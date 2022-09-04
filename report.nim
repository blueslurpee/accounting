import std/[sequtils, sugar, strutils, strformat, times]
import decimal/decimal
import tables

import types

proc printAccounts(accounts: seq[Account]): void =
  let nameLengths = accounts.map(x => len(x.key))
  let maxLengthName = nameLengths.foldl(if b > a: b else: a)

  let balanceLengths = accounts.map(x => len($x.balance))
  let maxLengthBalance = balanceLengths.foldl(if b > a: b else: a)

  let endGap = spaces(2)
  let midGap = spaces(3)

  let nameHeader = "Name"
  let namePadding = spaces(maxLengthName - nameHeader.len)

  let balanceHeader = "Balance"
  let balancePadding = spaces(5)

  echo endGap, nameHeader, namePadding, midGap, balanceHeader, balancePadding, endGap
  echo ""

  for account in accounts:
    let namePadLength = maxLengthName - account.key.len
    let balancePadLength = maxLengthBalance - len($account.balance)
    echo "| ", &"{account.key}", spaces(namePadLength), " | ", spaces(3 + balancePadLength), &"{account.balance}", " |"
  
  echo ""

proc printTransaction(transaction: Transaction) =
  echo &"Date: {transaction.date.getDateStr}"
  echo &"Payee: {transaction.payee}"
  echo &"Note: {transaction.note}"
  echo "Records:"
  for record in transaction.records:
    echo "\t", &"{record.accountKey} ", &"{record.norm} ", &"{record.amount} ",
        record.currency.string

proc reportLedger*(ledger: var Ledger) =
  let accountSeq = collect(newSeq):
    for key in ledger.accounts.keys: ledger.accounts[key]
  
  echo ""
  echo "--- ACCOUNT SUMMARY ---\n"
  printAccounts(accountSeq)
  
  echo "--- TRANSACTION JOURNAL ---\n"
  for transaction in ledger.transactions:
    echo &"TRANSACTION {transaction.index + 1}"
    printTransaction(transaction)
    echo ""