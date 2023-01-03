import std/[os, times, parseopt, options]
import tables

import results

import types
import parse
import core
import report

proc writeHelp() = echo "Help Command"
proc writeVersion() = echo "0.0.1"

# const filename = "./journal/test_2.txt"
var filename: string = ""
var p = initOptParser(os.commandLineParams())

for kind, key, val in p.getopt():
  case kind
  of cmdArgument:
    filename = key
  of cmdLongOption, cmdShortOption:
    case key
    of "help", "h": writeHelp()
    of "version", "v": writeVersion()
  of cmdEnd: assert(false) # cannot happen

if filename == "":
  writeHelp()
else:
  echo "FILE ", filename 

  var buffer: Buffer = Buffer(
      currencies: initTable[string, Currency](),
      accounts: initTable[string, OptionalAccount](), 
      exchangeAccounts: initTable[string, ExchangeAccount](),
      transactions: TransactionBuffer(lastDate: dateTime(0000, mJan, 1, 00, 00,
      00, 00, utc())))

  var ledger = transferBufferToLedger(parseFileIntoBuffer(filename, buffer))
  let checkTransactions = verifyTransactions(ledger.transactions, @[verifyMultiCurrencyValidCurrencies, verifyEqualDebitsAndCredits])

  if (checkTransactions.isOk):
    ledger = aggregateTransactions(ledger, some("USD"))
    reportLedger(ledger)
  else:
    echo checkTransactions.error

