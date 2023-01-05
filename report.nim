import std/[sequtils, sugar, strutils, strformat, algorithm, times]
import decimal/decimal
import tables

import types

proc sortOnIndex(a, b: Currency):int = 
  (if a.index >= b.index: 1 else: -1)

proc toRateStringSequence(rates: seq[string]): string = 
  result = "["
  for i in 0..rates.high:
    let s = rates[i]
    if i == 0:
      result = result & s & ","
    else:
      result = " " & result & s
  result = result & "]"

proc toBalanceString(account: Account): string =
  return (if account.balance >= 0: $account.balance else: "(" &
      $account.balance.abs & ")")

proc toBalanceString(account: ExchangeAccount): string =
  let referenceBalanceString = (if account.referenceBalance >=
      0: $account.referenceBalance else: "(" & $account.referenceBalance.abs & ")")
  let securityBalanceString = (if account.securityBalance >=
      0: $account.securityBalance else: "(" & $account.securityBalance.abs & ")")
  return referenceBalanceString & ":" & securityBalanceString

proc toAccountingString(decimal: DecimalType): string =
  return (if decimal >= 0: $decimal else: "(" & $decimal.abs & ")")

proc printBalanceSheet(currencies: Table[string, Currency], accounts: seq[Account],
    exchangeAccounts: seq[ExchangeAccount]): void =
  let nameLengths = accounts.map(x => len(x.key)).concat(exchangeAccounts.map(
      x => len(x.key)))
  let maxLengthName = nameLengths.foldl(if b > a: b else: a)

  let balanceLengths = accounts.map(x => x.toBalanceString.len).concat(
      exchangeAccounts.map(x => x.toBalanceString.len))
  let maxLengthBalance = balanceLengths.foldl(if b > a: b else: a)

  let endGap = spaces(2)
  let midGap = spaces(3)

  let nameHeader = "Name"
  let namePadding = spaces(maxLengthName - nameHeader.len)

  let balanceHeader = "Balance"
  let balancePadding = spaces(5)

  echo "\t--- BALANCE SHEET ---\n"
  echo endGap, nameHeader, namePadding, midGap, balanceHeader, balancePadding, endGap

  echo ""
  echo spaces(2) & "Assets" & "\n"  
  for value in currencies.values.toSeq.sorted(sortOnIndex):
    let currencyKey = value.key

    for account in accounts.filter(a => a.kind == AccountKind.Asset and a.currencyKey == currencyKey):
      let namePadLength = maxLengthName - account.key.len
      let balancePadLength = maxLengthBalance - account.toBalanceString.len
      echo "| ", &"{account.key}", spaces(namePadLength), " | ", spaces(3 +
          balancePadLength), account.toBalanceString, " |"
    
  echo ""
  echo spaces(2) & "Liabilities" & "\n"  
  for value in currencies.values.toSeq.sorted(sortOnIndex):
    let currencyKey = value.key

    for account in accounts.filter(a => a.kind == AccountKind.Liability and a.currencyKey == currencyKey):
      let namePadLength = maxLengthName - account.key.len
      let balancePadLength = maxLengthBalance - account.toBalanceString.len
      echo "| ", &"{account.key}", spaces(namePadLength), " | ", spaces(3 +
          balancePadLength), account.toBalanceString, " |"


  echo ""
  echo spaces(2) & "Equity" & "\n"
  for value in currencies.values.toSeq.sorted(sortOnIndex):
    let currencyKey = value.key
    let currencyAssets = accounts.filter(a => a.kind == AccountKind.Asset and
        a.currencyKey == currencyKey).foldl(a + b.balance, newDecimal("0.00"))
    let currencyLiabilities = accounts.filter(a => a.kind ==
        AccountKind.Liability and a.currencyKey == currencyKey).foldl(a +
        b.balance, newDecimal("0.00"))
    let currencyEquity = currencyAssets - currencyLiabilities

    let namePadLength = maxLengthName - currencyKey.len
    let balancePadLength = maxLengthBalance -
        currencyEquity.toAccountingString.len

    echo "| ", currencyKey, spaces(namePadLength), " | ", spaces(3 +
        balancePadLength), currencyEquity.toAccountingString, " |"

  echo ""
  echo spaces(2) & "Exchange Accounts" & "\n"
  for exchangeAccount in exchangeAccounts:
    let namePadLength = maxLengthName - exchangeAccount.key.len
    let balancePadLength = maxLengthBalance -
        exchangeAccount.toBalanceString.len
    echo "| ", &"{exchangeAccount.key}", spaces(namePadLength), " | ", spaces(
        3 + balancePadLength), exchangeAccount.toBalanceString, " |"


