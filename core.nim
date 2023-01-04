import std/[sequtils, sugar, options]
import tables

import decimal/decimal
import results

import types

proc reverse*(str: string): string =
  result = ""
  for index in countdown(str.high, 0):
    result.add(str[index])

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
  let forwardKey = referenceCurrencyKey & ":" & securityCurrencyKey
  if forwardKey in transaction.conversionRates:
    return transaction.conversionRates[forwardKey]

  let reverseKey = forwardKey.reverse
  if reverseKey in transaction.conversionRates:
    return transaction.conversionRates[reverseKey] / 1

  # Change to Result Type
  raise newException(LogicError, "Conversion Rate Not Provided")

proc getExchangeAccount(exchangeAccounts: Table[string, ExchangeAccount],
    referenceCurrencyKey: string, securityCurrencyKey: string): tuple[
    exchangeAccount: ExchangeAccount, flipped: bool] =
  let forwardKey = referenceCurrencyKey & ":" & securityCurrencyKey
  if forwardKey in exchangeAccounts:
    return (exchangeAccounts[forwardKey], false)

  let reverseKey = forwardKey.reverse
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


proc convertTransaction(l: Ledger, transaction: Transaction,
    reportingCurrencyKey: string): Transaction =
  for i in 0..transaction.records.high:
    var record = transaction.records[i]
    if (record.kind == AccountKind.Revenue or record.kind ==
        AccountKind.Expense) and record.currencyKey != reportingCurrencyKey:
      let conversionRate = getConversionRate(transaction, record.currencyKey, reportingCurrencyKey)
      let (exchangeAccount, flipped) = getExchangeAccount(l.exchangeAccounts, reportingCurrencyKey, record.currencyKey)
      case record.kind:
        of AccountKind.Revenue:
          case record.norm:
            of Norm.Credit:
              if flipped:
                echo ""
              else:
                # The transaction directions should be correct
                # We made revenue in the security, therefore upon conversion we must increase the security balance as it represents an exposure
                let convertedAmount = (record.amount * conversionRate).quantize(record.amount)
                exchangeAccount.securityBalance += record.amount
                exchangeAccount.referenceBalance -= convertedAmount
                record.amount = convertedAmount
            of Norm.Debit:
              if flipped:
                echo ""
              else:
                let convertedAmount = (record.amount * conversionRate).quantize(record.amount)
                exchangeAccount.securityBalance -= record.amount
                exchangeAccount.referenceBalance += convertedAmount
                record.amount = convertedAmount
        of AccountKind.Expense:
          case record.norm:
            of Norm.Credit:
              if flipped:
                echo ""
              else:
                let convertedAmount = (record.amount * conversionRate).quantize(record.amount)
                exchangeAccount.securityBalance += record.amount
                exchangeAccount.referenceBalance -= convertedAmount
                record.amount = convertedAmount
            of Norm.Debit:
              if flipped:
                echo ""
              else:
                # The transaction directions should be correct
                # We record and expense in the security, therefore upon conversion we must decrease the security balance, reducing exposure
                let convertedAmount = (record.amount * conversionRate).quantize(record.amount)
                exchangeAccount.securityBalance -= record.amount
                exchangeAccount.referenceBalance += convertedAmount
                record.amount = convertedAmount
        else:
          echo ""



  return transaction
  # for record in transaction.records:
  #   if record.


proc aggregateTransaction(l: Ledger, transaction: Transaction): void =
  for record in transaction.records:
    let account = l.accounts[record.accountKey]

    if account.norm == record.norm:
      account.balance += record.amount
    else:
      account.balance -= record.amount

  if transaction.isMultiCurrency:
    let (referenceCurrencyKey, securityCurrencyKey) = extractCurrencies(transaction)
    # let conversionRate = getConversionRate(transaction, referenceCurrencyKey, securityCurrencyKey)
    let (exchangeAccount, flipped) = getExchangeAccount(l.exchangeAccounts,
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
      echo "Flipped"
      exchangeAccount.referenceBalance += securityDelta
      exchangeAccount.securityBalance += referenceDelta
    else:
      exchangeAccount.referenceBalance += referenceDelta
      exchangeAccount.securityBalance += securityDelta

proc aggregateTransactions*(l: Ledger, reportingCurrencyKey: Option[
    string]): Ledger =
  if reportingCurrencyKey.isSome():
    for transaction in l.transactions:
      aggregateTransaction(l, convertTransaction(l, transaction,
          reportingCurrencyKey.get()))
  else:
    for transaction in l.transactions:
      aggregateTransaction(l, transaction)

  return l

