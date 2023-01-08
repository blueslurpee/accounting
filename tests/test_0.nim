import std/options
import ../account
import results

type R* = Result[void, string]


discard """"""
block:
    let tree = newAccountTree("USD")
    var account = tree.findAccount("Asset:Cash")
    assert account.isNone

    account = tree.findAccount("Asset")
    assert account.isSome

block:
    let tree = newAccountTree("USD")
    let account = newAccount(key="Asset:Cash", name="Cash", norm=Norm.Debit, kind=AccountKind.Asset, currencyKey="USD")
    let account2 = newAccount(key="Asset:Cash:Checking", name="Mercury Checking", norm=Norm.Debit, kind=AccountKind.Asset, currencyKey="USD")
    
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
    let tree = newAccountTree("USD")
    let account = newAccount(key="Asset:Cash:Checking", name="Mercury Checking", norm=Norm.Debit, kind=AccountKind.Asset, currencyKey="USD")
    
    var r = tree.insertAccount(account)
    assert r.isOk
    assert tree.assets.children[0].children.len == 1
    assert tree.assets.children[0].children[0].key == "Asset:Cash:Checking"

    var a = tree.findAccount("Asset:Cash:Checking")
    assert a.isSome
    assert a.get().key == "Asset:Cash:Checking"
    