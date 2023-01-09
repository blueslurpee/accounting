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
type
  Norm* = enum
    Debit
    Credit
  AccountKind* = enum
    Asset = "ASSET"
    Liability = "LIABILITY"
    Equity = "EQUITY"
    Revenue = "REVENUE"
    Expense = "EXPENSE"

type
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

type 
    Account* = ref object
        key*: string
        name*: string
        kind*: AccountKind
        norm*: Norm
        open*: DateTime
        close*: Option[DateTime]
        balances*: seq[tuple[currencyKey: string, balance: DecimalType]]
        children*: seq[Account]
    ExchangeAccount* = object
        key*: string
        referenceBalance*: DecimalType
        securityBalance*: DecimalType
    AccountTree* = ref object
        assets*: Account
        liabilities*: Account
        equity*: Account
        revenue*: Account
        expenses*: Account
        exchange*: Table[string, ExchangeAccount]

type
    Transaction* = object
        index*: int
        date*: DateTime
        payee*: string
        note*: string
        conversionRates*: seq[tuple[key: string, rate: DecimalType]]
        records*: seq[Record]
    Record* = object
        accountKey*: string
        kind*: AccountKind
        norm*: Norm
        amount*: DecimalType
        currencyKey*: string
    Verifier* = proc(transaction: Transaction): R

type
    Buffer* = object
        index*: int
        conversionRatesBuffer*: seq[tuple[key: string, rate: DecimalType]]
        accounts*: AccountTree
        currencies*: Table[string, Currency]
        transactions*: seq[Transaction]
    Ledger* = object
        accounts*: AccountTree
        currencies*: Table[string, Currency]
        transactions*: seq[Transaction]

proc toNorm*(accountKind: AccountKind): Norm =
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

proc parseKind*(kind: string): AccountKind =
  case kind
  of "Asset":
    return Asset
  of "Liability":
    return Liability
  of "Equity":
    return Equity
  of "Revenue":
    return Revenue
  of "Expense":
    return Expense
  else:
    raise newException(ValueError, "Invalid Account Type")