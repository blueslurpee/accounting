import std/[times, options]
import tables
import decimal/decimal
import results

type R* = Result[void, string]

type ParseError* = object of ValueError
type LogicError* = object of ValueError

type
  Currency* = distinct string
  Norm* = enum
    Debit
    Credit

type
  AccountKind* = enum
    Asset = "Assets"
    Liability = "Liabilities"
    Equity = "Equity"
    Revenue = "Revenue"
    Expense = "Expenses"
    Draw = "Draws"
  AccountNodeType* = enum
    Parent
    Leaf
  AccountNode* = ref object
    v*: string
    case kind*: AccountNodeType # the `kind` field is the discriminator
    of Parent:
      succ*: AccountNode
    of Leaf:
      discard
  OptionalAccount* = tuple
    key: string
    kind: AccountKind
    norm: Norm
    open: Option[DateTime]
    close: Option[DateTime]
  Account* = tuple
    key: string
    kind: AccountKind
    norm: Norm
    open: DateTime
    close: DateTime
    balance: DecimalType

type
  Transaction* = object
    index*: int
    date*: DateTime
    payee*: string
    note*: string
    records*: seq[Record]
  Record* = object
    accountKey*: string
    norm*: Norm
    amount*: DecimalType
    currency*: Currency
  Verifier* = proc(transaction: Transaction): R

type
  AccountBuffer* = Table[string, OptionalAccount]
  TransactionBuffer* = object
    index*: int
    lastDate*: DateTime
    newEntry*: bool
    dates*: seq[DateTime]
    payees*: seq[string]
    notes*: seq[string]
    records*: seq[seq[Record]]
  Buffer* = object
    accounts*: AccountBuffer
    transactions*: TransactionBuffer

type Ledger* = tuple
  accounts: Table[string, Account]
  transactions: seq[Transaction]


proc key*(account: AccountNode): string =
  var current = account

  while current.kind != Leaf:
    result.add(current.v & ":")
    current = current.succ

  result.add(current.v)