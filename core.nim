import std/[sequtils, sugar, options, sets]
import tables

import decimal/decimal
import results

import types


proc isMultiCurrency(transaction: Transaction): bool =
  let currencies = transaction.records.map(r => r.currency.string).deduplicate
  result = currencies.len == 2


proc getExchangeAccountKey(transaction: Transaction): string =
  let currencies = transaction.records.map(r => r.currency.string).deduplicate
  result = currencies[0] & ":" & currencies[1]


proc extractConversionDetails(transaction: Transaction): tuple[
    reference: Currency, security: Currency, conversionRate: DecimalType] =
  let definingRecord: Record = transaction.records.filter(r =>
      r.conversionTarget.isSome and r.conversionRate.isSome)[0]
  result = (definingRecord.currency, definingRecord.conversionTarget.get(),
      definingRecord.conversionRate.get())


# let verifyRecordAccountsExist


let verifyMultiCurrencyValidCurrencies*: Verifier = proc(
    transaction: Transaction): R =
  if not transaction.isMultiCurrency:
    return R.ok

  let currencies = transaction.records.map(r => r.currency.string).deduplicate

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
      return R.err "Debits and Credits must sum to 0"
  else:
    let (reference, security, conversionRate) = extractConversionDetails(transaction)

    let referenceDebitAmount = transaction.records.filter(r =>
        r.currency.string == reference.string and r.norm == Debit).foldl(a +
        b.amount, newDecimal("0.00"))
    let referenceCreditAmount = transaction.records.filter(r =>
        r.currency.string == reference.string and r.norm == Credit).foldl(a +
        b.amount, newDecimal("0.00"))
    let referenceAbsDelta = (referenceDebitAmount - referenceCreditAmount).abs

    let securityDebitAmount = transaction.records.filter(r =>
        r.currency.string == security.string and r.norm == Debit).foldl(a +
        b.amount, newDecimal("0.00"))
    let securityCreditAmount = transaction.records.filter(r =>
        r.currency.string == security.string and r.norm == Credit).foldl(a +
        b.amount, newDecimal("0.00"))
    let securityAbsDelta = (securityDebitAmount - securityCreditAmount).abs

    if (securityAbsDelta / referenceAbsDelta).quantize(newDecimal("0.00")) == conversionRate:
      return R.ok
    else:
      echo referenceAbsDelta, " ", securityAbsDelta, " ", securityAbsDelta / referenceAbsDelta, " ", conversionRate
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


proc aggregateTransaction(accounts: Table[string, Account],
    exchangeAccounts: Table[string, ExchangeAccount],
    transaction: Transaction): void =
  for record in transaction.records:
    let account = accounts[record.accountKey]

    if account.norm == record.norm:
      account.balance += record.amount
    else:
      account.balance -= record.amount

  if transaction.isMultiCurrency:
    let exchangeAccountKey = getExchangeAccountKey(transaction)
    let exchangeAccount = exchangeAccounts[exchangeAccountKey]
    let (reference, security, _) = extractConversionDetails(transaction)

    let referenceDebitAmount = transaction.records.filter(r =>
        r.currency.string == reference.string and r.norm == Debit).foldl(a +
        b.amount, newDecimal("0.00"))
    let referenceCreditAmount = transaction.records.filter(r =>
        r.currency.string == reference.string and r.norm == Credit).foldl(a +
        b.amount, newDecimal("0.00"))
    let referenceDelta = referenceDebitAmount - referenceCreditAmount

    let securityDebitAmount = transaction.records.filter(r =>
        r.currency.string == security.string and r.norm == Debit).foldl(a +
        b.amount, newDecimal("0.00"))
    let securityCreditAmount = transaction.records.filter(r =>
        r.currency.string == security.string and r.norm == Credit).foldl(a +
        b.amount, newDecimal("0.00"))
    let securityDelta = securityDebitAmount - securityCreditAmount

    exchangeAccount.referenceBalance += referenceDelta
    exchangeAccount.securityBalance += securityDelta

proc aggregateTransactions*(currencies: OrderedSet[string], accounts: Table[string, Account],
    exchangeAccounts: Table[string, ExchangeAccount], transactions: seq[
    Transaction]): Ledger =
  var accounts = accounts
  var transactions = transactions

  for transaction in transactions:
    aggregateTransaction(accounts, exchangeAccounts, transaction)

  return (currencies: currencies, accounts: accounts, exchangeAccounts: exchangeAccounts,
      transactions: transactions)

