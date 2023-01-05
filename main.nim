import std/[os, times, parseopt, options]
import tables

import results
import decimal/decimal # https://github.com/status-im/nim-decimal

import types
import parse
import core
import report

proc writeHelp() = echo "Help Command"
proc writeVersion() = echo "0.0.1"

# const filename = "./journal/test_2.txt"
var filename: string = ""
var reportingCurrencyKey = none(string)
var p = initOptParser(os.commandLineParams())

for kind, key, value in p.getopt():
  case kind
  of cmdArgument:
    filename = key
  of cmdLongOption, cmdShortOption:
    case key
    of "report", "r":
      reportingCurrencyKey = some(value)
    of "help", "h": writeHelp()
    of "version", "v": writeVersion()
  of cmdEnd: assert(false) # cannot happen

if filename == "":
  writeHelp()
else:
  var buffer: Buffer = Buffer(
      currencies: initTable[string, Currency](),
      accounts: initTable[string, OptionalAccount](), 
      conversionRatesBuffer: initTable[string, DecimalType](),
      exchangeAccounts: initTable[string, ExchangeAccount](),
      transactions: TransactionBuffer(lastDate: dateTime(0000, mJan, 1, 00, 00,
      00, 00, utc())))

  var ledger = transferBufferToLedger(parseFileIntoBuffer(filename, buffer))
  let checkTransactions = verifyTransactions(ledger.transactions, @[verifyMultiCurrencyValidCurrencies, verifyEqualDebitsAndCredits])

  if (checkTransactions.isOk):
    ledger = aggregateTransactions(ledger, reportingCurrencyKey)
    reportLedger(ledger)
  else:
    echo checkTransactions.error

