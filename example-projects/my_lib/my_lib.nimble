# Package

version       = "0.1.0"
author        = "Guoliang Cao"
description   = "A test library in Gene language"
license       = "MIT"
srcDir        = "src"
installExt    = @["nim"]
binDir        = "build"
bin           = @["gene_dummy_lib"]  # Minimal stub so `nimble build` succeeds

# Dependencies

requires "nim >= 1.0.0"

task buildext, "Build the Nim extension":
  exec "nim c --app:lib --outdir:build/my_lib src/my_lib/index.nim"

# Make `nimble build` work by delegating to buildext (no binaries defined)
task build, "Build the Nim extension (alias for buildext)":
  exec "nimble buildext"
