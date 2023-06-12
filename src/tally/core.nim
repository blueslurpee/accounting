import std/[sequtils, sugar, options, strformat]
import tables
import decimal/decimal
import results

import types
import account

type DecimalR = Result[DecimalType, string]
type RecordR = Result[Record, string]

func isMultiCurrency*(transaction: Transaction): bool =
  ## Does a transaction involve more than one currency
  let currencies = transaction.records.map(r => r.currencyKey).deduplicate
  result = currencies.len == 2


func extractCurrencies*(transaction: Transaction): tuple[
    referenceCurrencyKey: string, securityCurrencyKey: string] =
  let currencies = transaction.records.map(r => r.currencyKey).deduplicate

  if currencies.len != 2:
    # Change to Result Type
    raise newException(LogicError, "More than 2 currencies not supported")

  return (currencies[0], currencies[1])


proc getConversionRate*(conversionRates: seq[tuple[key: string,
    rate: DecimalType]], referenceCurrencyKey: string,
    securityCurrencyKey: string): DecimalR =
  if referenceCurrencyKey == securityCurrencyKey: return DecimalR.ok newDecimal("1.00000")

  let queryKey = referenceCurrencyKey & ":" & securityCurrencyKey
  let converseQueryKey = securityCurrencyKey & ":" & referenceCurrencyKey

  for (key, rate) in conversionRates:
    if key == queryKey:
      return DecimalR.ok rate
    elif key == converseQueryKey:
      return DecimalR.ok (1 / rate).quantize(rate)

  return DecimalR.err "Could not get conversion rate"


proc getExchangeAccount(
    ledger: Ledger,
    referenceCurrencyKey: string,
    securityCurrencyKey: string
  ): tuple[exchangeAccount: ExchangeAccount, flipped: bool] =
  let forwardKey = referenceCurrencyKey & ":" & securityCurrencyKey
  if forwardKey in ledger.accounts.exchange:
    return (ledger.accounts.exchange[forwardKey], false)

  let reverseKey = securityCurrencyKey & ":" & referenceCurrencyKey
  if reverseKey in ledger.accounts.exchange:
    return (ledger.accounts.exchange[reverseKey], true)

  # Change to Result Type
  raise newException(LogicError, "Could not find ExchangeAccount")


proc mapRecord(r: Record, reportingCurrencyKey: string, conversionRates: seq[
    tuple[key: string, rate: DecimalType]]): RecordR =
  ## Maps a transaction record given:
  ## - the record
  ## - a reporting currency key
  ## - the provided conversion rates
  ## The appled conversion is taken from the conversion rate which corresponds to the record currency and the reporting currency.
  ## If not found, the original record is returned.
  ## The return value is a result type
  if (r.kind == AccountKind.Revenue or r.kind == AccountKind.Expense):
    let conversionRate = ?(conversionRates.getConversionRate(r.currencyKey,
        reportingCurrencyKey))
    let convertedAmount = (r.amount * conversionRate).quantize(r.amount)

    return RecordR.ok Record(
                        accountKey: r.accountKey,
                        kind: r.kind,
                        norm: r.norm,
                        currencyKey: r.currencyKey,
                        amount: r.amount,
                        convertedCurrencyKey: reportingCurrencyKey,
                        convertedAmount: convertedAmount,
                        doc: r.doc
      )
  return RecordR.ok r


proc postExchanges(ledger: Ledger, transaction: Transaction) =
  ## In order to correctly handle multiple currencies without the need for a single base currency,
  ## transactions that involve more than one currency need to pass their exchanges through
  ## special "currency-exchange" accounts. These allow currency exchanges to be tracked like any other
  ## account and reported in the reporting currency. Additionally, these exchange accounts support unrealized gains/losses on
  ## foreign exchange. For more information, see: https://www.mathstat.dal.ca/~selinger/accounting/tutorial.html#2.2
  if transaction.isMultiCurrency:
    let (referenceCurrencyKey, securityCurrencyKey) = transaction.extractCurrencies()
    let (exchangeAccount, flipped) = ledger.getExchangeAccount(
        referenceCurrencyKey, securityCurrencyKey)

    var referenceDebit, referenceCredit, securityDebit,
      securityCredit = newDecimal("0.00")
    for record in transaction.records:
      if (record.currencyKey == referenceCurrencyKey and record.norm == Debit):
        referenceDebit += record.amount
      if (record.currencyKey == referenceCurrencyKey and record.norm == Credit):
        referenceCredit += record.amount
      if (record.currencyKey == securityCurrencyKey and record.norm == Debit):
        securityDebit += record.amount
      if (record.currencyKey == securityCurrencyKey and record.norm == Credit):
        securityCredit += record.amount

    let referenceDelta = referenceDebit - referenceCredit
    let securityDelta = securityDebit - securityCredit

    # How do these mutate the balances of the exchange accounts with value semantics?
    if flipped:
      exchangeAccount.referenceBalance += securityDelta
      exchangeAccount.securityBalance += referenceDelta
    else:
      exchangeAccount.referenceBalance += referenceDelta
      exchangeAccount.securityBalance += securityDelta


