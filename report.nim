import std/[sequtils, sugar, strutils, strformat, algorithm, times]
import decimal/decimal
import tables

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

proc printBalanceSheet(l: Ledger): void =
  echo "\t--- BALANCE SHEET ---\n"
  # echo endGap, nameHeader, namePadding, midGap, balanceHeader, balancePadding, endGap

  echo ""
  l.accounts.assets.echoSelf()
    
  echo ""
  l.accounts.liabilities.echoSelf()

  echo ""
  l.accounts.equity.echoSelf()

  # echo ""
  # echo spaces(2) & "Exchange Accounts" & "\n"
  # for exchangeAccount in l.accounts.exchange:
  #   let namePadLength = maxLengthName - exchangeAccount.key.len
  #   let balancePadLength = maxLengthBalance -
  #       exchangeAccount.toBalanceString.len
  #   echo "| ", &"{exchangeAccount.key}", spaces(namePadLength), " | ", spaces(
  #       3 + balancePadLength), exchangeAccount.toBalanceString, " |"


proc printIncomeStatement(l: Ledger): void =
  echo "\t--- INCOME STATEMENT ---\n"

  echo ""
  l.accounts.revenue.echoSelf()

  echo ""
  l.accounts.expenses.echoSelf()


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


proc reportLedger*(ledger: Ledger, noJournal: bool = false) =
  echo ""
  printBalanceSheet(ledger)
  echo ""

  echo ""
  printIncomeStatement(ledger)
  echo ""

  if not noJournal:
    echo ""
    printTransactionJournal(ledger.transactions)
    echo ""
