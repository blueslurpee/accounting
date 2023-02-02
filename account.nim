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

proc reportComponents*(account: Account, reportingCurrencyKey: Option[string], depth: int = 0, maxBalanceLength: int = 0): tuple[left: string, right: string, remaining: seq[string]] =
    let left = "| " & spaces(2 * depth) & account.name
    let right = (
        if account.balances.len == 0: 
            "-- | " 
        else: 
            if account.balances.all(x => x.balance == newDecimal("0.00")):
                " -- | "
            else:
                let (currencyKey, balance) = account.balances[0]
                let gap = max(1 + maxBalanceLength - balance.toAccountingString.len, 1)
                currencyKey & spaces(gap) & balance.toAccountingString & " | "
    )
    
    var remaining: seq[string] = @[]
    for i in 1..account.balances.high:
        let (currencyKey, balance) = account.balances[i]
        let gap = max(1 + maxBalanceLength - balance.toAccountingString.len, 1)
        let line = 
            if reportingCurrencyKey.isSome():
                reportingCurrencyKey.get() & spaces(gap) & balance.toAccountingString
            else:
                currencyKey & spaces(gap) & balance.toAccountingString & " |"
        remaining.add(line)

    return (left, right, remaining)


proc reportLength*(account: Account, reportingCurrencyKey: Option[string], depth: int = 0, maxBalanceLength: int = 0): int =
    let (left, right, _) = account.reportComponents(reportingCurrencyKey, depth, maxBalanceLength)
    return left.len + right.len

proc maxReportLength*(account: Account, reportingCurrencyKey: Option[string], depth: int = 0, maxBalanceLength: int = 0): int =
    if account.children.len == 0:
        return account.reportLength(reportingCurrencyKey, depth, maxBalanceLength)
    else:
        return account.children.map(a => a.maxReportLength(reportingCurrencyKey, depth + 1, maxBalanceLength)).foldl(if a > b: a else: b, account.reportLength(reportingCurrencyKey, depth, maxBalanceLength))

proc maxBalanceLength*(account: Account): int = 
    if account.children.len == 0:
        return account.balances.map(b => b[1].toAccountingString.len).foldl(if a > b: a else: b, 1)
    else:
        let ownBalances = account.balances.map(b => b[1].toAccountingString.len).foldl(if a > b: a else: b, 1)
        return account.children.map(a => a.maxBalanceLength()).foldl(if a > b: a else: b, ownBalances)

proc maxReportLength*(tree: AccountTree, reportingCurrencyKey: Option[string], buffer: int = 10): int = 
    return max(@[tree.assets.maxReportLength(reportingCurrencyKey, 0), tree.liabilities.maxReportLength(reportingCurrencyKey, 0), tree.equity.maxReportLength(reportingCurrencyKey, 0), tree.revenue.maxReportLength(reportingCurrencyKey, 0), tree.expenses.maxReportLength(reportingCurrencyKey, 0)]) + buffer

proc maxBalanceLength*(tree: AccountTree): int =
    return max(@[tree.assets.maxBalanceLength(), tree.liabilities.maxBalanceLength(), tree.equity.maxBalanceLength(), tree.revenue.maxBalanceLength(), tree.expenses.maxBalanceLength()])

proc echoSelf*(account: Account, reportingCurrencyKey: Option[string], maxReportLength: int = -1, depth: int = 0, maxBalanceLength: int = 0): void =
    var maxReportLength = if maxReportLength == -1: account.maxReportLength(reportingCurrencyKey, depth, maxBalanceLength) else: maxReportLength
    let (left, right, remaining) = account.reportComponents(reportingCurrencyKey, depth, maxBalanceLength)
    let gapLength = maxReportLength - account.reportLength(reportingCurrencyKey, depth, maxBalanceLength)

    echo left & spaces(gapLength) & right
    for s in remaining:
        let fillLength = maxReportLength - (s.len + 3)
        echo "| ", spaces(fillLength), s

    for child in account.children:
        child.echoSelf(reportingCurrencyKey, maxReportLength, depth + 1, maxBalanceLength)
