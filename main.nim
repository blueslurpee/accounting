import std/[strformat, times, sequtils, sugar]
import tables

import decimal/decimal
import results

import types
import parse

const filename = "./test.txt"

var buffer: Buffer = Buffer(accounts: initTable[string, OptionalAccountData](),
    transactions: TransactionBuffer(lastDate: dateTime(0000, mJan, 1, 00, 00,
    00, 00, utc())))

let verifyEqualDebitsAndCredits: Verifier = proc(transaction: Transaction): R =
  let debits = transaction.records.filter(t => t.norm == Debit)
  let credits = transaction.records.filter(t => t.norm == Credit)

  let startAmount = newDecimal("0.00")
  let debitAmount = foldl(debits, a + b.amount, startAmount)
  let creditAmount = foldl(credits, a + b.amount, startAmount)

  if debitAmount == creditAmount:
    return R.ok
  else:
    return R.err "Debits and Credits must sum to 0"

proc verifyTransactions(transactions: seq[Transaction], verifiers: seq[Verifier]): R =
  result = R.ok

  block verify:
    for transaction in transactions:
      for verifier in verifiers:
        let check = verifier(transaction)
        if check.isErr:
          result = R.err(check.error)
          break verify

proc printTransaction(transaction: Transaction) =
  echo &"Date: {transaction.date.getDateStr}"
  echo &"Payee: {transaction.payee}"
  echo &"Note: {transaction.note}"
  echo "Records:"
  for record in transaction.records:
    echo "\t", &"{record.account} ", &"{record.norm} ", &"{record.amount} ",
        record.currency.string

let (accounts, transactions) = transferBuffer(parseFileIntoBuffer(filename, buffer))
let checkTransactions = verifyTransactions(transactions, @[verifyEqualDebitsAndCredits])

if (checkTransactions.isOk):
  echo "Accounts\n"
  echo accounts

  echo "Transactions\n"
  for transaction in transactions:
    echo &"--- TRANSACTION {transaction.index + 1} ---"
    printTransaction(transaction)
else:
  echo checkTransactions.error
