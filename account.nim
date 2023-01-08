import std/[times, options]
import strutils
import decimal/decimal
import results
import types


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
    Exchange = "EXCHANGE"

type 
    Account* = ref object
        key*: string
        name*: string
        norm*: Norm
        open*: DateTime
        close*: DateTime
        case kind*: AccountKind
        of Asset, Liability, Equity, Revenue, Expense:
            currencyKey*: string
            balance*: DecimalType
        of Exchange:
            referenceCurrecyKey*: string
            securityCurrencyKey*: string
            referenceBalance*: DecimalType
            securityBalance*: DecimalType
        children*: seq[Account]
    AccountTree* = ref object
        assets*: Account
        liabilities*: Account
        equity*: Account
        revenue*: Account
        expenses*: Account
        exchange*: seq[Account]

proc newAccountTree*(defaultCurrencyKey: string): AccountTree =
    result = AccountTree(assets: Account(key: "Asset", name: "Assets", norm: Norm.Debit, kind: AccountKind.Asset, currencyKey: defaultCurrencyKey, balance: newDecimal("0.00"), children: @[]), 
                        liabilities: Account(key: "Liability", name: "Liabilities", norm: Norm.Credit, kind: AccountKind.Liability, currencyKey: defaultCurrencyKey, balance: newDecimal("0.00"), children: @[]),
                        equity: Account(key: "Equity", name: "Equity", norm: Norm.Credit, kind: AccountKind.Equity, currencyKey: defaultCurrencyKey, balance: newDecimal("0.00"), children: @[]),
                        revenue: Account(key: "Revenue", name: "Revenue", norm: Norm.Credit, kind: AccountKind.Revenue, currencyKey: defaultCurrencyKey, balance: newDecimal("0.00"), children: @[]),
                        expenses: Account(key: "Expense", name: "Expense", norm: Norm.Debit, kind: AccountKind.Expense, currencyKey: defaultCurrencyKey, balance: newDecimal("0.00"), children: @[]),
                        exchange: @[])

proc newAccount*(key: string, name: string, norm: Norm, kind: AccountKind, currencyKey: string): Account = 
    case kind:
    of Asset, Liability, Equity, Revenue, Expense:
        result = Account(key: key, name: name, norm: norm, kind: kind, currencyKey: currencyKey, balance: newDecimal("0.00"), children: @[])
    of Exchange:
        raise newException(ValueError, "Invalid Account Type")

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
        else:
            return none(Account)

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

