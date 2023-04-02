# Package
version       = "0.1.0"
author        = "cmbothwell"
description   = "Plain-text accounting written in Nim"
license       = "MIT"
srcDir        = "src"
binDir        = "bin"
bin           = @["tally"]


# Dependencies
requires "nim >= 1.9.1"
requires "cascade"
requires "result"
requires "decimal"
requires "npeg"


# Tasks
task demopdf, "Builds a demo pdf from libharu in C":
  exec("gcc -I/usr/local/include -L/usr/local/lib -lhpdf -o src/libharu/bin/demo src/libharu/main.c")
  exec("src/libharu/bin/demo")
  echo("   \e[1;92mSuccess:\e[0m Built demo pdf")