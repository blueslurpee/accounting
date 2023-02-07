import std/[sequtils, sugar]

import decimal/decimal
import results
import types
import core

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
    let conversionRate = transaction.conversionRates.getConversionRate(referenceCurrencyKey, securityCurrencyKey)

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


let verifyMultiCurrencyValidCurrencies * : Verifier = proc(
    transaction: Transaction): R =
  if not transaction.isMultiCurrency:
    return R.ok

  let currencies = transaction.records.map(r => r.currencyKey).deduplicate

  if currencies.len != 2:
    return R.err "Cannot have more than 2 currencies present in a transaction"

  return R.ok

proc verifyTransactions*(transactions: seq[Transaction], verifiers: seq[Verifier]): R =
  for transaction in transactions:
    for verifier in verifiers:
      let check = verifier(transaction)
      if check.isErr:
        return R.err(check.error)
  return R.ok
