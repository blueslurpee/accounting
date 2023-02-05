import std/options
import std/times

import decimal/decimal
import results

import accounting/types
import accounting/account

type R* = Result[void, string]
let defaultDate = parse("2022-01-01", "yyyy-MM-dd")


discard """"""
block:
    let tree = newAccountTree(defaultDate)
    var account = tree.findAccount("Asset:Cash")
    assert account.isNone

block:
    let tree = newAccountTree(defaultDate)
    let account = newAccount(key="Asset:Cash", name="Cash", norm=Norm.Debit, kind=AccountKind.Asset, open=defaultDate)
    let account2 = newAccount(key="Asset:Cash:Checking", name="Mercury Checking", norm=Norm.Debit, kind=AccountKind.Asset, open=defaultDate)
    
    var r = tree.insertAccount(account)
    assert r.isOk
    assert tree.assets.children.len == 1
    assert tree.assets.children[0].key == "Asset:Cash"

    r = tree.insertAccount(account2)
    assert r.isOk
    assert tree.assets.children[0].children.len == 1
    assert tree.assets.children[0].children[0].key == "Asset:Cash:Checking"

    var a = tree.findAccount("Asset:Cash:Checking")
    assert a.isSome
    assert a.get().key == "Asset:Cash:Checking"

block:
    let tree = newAccountTree(defaultDate)
    let account = newAccount(key="Asset:Cash:Checking", name="Mercury Checking", norm=Norm.Debit, kind=AccountKind.Asset, open=defaultDate)
    
    var r = tree.insertAccount(account)
    assert r.isOk
    assert tree.assets.children[0].children.len == 1
    assert tree.assets.children[0].children[0].key == "Asset:Cash:Checking"

    var a = tree.findAccount("Asset:Cash:Checking")
    assert a.isSome
    assert a.get().key == "Asset:Cash:Checking"

block:
    let tree = newAccountTree(defaultDate)
    let account = newAccount(key="Asset:Cash:Checking", name="Mercury Checking", norm=Norm.Debit, kind=AccountKind.Asset, open=defaultDate)
    
    var r = tree.insertAccount(account)
    assert r.isOk
    assert tree.assets.children[0].children.len == 1
    assert tree.assets.children[0].children[0].key == "Asset:Cash:Checking"

    var a = tree.findAccount("Asset:Cash:Checking")
    assert a.isSome
    assert a.get().key == "Asset:Cash:Checking"

    let account2 = a.get()
    discard account2.incrementBalance("USD", newDecimal("100.00"))
    assert account2.getBalance("USD") == newDecimal("100.00")
    
    discard account2.decrementBalance("USD", newDecimal("200.00"))
    assert account2.getBalance("USD") == newDecimal("-100.00")
    discard account2.incrementBalance("EUR", newDecimal("100.00"))

    let account3 = newAccount(key="Asset:Cash:Savings", name="Mercury Savings", norm=Norm.Debit, kind=AccountKind.Asset, open=defaultDate)
    r = tree.insertAccount(account3)
    assert r.isOk
    discard account3.incrementBalance("CHF", newDecimal("1000.00"))
    assert account3.getBalance("CHF") == newDecimal("1000.00")
    tree.assets.echoSelf()

block:
    let tree = newAccountTree(defaultDate)
    let account = newAccount(key="Asset:Cash:Checking", name="Mercury Checking", norm=Norm.Debit, kind=AccountKind.Asset, open=defaultDate)

    var r = tree.insertAccount(account)
    assert r.isOk

    let parent = tree.findAccount("Asset:Cash")
    discard account.incrementBalance("USD", newDecimal("100.00"))
    assert account.getBalance("USD") == newDecimal("100.00")
    assert parent.get().getBalance("USD") == newDecimal("100.00")
    let root = tree.findAccount("Asset")
    assert root.get.getBalance("USD") == newDecimal("100.00")


    