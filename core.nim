import std/[sequtils, strutils, sugar, options]
import tables

import decimal/decimal
import results

import types
import account

proc isMultiCurrency(transaction: Transaction): bool =
  let currencies = transaction.records.map(r => r.currencyKey).deduplicate
  result = currencies.len == 2

proc extractCurrencies(transaction: Transaction): tuple[
    referenceCurrencyKey: string, securityCurrencyKey: string] =
  let currencies = transaction.records.map(r => r.currencyKey).deduplicate

  if currencies.len != 2:
    # Change to Result Type
    raise newException(LogicError, "More than 2 currencies not supported")

  return (currencies[0], currencies[1])

proc getConversionRate(transaction: Transaction, referenceCurrencyKey: string,
    securityCurrencyKey: string): DecimalType =
  let queryKey = referenceCurrencyKey & ":" & securityCurrencyKey
  let converseQueryKey = securityCurrencyKey & ":" & referenceCurrencyKey

  for (key, rate) in transaction.conversionRates:
    if key == queryKey:
      return rate
    elif key == converseQueryKey:
      return (1 / rate).quantize(rate)

  # Change to Result Type
  raise newException(LogicError, "Conversion Rate Not Provided for Transaction: " & transaction.index.intToStr & " - " & transaction.payee)

proc getExchangeAccount(exchangeAccounts: Table[string, ExchangeAccount],
    referenceCurrencyKey: string, securityCurrencyKey: string): tuple[
    exchangeAccount: ExchangeAccount, flipped: bool] =
  let forwardKey = referenceCurrencyKey & ":" & securityCurrencyKey
  if forwardKey in exchangeAccounts:
    return (exchangeAccounts[forwardKey], false)

  let reverseKey = securityCurrencyKey & ":" & referenceCurrencyKey
  if reverseKey in exchangeAccounts:
    return (exchangeAccounts[reverseKey], true)

  # Change to Result Type
  raise newException(LogicError, "Could not find ExchangeAccount")


let verifyMultiCurrencyValidCurrencies * : Verifier = proc(
    transaction: Transaction): R =
  if not transaction.isMultiCurrency:
    return R.ok

  let currencies = transaction.records.map(r => r.currencyKey).deduplicate

  if currencies.len != 2:
    return R.err "Cannot have more than 2 currencies present in a transaction"

  return R.ok


let verifyEqualDebitsAndCredits*: Verifier = proc(transaction: Transaction): R =
  if not transaction.isMultiCurrency:
    let debits = transaction.records.filter(t => t.norm == Debit)
    let credits = transaction.records.filter(t => t.norm == Credit)

    let debitAmount = foldl(debits, a + b.amount, newDecimal("0.00"))
    let creditAmount = foldl(credits, a + b.amount, newDecimal("0.00"))

    if debitAmount == creditAmount:
      return R.ok
    else:
      echo "TRANSACTION ", transaction.date, " ", transaction.payee
      
      return R.err "Debits and Credits must sum to 0"
  else:
    let (referenceCurrencyKey, securityCurrencyKey) = extractCurrencies(transaction)
    let conversionRate = getConversionRate(transaction, referenceCurrencyKey, securityCurrencyKey)

    let referenceDebitAmount = transaction.records.filter(r =>
        r.currencyKey == referenceCurrencyKey and r.norm == Debit).foldl(a +
        b.amount, newDecimal("0.00"))
    let referenceCreditAmount = transaction.records.filter(r =>
        r.currencyKey == referenceCurrencyKey and r.norm == Credit).foldl(a +
        b.amount, newDecimal("0.00"))
    let referenceAbsDelta = (referenceDebitAmount - referenceCreditAmount).abs

    let securityDebitAmount = transaction.records.filter(r =>
        r.currencyKey == securityCurrencyKey and r.norm == Debit).foldl(a +
        b.amount, newDecimal("0.00"))
    let securityCreditAmount = transaction.records.filter(r =>
        r.currencyKey == securityCurrencyKey and r.norm == Credit).foldl(a +
        b.amount, newDecimal("0.00"))
    let securityAbsDelta = (securityDebitAmount - securityCreditAmount).abs

    if (securityAbsDelta / referenceAbsDelta).quantize(conversionRate) == conversionRate:
      return R.ok
    else:
      echo referenceAbsDelta, " ", securityAbsDelta, " ", securityAbsDelta /
          referenceAbsDelta, " ", conversionRate
      return R.err "Transaction amounts do not conform with provided conversion rate"


