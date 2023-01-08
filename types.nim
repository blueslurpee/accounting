import std/[times, options]
import tables
import strutils
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
    OptionalAccount* = object
        key*: string
        kind*: AccountKind
        norm*: Norm
        currencyKey*: string
        open*: Option[DateTime]
        close*: Option[DateTime]
    Account* = ref object
        key*: string
        name*: string
        kind*: AccountKind
        norm*: Norm
        open*: DateTime
        close*: DateTime
        currencyKey*: string
        balance*: DecimalType
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
        conversionRates*: Table[string, DecimalType]
        records*: seq[Record]
    Record* = object
        accountKey*: string
        kind*: AccountKind
        norm*: Norm
        amount*: DecimalType
        currencyKey*: string
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
        conversionRatesBuffer*: Table[string, DecimalType]
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

proc newAccountTree*(defaultCurrencyKey: string): AccountTree =
    result = AccountTree(assets: Account(key: "Asset", name: "Assets", norm: Norm.Debit, kind: AccountKind.Asset, currencyKey: defaultCurrencyKey, balance: newDecimal("0.00"), children: @[]), 
                        liabilities: Account(key: "Liability", name: "Liabilities", norm: Norm.Credit, kind: AccountKind.Liability, currencyKey: defaultCurrencyKey, balance: newDecimal("0.00"), children: @[]),
                        equity: Account(key: "Equity", name: "Equity", norm: Norm.Credit, kind: AccountKind.Equity, currencyKey: defaultCurrencyKey, balance: newDecimal("0.00"), children: @[]),
                        revenue: Account(key: "Revenue", name: "Revenue", norm: Norm.Credit, kind: AccountKind.Revenue, currencyKey: defaultCurrencyKey, balance: newDecimal("0.00"), children: @[]),
                        expenses: Account(key: "Expense", name: "Expense", norm: Norm.Debit, kind: AccountKind.Expense, currencyKey: defaultCurrencyKey, balance: newDecimal("0.00"), children: @[]),
                        exchange: initTable[string, ExchangeAccount]())

proc newAccount*(key: string, name: string, norm: Norm, kind: AccountKind, currencyKey: string): Account = 
    result = Account(key: key, name: name, norm: norm, kind: kind, currencyKey: currencyKey, balance: newDecimal("0.00"), children: @[])

proc splitKey*(key: string): seq[string] =
    result = key.split(":")

proc concatenateKey*(elements: seq[string]): string =
    for i in 0..elements.high:
        if i == 0:
            result = result & elements[i]
        else:
            result = result & ":" & elements[i]

proc truncateKey*(key: string, depth: int = 1): string =
    result = key.splitKey()[0..depth].concatenateKey()

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

proc findAccount*(account: Account, queryKey: string, depth: int = 1): Option[Account] =
    result = none(Account)

    if queryKey == account.key:
        return some(account)

    if account.children.len == 0:
        return none(Account)

    for child in account.children:
        # Don't check child branches of the tree that are already a non-match
        let queryTruncatedPath = queryKey.truncateKey(depth).splitKey()
        let childTruncatedPath = child.key.truncateKey(depth).splitKey()

        if queryTruncatedPath[depth] == childTruncatedPath[depth]:
            result = child.findAccount(queryKey)
        if result.isSome:
            return result

proc findAccount*(tree: AccountTree, key: string): Option[Account] = 
    let kind = parseKind(key.splitKey()[0])

    case kind:
        of Asset:
            result = tree.assets.findAccount(key)
        of Liability:
            result = tree.liabilities.findAccount(key)
        of Equity:
            result = tree.equity.findAccount(key)
        of Revenue:
            result = tree.revenue.findAccount(key)
        of Expense:
            result = tree.expenses.findAccount(key)

proc insertAccount*(tree: AccountTree, account: Account): R =
    if tree.findAccount(account.key).isSome:
        return R.err "Account already exists"
    
    var parentO: Option[Account] = none(Account)
    let path = account.key.splitKey()

    for i in countdown(path.high, 1):
        let queryKey = path[0..i-1].concatenateKey
        let r = tree.findAccount(queryKey)
        if r.isSome:
            parentO = r
            break

    if parentO.isNone:
        return R.err "Could not find appropriate parent account"

    if parentO.isSome:
        let parent = parentO.get()
        let levelDifference = account.key.splitKey.len - parent.key.splitKey.len

        if levelDifference == 1:
            parent.children.add(account)
            return R.ok

        else:
            let immediateParent = newAccount(account.key.truncateKey, account.key.truncateKey, account.norm, account.kind, account.currencyKey)
            immediateParent.children.add(account)
            return tree.insertAccount(immediateParent)

