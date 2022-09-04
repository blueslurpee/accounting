import std/[sequtils, sugar]
import tables

import decimal/decimal
import results

import types


let verifyEqualDebitsAndCredits*: Verifier = proc(transaction: Transaction): R =
  let debits = transaction.records.filter(t => t.norm == Debit)
  let credits = transaction.records.filter(t => t.norm == Credit)

  let startAmount = newDecimal("0.00")
  let debitAmount = foldl(debits, a + b.amount, startAmount)
  let creditAmount = foldl(credits, a + b.amount, startAmount)

  if debitAmount == creditAmount:
    return R.ok
  else:
    return R.err "Debits and Credits must sum to 0"

proc verifyTransactions*(transactions: seq[Transaction], verifiers: seq[Verifier]): R =
  result = R.ok

  block verify:
    for transaction in transactions:
      for verifier in verifiers:
        let check = verifier(transaction)
        if check.isErr:
          result = R.err(check.error)
          break verify

proc aggregateTransactions*(accounts: Table[string, Account], transactions: seq[Transaction]): Ledger = 
  var accounts = accounts
  var transactions = transactions

  for transaction in transactions:
    for record in transaction.records:
      let account = accounts[record.accountKey]
      if account.norm == record.norm:
        account.balance += record.amount
      else:
        account.balance -= record.amount

  return (accounts: accounts, transactions: transactions)