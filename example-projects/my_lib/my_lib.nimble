# Package

version       = "0.1.0"
author        = "Guoliang Cao"
description   = "A test library in Gene language"
license       = "MIT"
srcDir        = "src"
installExt    = @["nim"]

# Dependencies

requires "nim >= 1.0.0"

task buildext, "Build the Nim extension":
  exec "nim c --app:lib --outdir:build/ src/my_lib/index.nim"
