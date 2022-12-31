import std/[times, options, sets]
import strutils, tables
import npeg # https://github.com/zevv/npeg
import decimal/decimal # https://github.com/status-im/nim-decimal
import results # https://github.com/arnetheduck/nim-result

import types

proc parseAccountKind(accountKind: string): AccountKind =
  case accountKind
  of "Assets":
    return Asset
  of "Liabilities":
    return Liability
  of "Equity":
    return Equity
  of "Revenue":
    return Revenue
  of "Expenses":
    return Expense
  of "Draws":
    return Draw
  else:
    raise newException(ValueError, "Invalid Account Type")

proc generateAccountNodes(nodeList: seq[string]): AccountNode =
  if nodeList.len == 1:
    return AccountNode(kind: AccountNodeType.Leaf, v: nodeList[0])
  elif nodeList.len > 1:
    return AccountNode(kind: AccountNodeType.Parent, v: nodeList[0],
        succ: generateAccountNodes(nodeList[1 .. ^1]))
  else:
    raise newException(RangeDefect, "Invalid Account Node List")

proc accountKindToNorm(accountKind: AccountKind): Norm =
  case accountKind
  of Asset:
    result = Debit
  of Liability:
    result = Credit
  of Equity:
    result = Credit
  of Revenue:
    result = Credit
  of Expense:
    result = Debit
  of Draw:
    result = Debit
  of Exchange:
    result = Credit


proc parseAccount(key: string, currencyKey: string): OptionalAccount =
  let elements = key.split(":")
  let kind = parseAccountKind(elements[0])

  return OptionalAccount(key: currencyKey & ":" & key, kind: kind, norm: accountKindToNorm(kind), currencyKey: currencyKey, open: none(
      DateTime), close: none(DateTime))

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
    decl <- currencyDecl | exchangeDecl | openDecl | closeDecl | balanceDecl | padDecl |
        noteDecl | priceDecl | transactionDecl

    currencyDecl <- "currency" * +Blank * >currency * *Blank * ?"\n":
      let currency = Currency(key: $1, index: currencyIndex)
      buffer.currencies[currency.key] = currency
      currencyIndex += 1

    exchangeDecl <- "exchange-pair" * +Blank * >currency * ":" * >currency *
        *Blank * ?"\n":
      let accountKey = $1 & ":" & $2
      if accountKey in buffer.exchangeAccounts:
        raise newException(ParseError, "Cannot define multiple identical exchange accounts")
      buffer.exchangeAccounts[accountKey] = ExchangeAccount(key: accountKey,
          kind: AccountKind.Exchange, norm: Norm.Credit,
          referenceBalance: newDecimal("0.00"), securityBalance: newDecimal("0.00"))

    openDecl <- >date * +Blank * "open" * +Blank * >account * *Blank * >currency * *Blank * ?"\n":
      let date = parse($1, "yyyy-MM-dd")
      let account = parseAccount($2, $3)

      if account.key in buffer.accounts:
        if buffer.accounts[account.key].open.isSome:
          raise newException(ParseError, "Cannot define multiple open directives for the same account")
        else:
          buffer.accounts[account.key].open = some(date)
      else:
        buffer.accounts[account.key] = OptionalAccount(key: account.key, kind: account.kind,
            norm: account.norm, currencyKey: account.currencyKey, open: some(date), close: none(DateTime))

    closeDecl <- >date * +Blank * "close" * +Blank * >account * *Blank * >currency * *Blank * ?"\n":
      let date = parse($1, "yyyy-MM-dd")
      let account = parseAccount($2, $3)

      if account.key in buffer.accounts:
        if buffer.accounts[account.key].close.isSome:
          raise newException(ParseError, "Cannot define multiple close directives for the same account")
        else:
          buffer.accounts[account.key].close = some(date)
      else:
        buffer.accounts[account.key] = OptionalAccount(key: account.key, kind: account.kind,
            norm: account.norm, currencyKey: account.currencyKey, open: none(DateTime), close: some(date))

    balanceDecl <- date * +Blank * "balance" * +Blank * account * +Blank *
        amount * +Blank * currency * *Blank * ?"\n"
    padDecl <- date * +Blank * "pad" * +Blank * account * +Blank * account *
        *Blank * ?"\n"
    noteDecl <- date * +Blank * "note" * +Blank * account * +Blank * note *
        *Blank * ?"\n"
    priceDecl <- date * +Blank * "price" * +Blank * currency * +Blank * amount *
        +Blank * currency * *Blank * ?"\n"
    transactionDecl <- transactionHeader * +record * ?"\n"

    transactionHeader <- >date * +Blank * "*" * +Blank * >payee * *Blank *
        >?note * *Blank * "\n":
      let date: DateTime = parse($1, "yyyy-MM-dd")

      buffer.transactions.newEntry = true
      buffer.transactions.index += 1
      buffer.transactions.dates.add(date)
      buffer.transactions.payees.add($2)
      buffer.transactions.notes.add($3)

      if (date > buffer.transactions.lastDate):
        buffer.transactions.lastDate = date

    record <- *Blank * >account * +Blank * >norm * +Blank * >amount * +Blank *
        >currency * *Blank * ?("@" * *Blank * >rate * *Blank * >currency) * ?"\n":
      let conversionRate = (if capture.len == 7: some(newDecimal(
          $5)) else: none(DecimalType))
      let conversionTarget = (if capture.len == 7: some($6) else: none(string))

      let currencyKey = $4
      let accountKey = currencyKey & ":" & $1

      if buffer.transactions.newEntry:
        buffer.transactions.records.add(@[Record(accountKey: accountKey,
            norm: parseNorm($2), amount: newDecimal($3), currencyKey: currencyKey,
                conversionTarget: conversionTarget,
                conversionRate: conversionRate)])
        buffer.transactions.newEntry = false
      else:
        buffer.transactions.records[^1].add(Record(accountKey: accountKey,
            norm: parseNorm($2), amount: newDecimal($3), currencyKey: currencyKey,
                conversionTarget: conversionTarget,
                conversionRate: conversionRate))

    account <- accountKind * ":" * accountTree
    accountKind <- "Assets" | "Liabilities" | "Equity" | "Revenue" |
        "Expenses" | "Draws"
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

  for key in buffer.accounts.keys:
    let account = buffer.accounts[key]

    let open = account.open
    let close = account.close

    if open.isNone:
      raise newException(LogicError, "Account must have an opening date")

    let concreteOpen = open.get
    let concreteClose = if close.isSome: close.get else: buffer.transactions.lastDate

    result.accounts[key] = Account(key: account.key, kind: account.kind,
        norm: account.norm, currencyKey: account.currencyKey, open: concreteOpen, close: concreteClose,
        balance: newDecimal("0.00"))

  for key in buffer.exchangeAccounts.keys:
    result.exchangeAccounts[key] = ExchangeAccount(key: key, kind: AccountKind.Exchange,
        norm: Norm.Credit, referenceBalance: newDecimal("0.00"),
        securityBalance: newDecimal("0.00"))


  for i in 0 .. buffer.transactions.index - 1:
    let note = if buffer.transactions.notes[i] != "": buffer.transactions.notes[i] else: "n/a"
    let transaction = Transaction(index: i, date: buffer.transactions.dates[i],
        payee: buffer.transactions.payees[i], note: note,
        records: buffer.transactions.records[i])
    result.transactions.add(transaction)
