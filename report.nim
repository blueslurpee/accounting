import std/[sequtils, sugar, strutils, strformat, times, sets]
import decimal/decimal
import tables

import types

proc toBalanceString(account: Account): string =
  return (if account.balance >= 0: $account.balance else: "(" & $account.balance.abs & ")")

proc toBalanceString(account: ExchangeAccount): string =
  let referenceBalanceString = (if account.referenceBalance >= 0: $account.referenceBalance else: "(" & $account.referenceBalance.abs & ")")
  let securityBalanceString = (if account.securityBalance >= 0: $account.securityBalance else: "(" & $account.securityBalance.abs & ")")
  return referenceBalanceString & ":" & securityBalanceString

proc toAccountingString(decimal: DecimalType): string =
  return (if decimal >= 0: $decimal else: "(" & $decimal.abs & ")")

proc printAccounts(accounts: seq[Account], exchangeAccounts: seq[ExchangeAccount]): void =
  let nameLengths = accounts.map(x => len(x.key)).concat(exchangeAccounts.map(x => len(x.key)))
  let maxLengthName = nameLengths.foldl(if b > a: b else: a)

  let balanceLengths = accounts.map(x => x.toBalanceString.len).concat(exchangeAccounts.map(x => x.toBalanceString.len))
  let maxLengthBalance = balanceLengths.foldl(if b > a: b else: a)

  let endGap = spaces(2)
  let midGap = spaces(3)

  let nameHeader = "Name"
  let namePadding = spaces(maxLengthName - nameHeader.len)

  let balanceHeader = "Balance"
  let balancePadding = spaces(5)

  echo "--- BALANCE SHEET ---\n"
  echo endGap, nameHeader, namePadding, midGap, balanceHeader, balancePadding, endGap
  echo ""

  for account in accounts:
    let namePadLength = maxLengthName - account.key.len
    let balancePadLength = maxLengthBalance - account.toBalanceString.len
    echo "| ", &"{account.key}", spaces(namePadLength), " | ", spaces(3 + balancePadLength), account.toBalanceString, " |"

  for exchangeAccount in exchangeAccounts:
    let namePadLength = maxLengthName - exchangeAccount.key.len
    let balancePadLength = maxLengthBalance - exchangeAccount.toBalanceString.len
    echo "| ", &"{exchangeAccount.key}", spaces(namePadLength), " | ", spaces(3 + balancePadLength), exchangeAccount.toBalanceString, " |"


proc printAggregates(currencies: OrderedSet[string], accounts: seq[Account], exchangeAccounts: seq[ExchangeAccount]): void =
  echo spaces(2) & "TOTALS" & "\n"
  for currency in currencies:
    let currencyAssets = accounts.filter(a => a.kind == AccountKind.Asset and a.currency.string == currency).foldl(a +
        b.balance, newDecimal("0.00"))
    let currencyLiabilities = accounts.filter(a => a.kind == AccountKind.Liability and a.currency.string == currency).foldl(a +
        b.balance, newDecimal("0.00"))
    let currencyEquity = currencyAssets - currencyLiabilities

    echo spaces(2) & currency & " " & currencyEquity.toAccountingString


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

  let exchangeAccountSeq = collect(newSeq):
    for key in ledger.exchangeAccounts.keys: ledger.exchangeAccounts[key]
  
  echo ""
  printAccounts(accountSeq, exchangeAccountSeq)
  echo ""

  echo ""
  printAggregates(ledger.currencies, accountSeq, exchangeAccountSeq)
  echo ""

  echo "--- TRANSACTION JOURNAL ---\n"
  for transaction in ledger.transactions:
    echo &"TRANSACTION {transaction.index + 1}"
    printTransaction(transaction)
    echo ""