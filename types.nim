import std/[times, options]
import tables
import decimal/decimal
import results

type R* = Result[void, string]

type ParseError* = object of ValueError
type LogicError* = object of ValueError

type
  Currency* = object
    key*: string
    index*: int
  Norm* = enum
    Debit
    Credit

type
  AccountKind* = enum
    Asset = "ASSET"
    Liability = "LIABILITY"
    Equity = "EQUITY"
    Revenue = "REVENUE"
    Expense = "EXPENSE"
    Exchange = "EXCHANGE"
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
  OptionalAccount* = object
    key*: string
    kind*: AccountKind
    norm*: Norm
    currencyKey*: string
    open*: Option[DateTime]
    close*: Option[DateTime]
  Account* = object
    key*: string
    kind*: AccountKind
    norm*: Norm
    currencyKey*: string
    open*: DateTime
    close*: DateTime
    balance*: DecimalType
  ExchangeAccount* = object
    key*: string
    kind*: AccountKind
    norm*: Norm
    referenceBalance*: DecimalType
    securityBalance*: DecimalType

type
  Transaction* = object
    index*: int
    date*: DateTime
    payee*: string
    note*: string
    conversionRates*: Table[string, DecimalType]
    records*: seq[Record]
  Record* = object
    accountKey*: string
    kind*: AccountKind
    norm*: Norm
    amount*: DecimalType
    currencyKey*: string
    # conversionTarget*: Option[string]
    # conversionRate*: Option[DecimalType]
  Verifier* = proc(transaction: Transaction): R

type
  AccountBuffer* = Table[string, OptionalAccount]
  ExchangeAccountBuffer* = Table[string, ExchangeAccount]
  TransactionBuffer* = object
    index*: int
    lastDate*: DateTime
    newEntry*: bool
    dates*: seq[DateTime]
    payees*: seq[string]
    notes*: seq[string]
    conversionRates*: seq[Table[string, DecimalType]]
    records*: seq[seq[Record]]
  Buffer* = object
    currencies*: Table[string, Currency]
    accounts*: AccountBuffer
    exchangeAccounts*: ExchangeAccountBuffer
    transactions*: TransactionBuffer

type Ledger* = object
  currencies*: Table[string, Currency]
  accounts*: Table[string, Account]
  exchangeAccounts*: Table[string, ExchangeAccount]
  transactions*: seq[Transaction]


proc key*(account: AccountNode): string =
  var current = account

  while current.kind != Leaf:
    result.add(current.v & ":")
    current = current.succ

  result.add(current.v)