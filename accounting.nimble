# Package

version       = "0.1.0"
author        = "cmbothwell"
description   = "Plain-text accounting written in Nim"
license       = "MIT"
srcDir        = "src"
bin           = @["accounting"]


# Dependencies

requires "nim >= 1.9.1"
requires "cascade"
requires "result"
requires "decimal"
requires "npeg"

