import std/[sugar, strutils, times, strformat]
import options
import decimal/decimal

import types
import account

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
  echo "\t--- BALANCE SHEET ---\n"
  echo ""
  l.accounts.assets.echoSelf(length)
    
  echo ""
  l.accounts.liabilities.echoSelf(length)

  echo ""
  l.accounts.equity.echoSelf(length)

  # echo ""
  # echo spaces(2) & "Exchange Accounts" & "\n"
  # for exchangeAccount in l.accounts.exchange:
  #   let namePadLength = maxLengthName - exchangeAccount.key.len
  #   let balancePadLength = maxLengthBalance -
  #       exchangeAccount.toBalanceString.len
  #   echo "| ", &"{exchangeAccount.key}", spaces(namePadLength), " | ", spaces(
  #       3 + balancePadLength), exchangeAccount.toBalanceString, " |"


proc printIncomeStatement(l: Ledger, reportingCurrencyKey: Option[string], length: int = -1): void =
  echo "\t--- INCOME STATEMENT ---\n"
  echo ""
  l.accounts.revenue.echoSelf(length)

  echo ""
  l.accounts.expenses.echoSelf(length)

  if reportingCurrencyKey.isSome():
    let ni = (l.accounts.revenue.getBalance("USD") - l.accounts.expenses.getBalance("USD")).toAccountingString
    echo ""
    echo &"\t--- NET INCOME: {ni} {reportingCurrencyKey.get()} ---\n"


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

  if not noJournal:
    echo ""
    printTransactionJournal(ledger.transactions)
    echo ""
