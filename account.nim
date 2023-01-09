import std/[options, times, sugar]
import strutils
import sequtils
import tables

import cascade
import decimal/decimal
import results
import types

proc newAccount*(key: string, name: string, norm: Norm, kind: AccountKind, open: DateTime): Account

proc newAccountTree*(defaultOpen: DateTime): AccountTree =
    result = AccountTree(assets: newAccount(key="Asset", name="Assets", norm=Norm.Debit, kind=AccountKind.Asset, open=defaultOpen), 
                        liabilities: newAccount(key="Liability", name="Liabilities", norm=Norm.Credit, kind=AccountKind.Liability, open=defaultOpen),
                        equity: newAccount(key="Equity", name="Equity", norm=Norm.Credit, kind=AccountKind.Equity, open=defaultOpen),
                        revenue: newAccount(key="Revenue", name="Revenue", norm=Norm.Credit, kind=AccountKind.Revenue, open=defaultOpen),
                        expenses: newAccount(key="Expense", name="Expense", norm=Norm.Debit, kind=AccountKind.Expense, open=defaultOpen),
                        exchange: initTable[string, ExchangeAccount]())

proc newAccount*(key: string, name: string, norm: Norm, kind: AccountKind, open: DateTime): Account = 
    result = Account(key: key, name: name, norm: norm, kind: kind, open: open, balances: @[], children: @[])

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

proc aggregation(account: Account): seq[Account] = 
    if account.children.len == 0:
        result = @[account]
    else:
        result = @[account]
        for child in account.children:
            result.add(child.aggregation)

proc aggregation*(tree: AccountTree): seq[Account] =
    result.add(tree.assets.aggregation)
    result.add(tree.liabilities.aggregation)
    result.add(tree.equity.aggregation)
    result.add(tree.revenue.aggregation)
    result.add(tree.expenses.aggregation)

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
            let immediateParent = newAccount(account.key.truncateKey, account.key.truncateKey, account.norm, account.kind, account.open)
            immediateParent.children.add(account)
            return tree.insertAccount(immediateParent)


proc incrementBalance*(account: Account, currencyKey: string, amount: DecimalType): Account =
    account.balances = account.balances.map(b => 
    (if b.currencyKey == currencyKey: 
        cascade b: 
            balance = b.balance + amount 
    else: b))

    return account

proc decrementBalance*(account: Account, currencyKey: string, amount: DecimalType): Account =
    account.balances = account.balances.map(b => 
    (if b.currencyKey == currencyKey: 
        cascade b: 
            balance = b.balance - amount 
    else: b))

    return account