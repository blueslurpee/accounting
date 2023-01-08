import std/options
import std/times
import ../types
import ../account
import results

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
    