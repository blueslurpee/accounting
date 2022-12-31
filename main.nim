import std/[times]
import tables

import results

import types
import parse
import core
import report

const filename = "./journal/test.txt"

var buffer: Buffer = Buffer(
    currencies: initTable[string, Currency](),
    accounts: initTable[string, OptionalAccount](), 
    exchangeAccounts: initTable[string, ExchangeAccount](),
    transactions: TransactionBuffer(lastDate: dateTime(0000, mJan, 1, 00, 00,
    00, 00, utc())))

var ledger = transferBufferToLedger(parseFileIntoBuffer(filename, buffer))
let checkTransactions = verifyTransactions(ledger.transactions, @[verifyMultiCurrencyValidCurrencies, verifyEqualDebitsAndCredits])

if (checkTransactions.isOk):
  ledger = aggregateTransactions(ledger.currencies, ledger.accounts, ledger.exchangeAccounts, ledger.transactions)
  reportLedger(ledger)
else:
  echo checkTransactions.error

