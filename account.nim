import std/[options, times, sugar]
import strutils
import sequtils
import tables

import cascade
import decimal/decimal
import results
import types

proc newRootAccount*(key: string, name: string, norm: Norm, kind: AccountKind, open: DateTime): Account
proc newAccount*(key: string, name: string, norm: Norm, kind: AccountKind, open: DateTime): Account

proc newAccountTree*(defaultOpen: DateTime): AccountTree =
    result = AccountTree(assets: newRootAccount(key="Asset", name="Assets", norm=Norm.Debit, kind=AccountKind.Asset, open=defaultOpen), 
                        liabilities: newRootAccount(key="Liability", name="Liabilities", norm=Norm.Credit, kind=AccountKind.Liability, open=defaultOpen),
                        equity: newRootAccount(key="Equity", name="Equity", norm=Norm.Credit, kind=AccountKind.Equity, open=defaultOpen),
                        revenue: newRootAccount(key="Revenue", name="Revenue", norm=Norm.Credit, kind=AccountKind.Revenue, open=defaultOpen),
                        expenses: newRootAccount(key="Expense", name="Expense", norm=Norm.Debit, kind=AccountKind.Expense, open=defaultOpen),
                        exchange: initTable[string, ExchangeAccount]())

proc newRootAccount(key: string, name: string, norm: Norm, kind: AccountKind, open: DateTime): Account = 
    result = Account(key: key, name: name, norm: norm, kind: kind, position: TreePosition.Root, open: open, balances: @[], children: @[])

proc newAccount*(key: string, name: string, norm: Norm, kind: AccountKind, open: DateTime): Account = 
    result = Account(key: key, name: name, norm: norm, kind: kind, position: TreePosition.Inner, open: open, balances: @[], children: @[])

proc toAccountingString(decimal: DecimalType): string =
  return (if decimal >= 0: $decimal else: "(" & $decimal.abs & ")")

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
            case account.position:
            of TreePosition.Root:
                return R.err "Cannot add a root account type"
            of TreePosition.Inner:
                parent.children.add(account)
                account.parent = parent
                return R.ok

        else:
            let immediateParent = newAccount(account.key.truncateKey, account.key.truncateKey, account.norm, account.kind, account.open)
            immediateParent.children.add(account)
            account.parent = immediateParent
            return tree.insertAccount(immediateParent)

proc hasCurrency*(account: Account, queryCurrencyKey: string): bool = 
    for (currencyKey, _) in account.balances:
        if currencyKey == queryCurrencyKey:
            return true
    
    return false

proc getBalance*(account: Account, queryCurrencyKey: string): DecimalType = 
    for (currencyKey, balance) in account.balances:
        if currencyKey == queryCurrencyKey:
            return balance

    return newDecimal("0.00")

proc incrementBalance*(account: Account, currencyKey: string, amount: DecimalType): Account =
    if account.hasCurrency(currencyKey):
        account.balances = account.balances.map(b => 
        (if b.currencyKey == currencyKey: 
            cascade b: 
                balance = b.balance + amount 
        else: b))
    else:
        account.balances.add((currencyKey: currencyKey, balance: amount))

    case account.position:
    of TreePosition.Root: discard
    of TreePosition.Inner:
        discard account.parent.incrementBalance(currencyKey, amount)

    return account

proc decrementBalance*(account: Account, currencyKey: string, amount: DecimalType): Account =
    if account.hasCurrency(currencyKey):
        account.balances = account.balances.map(b => 
        (if b.currencyKey == currencyKey: 
            cascade b: 
                balance = b.balance - amount 
        else: b))
    else:
        account.balances.add((currencyKey: currencyKey, balance: amount * -1))

    case account.position:
    of TreePosition.Root: discard
    of TreePosition.Inner:
        discard account.parent.decrementBalance(currencyKey, amount)

    return account

proc reportComponents*(account: Account, depth: int = 0): tuple[left: string, right: string, remaining: seq[string]] =
    let left = "| " & spaces(2 * depth) & account.name
    let right = (
        if account.balances.len == 0: 
            "-- |" 
        else: 
            let (currencyKey, balance) = account.balances[0]
            let endS = if account.balances.len == 1: " |\n" else: " | "
            currencyKey & spaces(1) & balance.toAccountingString & endS
    )
    
    var remaining: seq[string] = @[]
    for i in 1..account.balances.high:
        let (currencyKey, balance) = account.balances[i]
        let negative = balance < 0
        let line = currencyKey & spaces(if negative: 2 else: 1) & balance.toAccountingString & (if negative: "|" else: " |")
        remaining.add(line)

    return (left, right, remaining)


proc reportLength*(account: Account, depth: int = 0): int =
    let (left, right, _) = account.reportComponents(depth)
    return left.len + right.len

proc maxReportLength*(account: Account, depth: int = 0): int =
    if account.children.len == 0:
        return account.reportLength(depth)
    else:
        return account.children.map(a => a.maxReportLength(depth + 1)).foldl(if a > b: a else: b, account.reportLength(depth))

proc echoSelf*(account: Account, maxReportLength: int = -1, depth: int = 0): void =
    var maxReportLength = if maxReportLength == -1: account.maxReportLength + 10 else: maxReportLength

    let (left, right, remaining) = account.reportComponents(depth)
    let gapLength = maxReportLength - account.reportLength(depth)

    echo left & spaces(gapLength) & right
    for s in remaining:
        let fillLength = maxReportLength - (s.len + 3)
        echo "| ", spaces(fillLength), s

    for child in account.children:
        echo child.name
        child.echoSelf(maxReportLength, depth + 1)
