import std/[sugar, strutils, times, strformat, sequtils, math]
import system
import options
import decimal/decimal

import types
import account

template maxFold(s: seq[auto]): untyped =
  s.foldl(if a > b: a else: b) 

proc toRateStringSequence(rates: seq[string]): string = 
  result = "["
  for i in 0..rates.high:
    let s = rates[i]
    if i == 0:
      result = result & s & ","
    else:
      result = " " & result & s
  result = result & "]"

proc printBalanceSheet(l: Ledger, length: int = -1): void =
  let maxBalanceLength = l.accounts.maxBalanceLength

  echo "\t--- BALANCE SHEET ---\n"
  echo ""
  l.accounts.assets.echoSelf(length, 0, maxBalanceLength)
    
  echo ""
  l.accounts.liabilities.echoSelf(length, 0, maxBalanceLength)

  echo ""
  l.accounts.equity.echoSelf(length, 0, maxBalanceLength)

  # echo ""
  # echo spaces(2) & "Exchange Accounts" & "\n"
  # for exchangeAccount in l.accounts.exchange:
  #   let namePadLength = maxLengthName - exchangeAccount.key.len
  #   let balancePadLength = maxLengthBalance -
  #       exchangeAccount.toBalanceString.len
  #   echo "| ", &"{exchangeAccount.key}", spaces(namePadLength), " | ", spaces(
  #       3 + balancePadLength), exchangeAccount.toBalanceString, " |"


proc printIncomeStatement(l: Ledger, reportingCurrencyKey: Option[string], length: int = -1): void =
  let maxBalanceLength = l.accounts.maxBalanceLength

  echo "\t--- INCOME STATEMENT ---\n"
  echo ""
  l.accounts.revenue.echoSelf(length, 0, maxBalanceLength)

  echo ""
  l.accounts.expenses.echoSelf(length, 0, maxBalanceLength)

  if reportingCurrencyKey.isSome():
    let currencyKey  = reportingCurrencyKey.get()
    let ni = (l.accounts.revenue.getBalance(currencyKey) - l.accounts.expenses.getBalance(currencyKey)).toAccountingString
    echo ""
    echo &"\t--- NET INCOME: {ni} {currencyKey} ---\n"


proc printExpenseReport(l: Ledger): void =
  echo "\t--- EXPENSE REPORT ---\n"

  let maxHeaderLength = l.transactions.filter(t => t.records.any(r => r.kind == AccountKind.Expense)).map(x => ("  " & x.date.format("yyyy-MM-dd") & " " & x.payee).len).maxFold
  # let maxKeyLength = l.transactions.map(x => x.records.map(r => r.accountKey.splitKey[1..^1].join(":").len).maxFold).maxFold
  let maxBalanceLength = l.transactions.map(x => x.records.map(r => r.amount.toAccountingString.len).maxFold).maxFold
  let total = l.transactions.map(x => x.records.filter(r => r.kind == AccountKind.Expense).map(r => r.amount).foldl(a + b, newDecimal("0.00"))).foldl(a + b, newDecimal("0.00"))

  for transaction in l.transactions:
    if transaction.records.filter(x => x.kind == AccountKind.Expense).len > 0:

      echo "| ", transaction.date.format("yyyy-MM-dd"), " - ", transaction.payee
      for record in transaction.records:
        if record.kind == AccountKind.Expense:
          let printableAccountKey = record.accountKey.splitKey[1..^1].join(":")
          let gap = max(1, maxHeaderLength - printableAccountKey.len)
          let balanceGap = max(1, maxBalanceLength - record.amount.toAccountingString.len)
          echo "|  - ", printableAccountKey, spaces(gap), record.currencyKey, spaces(balanceGap), record.amount.toAccountingString, " |"

      echo ""
  
  echo "TOTAL: ", total.toAccountingString


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


proc reportLedger*(ledger: Ledger, reportingCurrencyKey: Option[string], noJournal: bool = false) =
  let maxReportLength = ledger.accounts.maxReportLength
  echo ""
  printBalanceSheet(ledger, maxReportLength)
  echo ""

  echo ""
  printIncomeStatement(ledger, reportingCurrencyKey, maxReportLength)
  echo ""

  echo ""
  printExpenseReport(ledger)
  echo ""

  if not noJournal:
    echo ""
    printTransactionJournal(ledger.transactions)
    echo ""
