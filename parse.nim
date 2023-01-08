import std/[times, options, sets]
import strutils, tables
import npeg # https://github.com/zevv/npeg
import decimal/decimal # https://github.com/status-im/nim-decimal
import results # https://github.com/arnetheduck/nim-result

import types
import account

proc key*(account: AccountNode): string =
  var current = account

  while current.kind != Leaf:
    result.add(current.v & ":")
    current = current.succ

  result.add(current.v)

proc generateAccountNodes(nodeList: seq[string]): AccountNode =
  if nodeList.len == 1:
    return AccountNode(kind: AccountNodeType.Leaf, v: nodeList[0])
  elif nodeList.len > 1:
    return AccountNode(kind: AccountNodeType.Parent, v: nodeList[0],
        succ: generateAccountNodes(nodeList[1 .. ^1]))
  else:
    raise newException(RangeDefect, "Invalid Account Node List")

proc parseAccount(key: string, open: DateTime): Account =
  let elements = key.split(":")
  let kind = parseKind(elements[0])

  return newAccount(key=key, name=key, kind=kind, norm=kind.toNorm, open=open)

proc parseNorm(norm: string): Norm =
  case norm
  of "D":
    return Debit
  of "C":
    return Credit
  else:
    raise newException(ValueError, "Invalid Norm")

proc parseFileIntoBuffer*(filename: string, buffer: Buffer): Buffer =
  var buffer = buffer
  var currencyIndex = 0

  let parser = peg("input", buffer: Buffer):
    input <- *Space * *( > decl * *Space)
    decl <- comment | currencyDecl | exchangeDecl | openDecl | closeDecl | balanceDecl | padDecl |
        noteDecl | priceDecl | transactionDecl
      
    comment <- "#" * *(1 - "\n") * "\n"

    currencyDecl <- "currency" * +Blank * >currency * *Blank * ?"\n":
      let currency = Currency(key: $1, index: currencyIndex)
      buffer.currencies[currency.key] = currency
      currencyIndex += 1

    exchangeDecl <- "exchange-pair" * +Blank * >currency * ":" * >currency *
        *Blank * ?"\n":
      let accountKey = $1 & ":" & $2
      if accountKey in buffer.exchangeAccounts:
        raise newException(ParseError, "Cannot define multiple identical exchange accounts")
      buffer.exchangeAccounts[accountKey] = ExchangeAccount(key: accountKey, referenceBalance: newDecimal("0.00"), securityBalance: newDecimal("0.00"))

    openDecl <- >date * +Blank * "open" * +Blank * >account * *Blank * >currency * *Blank * ?"\n":
      let date = parse($1, "yyyy-MM-dd")
      let account = parseAccount($2, date)
      echo account.key
      # discard buffer.accounts.insertAccount(account)

    closeDecl <- >date * +Blank * "close" * +Blank * >account * *Blank * >currency * *Blank * ?"\n":
      let date = parse($1, "yyyy-MM-dd")
      let accountKey = $2

      let accountO = buffer.accounts.findAccount(accountKey)
      if accountO.isSome():
        let account = accountO.get()
        account.close = some(date)
      else:
        # TODO parse error
        discard

    balanceDecl <- date * +Blank * "balance" * +Blank * account * +Blank *
        amount * +Blank * currency * *Blank * ?"\n"
    padDecl <- date * +Blank * "pad" * +Blank * account * +Blank * account *
        *Blank * ?"\n"
    noteDecl <- date * +Blank * "note" * +Blank * account * +Blank * note *
        *Blank * ?"\n"
    priceDecl <- date * +Blank * "price" * +Blank * currency * +Blank * amount *
        +Blank * currency * *Blank * ?"\n"
    transactionDecl <- *exchangeRates * transactionHeader * +record * ?"\n"

    exchangeRates <- "@" * >currency * ":" * >currency * *Blank * >rate * *Blank * "\n":
      let currencyKey = $1 & ":" & $2
      buffer.conversionRatesBuffer[currencyKey] = newDecimal($3)

    transactionHeader <- >date * +Blank * "*" * +Blank * >payee * *Blank *
        >?note * *Blank * "\n":
      let date: DateTime = parse($1, "yyyy-MM-dd")
      let transactionExchangeRates = buffer.conversionRatesBuffer

      buffer.transactions.newEntry = true
      buffer.transactions.index += 1
      buffer.transactions.dates.add(date)
      buffer.transactions.payees.add($2)
      buffer.transactions.notes.add($3)
      buffer.transactions.conversionRates.add(transactionExchangeRates)

      buffer.conversionRatesBuffer = initTable[string, DecimalType]()

      if (date > buffer.transactions.lastDate):
        buffer.transactions.lastDate = date

    record <- *Blank * >account * +Blank * >norm * +Blank * >amount * +Blank *
        >currency * *Blank * ?("@" * *Blank * >rate * *Blank * >currency) * ?"\n":
      let conversionRate = (if capture.len == 7: some(newDecimal(
          $5)) else: none(DecimalType))
      let conversionTarget = (if capture.len == 7: some($6) else: none(string))

      let currencyKey = $4
      let accountKey = $1 & ":" & currencyKey
      let accountKind = parseKind(($1).split(":")[0])

      if buffer.transactions.newEntry:
        buffer.transactions.records.add(@[Record(accountKey: accountKey, kind: accountKind, 
            norm: parseNorm($2), amount: newDecimal($3), currencyKey: currencyKey)])
        buffer.transactions.newEntry = false
      else:
        buffer.transactions.records[^1].add(Record(accountKey: accountKey, kind: accountKind,
            norm: parseNorm($2), amount: newDecimal($3), currencyKey: currencyKey))

    account <- accountKind * ":" * accountTree
    accountKind <- "Asset" | "Liability" | "Equity" | "Revenue" |
        "Expense" | "Draw"
    accountTree <- *accountParent * accountLeaf
    accountParent <- +Alnum * ":"
    accountLeaf <- +Alnum

    exchangeRate <- "@" * *Blank * +Digit * "." * +Digit
    amount <- +Digit * "." * Digit[2]
    rate <- +Digit * "." * Digit[1..5]
    norm <- "D" | "C"
    currency <- +Alnum
    date <- Digit[4] * "-" * Digit[2] * "-" * Digit[2]
    payee <- "\"" * *(" " | +Alnum) * "\""
    note <- "\"" * *(" " | +Alnum) * "\""

  let parseResult = parser.matchFile(filename, buffer)
  doAssert parseResult.ok
  result = buffer

proc transferBufferToLedger*(buffer: Buffer): Ledger =
  result.currencies = buffer.currencies
  result.accounts = buffer.accounts

  for key in buffer.exchangeAccounts.keys:
    result.exchangeAccounts[key] = ExchangeAccount(key: key, referenceBalance: newDecimal("0.00"),
        securityBalance: newDecimal("0.00"))

  for i in 0 .. buffer.transactions.index - 1:
    let note = if buffer.transactions.notes[i] != "": buffer.transactions.notes[i] else: "n/a"
    let transaction = Transaction(index: i, date: buffer.transactions.dates[i],
        payee: buffer.transactions.payees[i], note: note, conversionRates: buffer.transactions.conversionRates[i],
        records: buffer.transactions.records[i])
    result.transactions.add(transaction)
