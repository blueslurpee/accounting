# import std/[times, tables]
# import options
# import types
# import account
# import parse
# import core
# import report

# import results

# proc getLedgerFromFile*(filepath: string): Ledger =
#     var buffer: Buffer = Buffer(
#       index: 0,
#       conversionRatesBuffer: @[],
#       accounts: newAccountTree(parse("2022-01-01", "yyyy-MM-dd")), 
#       currencies: initTable[string, Currency](),
#       transactions: @[]
#     )

#     var ledger = transferBufferToLedger(parseFileIntoBuffer(filepath, buffer))
#     let checkTransactions = verifyTransactions(ledger.transactions, @[verifyMultiCurrencyValidCurrencies, verifyEqualDebitsAndCredits])

#     if (checkTransactions.isOk):
#         ledger = aggregateTransactions(ledger, some("USD"))
#         reportLedger(ledger, some("USD"), true)