import std/[os, parseopt, options, strutils, strformat]

import results

import tally/types
import tally/parse
import tally/core
import tally/report
import tally/verify
import tally/pdf/pdfReport

let VERSION = "0.0.1"
proc writeVersion() = echo VERSION
proc writeHelp() = echo &"""
Tally - Plain Text Accounting in Nim Version {VERSION}
Copyright (c) 2022-2023 by Corey Bothwell

  tally [options] [input_file] 

Options:
  -r, --report:CURRENCY_KEY         report in specified currency
  -e, --expense-report              show expense report in output
  -j, --journal                     show transaction journal in output 
  -h, --help                        show this help
  -v, --version                     show version"""

# const filename = "./journal/test_2.txt"
var filename: string = ""
var reportingCurrencyKey = none(string)
var expenseReport: bool = false
var journal: bool = false
var p = initOptParser(os.commandLineParams())

for kind, key, value in p.getopt():
  case kind
  of cmdArgument:
    filename = key
  of cmdLongOption, cmdShortOption:
    case key
    of "report", "r":
      reportingCurrencyKey = some(value)
    of "expense-report", "e":
      expenseReport = true
    of "journal", "j":
      journal = true
    of "help", "h": writeHelp()
    of "version", "v": writeVersion()
  of cmdEnd: assert(false) # cannot happen

if filename == "":
  writeHelp()
else:
  var ledger = parseLedger(filename)
  let checkTransactions = verifyTransactions(ledger.transactions, @[verifyMultiCurrencyValidCurrencies, verifyEqualDebitsAndCredits])

  if (checkTransactions.isOk):
    ledger = processLedger(ledger, reportingCurrencyKey)
    ledger.report(reportingCurrencyKey, expenseReport, journal)
    ledger.generateExpenseReport(filename.split("/")[^1].split(".")[0])
  else:
    echo checkTransactions.error

