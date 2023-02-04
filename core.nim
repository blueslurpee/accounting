import std/[sequtils, sugar, options]
import tables
import decimal/decimal

import types
import account

proc isMultiCurrency*(transaction: Transaction): bool =
  let currencies = transaction.records.map(r => r.currencyKey).deduplicate
  result = currencies.len == 2


proc extractCurrencies*(transaction: Transaction): tuple[referenceCurrencyKey: string, securityCurrencyKey: string] =
  let currencies = transaction.records.map(r => r.currencyKey).deduplicate

  if currencies.len != 2:
    # Change to Result Type
    raise newException(LogicError, "More than 2 currencies not supported")

  return (currencies[0], currencies[1])


proc getConversionRate*(conversionRates: seq[tuple[key: string, rate: DecimalType]], referenceCurrencyKey: string, securityCurrencyKey: string, ): DecimalType =
  if referenceCurrencyKey == securityCurrencyKey: return newDecimal("1.00000")

  let queryKey = referenceCurrencyKey & ":" & securityCurrencyKey
  let converseQueryKey = securityCurrencyKey & ":" & referenceCurrencyKey

  for (key, rate) in conversionRates:
    if key == queryKey:
      return rate
    elif key == converseQueryKey:
      return (1 / rate).quantize(rate)

  # Change to Result Type
  raise newException(LogicError, "Conversion Rate Not Provided for Transaction")


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


proc mapRecord(r: Record, reportingCurrencyKey: string, conversionRates: seq[tuple[key: string, rate: DecimalType]]): Record = 
  if (r.kind == AccountKind.Revenue or r.kind == AccountKind.Expense):
    let conversionRate = conversionRates.getConversionRate(r.currencyKey, reportingCurrencyKey)
    let convertedAmount = (r.amount * conversionRate).quantize(r.amount)

    return Record(accountKey: r.accountKey, 
                  kind: r.kind, 
                  norm: r.norm, 
                  currencyKey: r.currencyKey, 
                  amount: r.amount, 
                  convertedCurrencyKey: reportingCurrencyKey, 
                  convertedAmount: convertedAmount)
  return r


proc postExchanges(ledger: Ledger, transaction: Transaction) = 
  if transaction.isMultiCurrency:
    let (referenceCurrencyKey, securityCurrencyKey) = transaction.extractCurrencies()
    let (exchangeAccount, flipped) = ledger.getExchangeAccount(referenceCurrencyKey, securityCurrencyKey)

    var referenceDebit, referenceCredit, securityDebit, securityCredit = newDecimal("0.00")
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
  for record in transaction.records:
    if (record.currencyKey != record.convertedCurrencyKey):
      let conversionRate = transaction.conversionRates.getConversionRate(record.currencyKey, record.convertedCurrencyKey)
      let (exchangeAccount, flipped) = ledger.getExchangeAccount(record.currencyKey, record.convertedCurrencyKey)
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
  for record in transaction.records:
    let accountO = ledger.accounts.findAccount(record.accountKey)

    if accountO.isNone:
      raise newException(LogicError, "Account not found")

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
      transaction.records = transaction.records.map(r => mapRecord(r, reportingCurrencyKey.get(), conversionRates))

    ledger.postExchanges(transaction)
    ledger.postConversions(transaction) # No effect if no reporting currency
    ledger.postTransaction(transaction)