proc verifyTransactions*(transactions: seq[Transaction], verifiers: seq[Verifier]): R =
  result = R.ok

  block verify:
    for transaction in transactions:
      for verifier in verifiers:
        let check = verifier(transaction)
        if check.isErr:
          result = R.err(check.error)
          break verify


proc convertTransactionExchanges(l: Ledger): Ledger = 
  var ledger = l

  for i in 0..ledger.transactions.high:
    var transaction = ledger.transactions[i]

    if transaction.isMultiCurrency:
      let (referenceCurrencyKey, securityCurrencyKey) = extractCurrencies(transaction)
      let (exchangeAccount, flipped) = getExchangeAccount(l.accounts.exchange,
          referenceCurrencyKey, securityCurrencyKey)

      let referenceDebitAmount = transaction.records.filter(r =>
          r.currencyKey == referenceCurrencyKey and r.norm == Debit).foldl(a +
          b.amount, newDecimal("0.00"))
      let referenceCreditAmount = transaction.records.filter(r =>
          r.currencyKey == referenceCurrencyKey and r.norm == Credit).foldl(a +
          b.amount, newDecimal("0.00"))
      let referenceDelta = referenceDebitAmount - referenceCreditAmount

      let securityDebitAmount = transaction.records.filter(r =>
          r.currencyKey == securityCurrencyKey and r.norm == Debit).foldl(a +
          b.amount, newDecimal("0.00"))
      let securityCreditAmount = transaction.records.filter(r =>
          r.currencyKey == securityCurrencyKey and r.norm == Credit).foldl(a +
          b.amount, newDecimal("0.00"))
      let securityDelta = securityDebitAmount - securityCreditAmount

      if flipped:
        exchangeAccount.referenceBalance += securityDelta
        exchangeAccount.securityBalance += referenceDelta
      else:
        exchangeAccount.referenceBalance += referenceDelta
        exchangeAccount.securityBalance += securityDelta

  return ledger

proc convertTransactionReporting(l: Ledger, reportingCurrencyKey: string): Ledger =
  var ledger = l

  for i in 0..ledger.transactions.high:
    var transaction = ledger.transactions[i]

    for i in 0..transaction.records.high:
      var record = transaction.records[i]

      if (record.kind == AccountKind.Revenue or record.kind ==
          AccountKind.Expense) and record.currencyKey != reportingCurrencyKey:
        # echo "Reporting Currency: ", reportingCurrencyKey
        # echo "Searching for conversion rate for: ", record.currencyKey
        let conversionRate = getConversionRate(transaction, record.currencyKey, reportingCurrencyKey) # We want to convert to reference
        let (exchangeAccount, flipped) = getExchangeAccount(l.accounts.exchange, reportingCurrencyKey, record.currencyKey)
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

          record.amount = convertedAmount 
          record.accountKey = record.accountKey.replace(record.currencyKey, reportingCurrencyKey)
          record.currencyKey = reportingCurrencyKey

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
      
          record.amount = convertedAmount 
          record.accountKey = record.accountKey.replace(record.currencyKey, reportingCurrencyKey)
          record.currencyKey = reportingCurrencyKey

      echo "New Record: ", record 
      transaction.records[i] = record

    echo "New Transaction: ", transaction
    ledger.transactions[i] = transaction

  return ledger

proc aggregateTransactions(l: Ledger): Ledger =
  var ledger = l

  for t in ledger.transactions:
    var transaction = t

    for record in transaction.records:
      let accountO = l.accounts.findAccount(record.accountKey)

      if accountO.isSome:
        let account = accountO.get()
        let currencyKey = record.currencyKey

        if account.norm == record.norm:
          discard account.incrementBalance(currencyKey, record.amount)
        else:
          discard account.decrementBalance(currencyKey, record.amount)

  return ledger

proc aggregateLedger*(l: Ledger, reportingCurrencyKey: Option[
    string]): Ledger =
  var ledger = l

  if reportingCurrencyKey.isSome():
    ledger = ledger.convertTransactionExchanges().convertTransactionReporting(reportingCurrencyKey.get()).aggregateTransactions()
  else:
    ledger = ledger.convertTransactionExchanges().aggregateTransactions()

  return ledger

