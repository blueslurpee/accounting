# Depends on https://github.com/status-im/nim-decimal

import std/[strformat, times, sugar, sequtils, options]
import npeg, strutils, tables
import decimal/decimal

import results
export results

const filename = "./test.txt"

type R = Result[void, string]

type ParseError = object of ValueError
type LogicError = object of ValueError

type
  Currency = distinct string
  Norm = enum
    Debit
    Credit

type
  AccountType = enum
    Asset = "Assets"
    Liability = "Liabilities"
    Equity = "Equity"
    Revenue = "Revenue"
    Expense = "Expenses"
    Draw = "Draws"
  AccountNodeType = enum
    Parent
    Leaf
  AccountNode = ref object
    v: string
    case kind: AccountNodeType  # the `kind` field is the discriminator
    of Parent: 
      succ: AccountNode
    of Leaf:
      discard
  Account = object
    accountType: AccountType
    norm: Norm
    self: AccountNode
  OptionalAccountData = tuple
    open: Option[DateTime]
    close: Option[DateTime]
  AccountData = tuple
    open: DateTime
    close: DateTime

type
  Transaction = object
    index: int
    date: DateTime
    payee: string
    note: string
    records: seq[Record]
  Record = object
    account: Account
    norm: Norm
    amount: DecimalType
    currency: Currency
  Verifier = proc(transaction: Transaction): R

type
  AccountBuffer = Table[string, OptionalAccountData]
  TransactionBuffer = object
    index: int
    lastDate: DateTime
    newEntry: bool
    dates: seq[DateTime]
    payees: seq[string]
    notes: seq[string]
    records: seq[seq[Record]]
  Buffer = object
    accounts: AccountBuffer
    transactions: TransactionBuffer

var buffer: Buffer = Buffer(accounts: initTable[string, OptionalAccountData](), transactions: TransactionBuffer(lastDate: dateTime(0000, mJan, 1, 00, 00, 00, 00, utc())))

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

proc parseNorm(norm: string): Norm = 
  case norm
  of "D":
    return Debit
  of "C":
    return Credit 
  else: 
    raise newException(ValueError, "Invalid Norm")

let verifyEqualDebitsAndCredits: Verifier = proc(transaction: Transaction): R = 
  let debits = transaction.records.filter(t => t.norm == Debit)
  let credits = transaction.records.filter(t => t.norm == Credit)

  let startAmount = newDecimal("0.00")
  let debitAmount = foldl(debits, a + b.amount, startAmount)
  let creditAmount = foldl(credits, a + b.amount, startAmount)

  if debitAmount == creditAmount:
    return R.ok
  else:
    return R.err "Debits and Credits must sum to 0"

proc key(account: Account): string = 
  result = $account.accountType & ":" 
  var current = account.self

  while current.kind != Leaf:
    result.add(current.v & ":")
    current = current.succ

  result.add(current.v)

proc transferBuffer(buffer: Buffer): (Table[string, AccountData], seq[Transaction]) = 
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
  

proc printTransaction(transaction: Transaction) = 
  echo &"Date: {transaction.date.getDateStr}"
  echo &"Payee: {transaction.payee}"
  echo &"Note: {transaction.note}"
  echo "Records:"
  for record in transaction.records:
    echo "\t", &"{record.account} ", &"{record.norm} ", &"{record.amount} ", record.currency.string

proc verifyTransactions(transactions: seq[Transaction], verifiers: seq[Verifier]): R = 
  result = R.ok

  block verify:
    for transaction in transactions:
      for verifier in verifiers:
        let check = verifier(transaction)
        if check.isErr:
          result = R.err(check.error)
          break verify
    

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

let result = parser.matchFile(filename, buffer)
doAssert result.ok

let (accounts, transactions) = buffer.transferBuffer
let checkTransactions = verifyTransactions(transactions, @[verifyEqualDebitsAndCredits])

if (checkTransactions.isOk):
  echo "Accounts\n"
  echo accounts

  echo "Transactions\n"
  for transaction in transactions:
    echo &"--- TRANSACTION {transaction.index + 1} ---"
    printTransaction(transaction)
else:
  echo checkTransactions.error