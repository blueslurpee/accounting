import std/[times, options]
import strutils, tables
import npeg # https://github.com/zevv/npeg
import decimal/decimal # https://github.com/status-im/nim-decimal
import results # https://github.com/arnetheduck/nim-result

import types

proc parseAccountType(accountType: string): AccountType = 
  case accountType
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
    return AccountNode(kind: AccountNodeType.Parent, v: nodeList[0], succ: generateAccountNodes(nodeList[1 .. ^1]))
  else:
    raise newException(RangeDefect, "Invalid Account Node List")
  
proc accountTypeToNorm(accountType: AccountType): Norm = 
  case accountType
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

proc parseAccount(account: string): Account = 
  let elements = account.split(":")

  let accountType = parseAccountType(elements[0])
  let accountIdentifiers = elements[1..^1]
  
  return Account(accountType: accountType, norm: accountTypeToNorm(accountType), self: generateAccountNodes(accountIdentifiers))

proc key(account: Account): string = 
  result = $account.accountType & ":" 
  var current = account.self

  while current.kind != Leaf:
    result.add(current.v & ":")
    current = current.succ

  result.add(current.v)

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

  let parser = peg("input", buffer: Buffer):
    input <- *Space * *(>decl * *Space)
    decl <- openDecl | closeDecl | balanceDecl | padDecl | noteDecl | priceDecl | transactionDecl

    openDecl <- >date * +Blank * "open" * +Blank * >account * *Blank * ?"\n":
      let date = parse($1, "yyyy-MM-dd")
      let account = parseAccount($2)

      if account.key in buffer.accounts:
        if buffer.accounts[account.key].open.isSome:
          raise newException(ParseError, "Cannot define multiple open directives for the same account")
        else:
          buffer.accounts[account.key].open = some(date)
      else:
        buffer.accounts[account.key] = (open: some(date), close: none(DateTime))

    closeDecl <- >date * +Blank * "close" * +Blank * >account * *Blank * ?"\n":
      let date = parse($1, "yyyy-MM-dd")
      let account = parseAccount($2)

      if account.key in buffer.accounts:
        if buffer.accounts[account.key].close.isSome:
          raise newException(ParseError, "Cannot define multiple close directives for the same account")
        else:
          buffer.accounts[account.key].close = some(date)
      else:
        buffer.accounts[account.key] = (open: none(DateTime), close: some(date))

    balanceDecl <- date * +Blank * "balance" * +Blank * account * +Blank * amount * +Blank * currency * *Blank * ?"\n"
    padDecl <- date * +Blank * "pad" * +Blank * account * +Blank * account * *Blank * ?"\n"
    noteDecl <- date * +Blank * "note" * +Blank * account * +Blank * note * *Blank * ?"\n"
    priceDecl <- date * +Blank * "price" * +Blank * currency * +Blank * amount * +Blank * currency * *Blank * ?"\n"
    transactionDecl <- transactionHeader * +record * ?"\n"

    transactionHeader <- >date * +Blank * "*" * +Blank * >payee * *Blank * >?note * *Blank * "\n":
      let date: DateTime = parse($1, "yyyy-MM-dd")

      buffer.transactions.newEntry = true
      buffer.transactions.index += 1
      buffer.transactions.dates.add(date)
      buffer.transactions.payees.add($2)
      buffer.transactions.notes.add($3)

      if (date > buffer.transactions.lastDate):
        buffer.transactions.lastDate = date

    record <- *Blank * >account * +Blank * >norm * +Blank * >amount * +Blank * >currency * *Blank * ?"\n":
      if buffer.transactions.newEntry:
        buffer.transactions.records.add(@[Record(account: parseAccount($1), norm: parseNorm($2), amount: newDecimal($3), currency: Currency($4))])
        buffer.transactions.newEntry = false
      else:
        buffer.transactions.records[^1].add(Record(account: parseAccount($1), norm: parseNorm($2), amount: newDecimal($3), currency: Currency($4)))
    
    account <- accountType * ":" * accountTree
    accountType <- "Assets" | "Liabilities" | "Equity" | "Revenue" | "Expenses" | "Draws"
    accountTree <- *accountParent * accountLeaf
    accountParent <- +Alnum * ":"
    accountLeaf <- +Alnum
    
    amount <- +Digit * "." * Digit[2]
    norm <- "D" | "C"
    currency <- +Alnum
    date <- Digit[4] * "-" * Digit[2] * "-" * Digit[2]
    payee <- "\"" * *(" " | +Alnum) * "\""
    note <- "\"" * *(" " | +Alnum) * "\""

  let parseResult = parser.matchFile(filename, buffer)
  doAssert parseResult.ok
  result = buffer

proc transferBuffer*(buffer: Buffer): (Table[string, AccountData], seq[Transaction]) = 
  for key in buffer.accounts.keys:
    let open = buffer.accounts[key].open
    let close = buffer.accounts[key].close

    if open.isNone:
      raise newException(LogicError, "Account must have an opening date")

    let concreteOpen = open.get
    let concreteClose = if close.isSome: close.get else: buffer.transactions.lastDate

    result[0][key] = (open: concreteOpen, close: concreteClose)

  for i in 0 .. buffer.transactions.index - 1:
    let note = if buffer.transactions.notes[i] != "": buffer.transactions.notes[i] else: "n/a"
    let transaction = Transaction(index: i, date: buffer.transactions.dates[i], payee: buffer.transactions.payees[i], note: note, records: buffer.transactions.records[i])
    result[1].add(transaction)