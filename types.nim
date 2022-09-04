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
  AccountType* = enum
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
  Account* = object
    accountType*: AccountType
    norm*: Norm
    self*: AccountNode
  OptionalAccountData* = tuple
    open: Option[DateTime]
    close: Option[DateTime]
  AccountData* = tuple
    open: DateTime
    close: DateTime

type
  Transaction* = object
    index*: int
    date*: DateTime
    payee*: string
    note*: string
    records*: seq[Record]
  Record* = object
    account*: Account
    norm*: Norm
    amount*: DecimalType
    currency*: Currency
  Verifier* = proc(transaction: Transaction): R

type
  AccountBuffer* = Table[string, OptionalAccountData]
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
