# Depends on https://github.com/status-im/nim-decimal

import std/[strformat, times, sugar, sequtils]
import npeg, strutils, tables
import decimal/decimal

import results
export results

const filename = "./test.txt"

type
  Currency = distinct string
  Norm = enum
    Debit
    Credit
  AccountType = enum
    Asset
    Liability
    Equity
    Revenue
    Expense
    Draw
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

type
  TransactionBuffer = object
    index: int
    newEntry: bool
    dates: seq[DateTime]
    payees: seq[string]
    notes: seq[string]
    records: seq[seq[Record]]

type R = Result[void, string]

let accounts: Table[string, Account] = initTable[string, Account]()
var buffer: TransactionBuffer

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

proc verifyEqualDebitsAndCredits(transaction: Transaction): R = 
  let debits = transaction.records.filter(t => t.norm == Debit)
  let credits = transaction.records.filter(t => t.norm == Credit)

  let startAmount = newDecimal("0.00")
  let debitAmount = foldl(debits, a + b.amount, startAmount)
  let creditAmount = foldl(credits, a + b.amount, startAmount)

  if debitAmount == creditAmount:
    return R.ok
  else:
    return R.err "Debits and Credits must sum to 0"

proc printTransaction(transaction: Transaction) = 
  echo &"Date: {transaction.date.getDateStr}"
  echo &"Payee: {transaction.payee}"
  echo &"Note: {transaction.note}"
  echo "Records:"
  for record in transaction.records:
    echo "\t", &"{record.account} ", &"{record.norm} ", &"{record.amount} ", record.currency.string

let parser = peg("input", buffer: TransactionBuffer):
  input <- *Space * *>(*decl * Space):
    echo $0

  decl <- openDecl | closeDecl | balanceDecl | padDecl | noteDecl | priceDecl | transactionDecl
  openDecl <- date * +Blank * "open" * +Blank * account * *Blank * ?"\n"
  closeDecl <- date * +Blank * "close" * +Blank * account * *Blank * ?"\n"
  balanceDecl <- date * +Blank * "balance" * +Blank * account * +Blank * amount * +Blank * currency * *Blank * ?"\n"
  padDecl <- date * +Blank * "pad" * +Blank * account * +Blank * account * *Blank * ?"\n"
  noteDecl <- date * +Blank * "note" * +Blank * account * +Blank * note * *Blank * ?"\n"
  priceDecl <- date * +Blank * "price" * +Blank * currency * +Blank * amount * +Blank * currency * *Blank * ?"\n"
  # TODO: Event
  transactionDecl <- transactionHeader * +record * ?"\n"

  transactionHeader <- >date * +Blank * "*" * +Blank * >payee * *Blank * >?note * *Blank * "\n":
    buffer.newEntry = true
    buffer.index += 1
    buffer.dates.add(parse($1, "yyyy-MM-dd"))
    buffer.payees.add($2)
    buffer.notes.add($3)
  record <- *Blank * >account * +Blank * >norm * +Blank * >amount * +Blank * >currency * *Blank * ?"\n":
    if buffer.newEntry:
      buffer.records.add(@[Record(account: parseAccount($1), norm: parseNorm($2), amount: newDecimal($3), currency: Currency($4))])
      buffer.newEntry = false
    else:
      buffer.records[^1].add(Record(account: parseAccount($1), norm: parseNorm($2), amount: newDecimal($3), currency: Currency($4)))
  
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

for i in 0 .. buffer.index - 1:
  let note = if buffer.notes[i] != "": buffer.notes[i] else: "n/a"
  let transaction = Transaction(index: i, date: buffer.dates[i], payee: buffer.payees[i], note: note, records: buffer.records[i])

  let equalDebitsAndCredits = verifyEqualDebitsAndCredits(transaction)
  if equalDebitsAndCredits.isOk:
    echo &"--- TRANSACTION {transaction.index + 1} ---"
    printTransaction(transaction)
  else:
    echo &"--- TRANSACTION {transaction.index + 1} ---"
    echo &"Invalid Transaction - {equalDebitsAndCredits.error}"

  echo "\n"