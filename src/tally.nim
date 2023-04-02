import std/[os, times, parseopt, options, strutils]
import tables

import results

import tally/types
import tally/account
import tally/parse
import tally/core
import tally/report
import tally/verify
import tally/pdf/pdfReport

proc writeHelp() = echo "Help Command"
proc writeVersion() = echo "0.0.1"

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
  var buffer: Buffer = Buffer(
      index: 0,
      conversionRatesBuffer: @[],
      accounts: newAccountTree(parse("2022-01-01", "yyyy-MM-dd")), 
      currencies: initTable[string, Currency](),
      transactions: @[]
  )

  var ledger = transferBufferToLedger(parseFileIntoBuffer(filename, buffer))
  let checkTransactions = verifyTransactions(ledger.transactions, @[verifyMultiCurrencyValidCurrencies, verifyEqualDebitsAndCredits])

  if (checkTransactions.isOk):
    ledger = processLedger(ledger, reportingCurrencyKey)
    ledger.report(reportingCurrencyKey, expenseReport, journal)
    ledger.generateExpenseReport(filename.split("/")[^1].split(".")[0])
  else:
    echo checkTransactions.error

