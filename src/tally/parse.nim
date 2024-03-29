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
  let key = if kind == AccountKind.Revenue or kind == AccountKind.Expense: "Equity:" & key else: key

  return newAccount(key=key, name=key, kind=kind, norm=kind.toNorm, open=open)

proc parseNorm(norm: string): Norm =
  case norm
  of "D":
    return Debit
  of "C":
    return Credit
  else:
    raise newException(ValueError, "Invalid Norm")

proc parseLedger*(filename: string): Ledger =
  var buffer = Buffer(
      index: 0,
      conversionRatesBuffer: @[],
      accounts: newAccountTree(parse("2022-01-01", "yyyy-MM-dd")), 
      currencies: initTable[string, Currency](),
      transactions: @[]
  )
  var currencyIndex = 0

  let parser = peg("input", buffer: Buffer):
    input <- *Space * *( > decl * *Space)
    decl <- comment | entityDecl | fiscalYearDecl | currencyDecl | exchangeDecl | openDecl | closeDecl | balanceDecl | padDecl |
        noteDecl | priceDecl | transactionDecl
      
    comment <- "#" * *(1 - "\n") * "\n"

    entityDecl <- "entity" * +Blank * >entity * *Blank * "\n":
      buffer.entity = $1

    fiscalYearDecl <- "fiscal-year" * +Blank * >fiscalYear * *Blank * "\n":
      buffer.fiscalYear = ($1).parseInt

    currencyDecl <- "currency" * +Blank * >currency * *Blank * ?"\n":
      let currency = Currency(key: $1, index: currencyIndex)
      buffer.currencies[currency.key] = currency
      currencyIndex += 1

    exchangeDecl <- "exchange-pair" * +Blank * >currency * ":" * >currency *
        *Blank * ?"\n":
      let accountKey = $1 & ":" & $2
      if accountKey in buffer.accounts.exchange:
        raise newException(ParseError, "Cannot define multiple identical exchange accounts")
      buffer.accounts.exchange[accountKey] = ExchangeAccount(key: accountKey, referenceBalance: newDecimal("0.00"), securityBalance: newDecimal("0.00"))

    openDecl <- >date * +Blank * "open" * +Blank * >account * *Blank * >currency * *Blank * ?"\n":
      let date = parse($1, "yyyy-MM-dd")
      let account = parseAccount($2, date)
      discard buffer.accounts.insertAccount(account)

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
      buffer.conversionRatesBuffer.add((currencyKey, newDecimal($3)))

    transactionHeader <- >date * +Blank * "*" * +Blank * >payee * *Blank *
        >?note * *Blank * "\n":
      let date: DateTime = parse($1, "yyyy-MM-dd")

      buffer.transactions.add(Transaction(
        index: buffer.index,
        date: date,
        payee: $2,
        note: $3,
        conversionRates: buffer.conversionRatesBuffer,
        records: @[]
      ))
      buffer.conversionRatesBuffer = @[]
      buffer.index += 1

    record <- *Blank * >account * +Blank * >norm * +Blank * >amount * +Blank *
        >currency * *Blank * ?("[" * >identifier * "]") * ?"\n":
      let currencyKey = $4
      let accountKey = $1
      let accountKind = parseKind(($1).split(":")[0])
      let doc: Option[string] = if capture.len == 6: some($5) else: none(string)

      buffer.transactions[^1].records.add(
        Record(accountKey: accountKey, 
               kind: accountKind,
               norm: parseNorm($2),
               currencyKey: currencyKey, 
               amount: newDecimal($3), 
               convertedCurrencyKey: currencyKey, 
               convertedAmount: newDecimal($3),
               doc: doc
        )
      )

    account <- accountKind * ":" * accountTree
    accountKind <- "Asset" | "Liability" | "Equity" | "Revenue" |
        "Expense" | "Draw"
    accountTree <- *accountParent * accountLeaf
    accountParent <- +Alnum * ":"
    accountLeaf <- +Alnum

    entity <- *(+Alnum * Blank) * +Alnum
    fiscalYear <- Digit[4]
    exchangeRate <- "@" * *Blank * +Digit * "." * +Digit
    amount <- +Digit * "." * Digit[2]
    rate <- +Digit * "." * Digit[1..5]
    norm <- "D" | "C"
    currency <- +Alnum
    identifier <- +(Alnum | "_" | ".")
    date <- Digit[4] * "-" * Digit[2] * "-" * Digit[2]
    payee <- "\"" * *(1 - "\"") * "\""
    note <- "\"" * *(" " | +Alnum) * "\""

  let parseResult = parser.matchFile(filename, buffer)
  doAssert parseResult.ok

  result.entity = buffer.entity
  result.fiscalYear = buffer.fiscalYear
  result.accounts = buffer.accounts.sortAccounts()
  result.currencies = buffer.currencies
  result.transactions = buffer.transactions