proc postConversions(ledger: Ledger, transaction: Transaction) =
  ## This procedure is similar to the above but is solely for reporting in a "unified" currency.
  ## Instead operating over whole transactions, it operates 'per record' when they are converted
  ## to the reporting currency. The exchange accounts record the conversion process so that the conversion remains
  ## "well defined" and the appropriate gain/loss from foreign exchange can be calculated.
  for record in transaction.records:
    if (record.currencyKey != record.convertedCurrencyKey):
      let conversionRateR = transaction.conversionRates.getConversionRate(
          record.currencyKey, record.convertedCurrencyKey)

      if conversionRateR.isOk:
        let conversionRate = conversionRateR.get()
        let (exchangeAccount, flipped) = ledger.getExchangeAccount(
            record.currencyKey, record.convertedCurrencyKey)
        let convertedAmount = (record.amount * conversionRate).quantize(record.amount)

        if record.kind == AccountKind.Revenue:
          case record.norm:
            of Norm.Credit:
              if flipped:
                exchangeAccount.referenceBalance += record.amount
                exchangeAccount.securityBalance -= convertedAmount
              else:
                # The canonical case
                # The transaction directions should be correct
                # We made revenue in the security, therefore upon conversion we must increase the security balance as it represents an exposure
                exchangeAccount.securityBalance += record.amount
                exchangeAccount.referenceBalance -= convertedAmount
            of Norm.Debit:
              if flipped:
                exchangeAccount.referenceBalance -= record.amount
                exchangeAccount.securityBalance += convertedAmount
              else:
                exchangeAccount.securityBalance -= record.amount
                exchangeAccount.referenceBalance += convertedAmount

        if record.kind == AccountKind.Expense:
          case record.norm:
            of Norm.Credit:
              if flipped:
                exchangeAccount.referenceBalance += record.amount
                exchangeAccount.securityBalance -= convertedAmount
              else:
                exchangeAccount.securityBalance += record.amount
                exchangeAccount.referenceBalance -= convertedAmount
            of Norm.Debit:
              if flipped:
                exchangeAccount.referenceBalance -= record.amount
                exchangeAccount.securityBalance += convertedAmount
              else:
                # The canonical case
                # The transaction directions should be correct
                # We record and expense in the security, therefore upon conversion we must decrease the security balance, reducing exposure
                exchangeAccount.securityBalance -= record.amount
                exchangeAccount.referenceBalance += convertedAmount


proc postTransaction(ledger: Ledger, transaction: Transaction) =
  # Standard accounting equation, increment/decrement accounts based upon transactions and their associated records/
  for record in transaction.records:
    let accountO = ledger.accounts.findAccount(record.accountKey)

    if accountO.isNone:
      raise newException(LogicError, &"Account: {record.accountKey} not found")

    let account = accountO.get()
    let currencyKey = record.convertedCurrencyKey

    if account.norm == record.norm:
      discard account.incrementBalance(currencyKey, record.convertedAmount)
    else:
      discard account.decrementBalance(currencyKey, record.convertedAmount)


proc processLedger*(ledger: Ledger, reportingCurrencyKey: Option[
    string]): Ledger =
  result = ledger
  for transaction in result.transactions.mitems:
    if reportingCurrencyKey.isSome():
      let conversionRates = transaction.conversionRates
      let mappedRecords = transaction.records.map(r => mapRecord(r,
          reportingCurrencyKey.get(), conversionRates))

      if mappedRecords.all(r => r.isOk):
        # TODO, handle case where not mapped
        transaction.records = mappedRecords.map(r => r.get())

    ledger.postExchanges(transaction)
    ledger.postConversions(transaction) # No effect if no reporting currency
    ledger.postTransaction(transaction)