proc printIncomeStatement(currencies: Table[string, Currency], accounts: seq[
    Account], exchangeAccounts: seq[ExchangeAccount]): void =
  let maxLengthName = currencies.keys.toSeq.map(x => x.len).foldl(if b > a: b else: a)
  let maxLengthRevenue = accounts.map(a => a.toBalanceString.len).foldl(if b > a: b else: a, 0)
  let maxLengthExpense = accounts.map(a => a.toBalanceString.len).foldl(if b > a: b else: a, 0)
  let maxLengthNetIncome = currencies.keys.toSeq.map(x => accounts.filter(a =>
      (a.kind == AccountKind.Revenue or a.kind == AccountKind.Expense) and a.currencyKey == x).map(a => (if a.kind == AccountKind.Revenue: a.balance else: -1 * a.balance)).foldl(a + b, newDecimal("0.00"))).map(decimal => 
      decimal.toAccountingString.len).foldl(if b > a: b else: a)

  let endGap = spaces(2)
  let midGap = spaces(3)

  let nameHeader = "Name"
  let namePadding = spaces(max(maxLengthName - nameHeader.len, 1))

  let revenueHeader = "Revenue"
  let revenuePadding = spaces(max(maxLengthRevenue - revenueHeader.len, 5))

  let expenseHeader = "Expense"
  let expensePadding = spaces(max(maxLengthExpense - expenseHeader.len, 5))

  let netIncomeHeader = "Net Income"
  let netIncomePadding = spaces(max(maxLengthNetIncome - netIncomeHeader.len, 5))

  echo "\t--- INCOME STATEMENT ---\n"
  echo endGap, nameHeader, namePadding, midGap, revenueHeader, revenuePadding,
      expenseHeader, expensePadding, netIncomeHeader, netIncomePadding, endGap
  echo ""

  for key in currencies.keys:
    let currencyKey = currencies[key].key
    let currencyRevenue = accounts.filter(a => a.kind == AccountKind.Revenue and
        a.currencyKey == currencyKey).foldl(a + b.balance, newDecimal("0.00"))
    let currencyExpense = accounts.filter(a => a.kind == AccountKind.Expense and
        a.currencyKey == currencyKey).foldl(a + b.balance, newDecimal("0.00"))
    let currencyNetIncome = currencyRevenue - currencyExpense

    let namePadLength = maxLengthName - currencyKey.len
    let revenuePadLength = maxLengthRevenue -
        currencyRevenue.toAccountingString.len
    let expensePadLength = maxLengthExpense -
        currencyExpense.toAccountingString.len
    let netIncomePadLength = maxLengthNetIncome - currencyNetIncome.toAccountingString.len

    echo "| ", currencyKey, spaces(namePadLength), " | ", spaces(3 +
        revenuePadLength), currencyRevenue.toAccountingString, " | ", spaces(3 +
        expensePadLength), currencyExpense.toAccountingString, " | ", spaces(3 + 
        netIncomePadLength), currencyNetIncome.toAccountingString, " |"


proc printTransactionJournal(transactions: seq[Transaction]) =
  echo "\t--- TRANSACTION JOURNAL ---\n"

  for transaction in transactions:
    let transactionConversionRates = collect:
      for key, value in transaction.conversionRates.pairs: &"{key} -> {value}"

    echo spaces(1), &"Conversion Rates: {transactionConversionRates.toRateStringSequence}"
    echo spaces(1), &"Date: {transaction.date.getDateStr}"
    echo spaces(1), &"Payee: {transaction.payee}"
    echo spaces(1), &"Note: {transaction.note}"
    echo spaces(1), "Records:"

    for record in transaction.records:
      echo "\t", &"{record.accountKey} ", &"{record.norm} ",
          &"{record.amount} ", record.currencyKey
    
    echo ""


proc reportLedger*(ledger: var Ledger) =
  let accountSeq = collect(newSeq):
    for key in ledger.accounts.keys: ledger.accounts[key]

  let exchangeAccountSeq = collect(newSeq):
    for key in ledger.exchangeAccounts.keys: ledger.exchangeAccounts[key]

  echo ""
  printBalanceSheet(ledger.currencies, accountSeq, exchangeAccountSeq)
  echo ""

  echo ""
  printIncomeStatement(ledger.currencies, accountSeq, exchangeAccountSeq)
  echo ""

  echo ""
  printTransactionJournal(ledger.transactions)
  echo ""
