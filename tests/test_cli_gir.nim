import unittest, os

import gene/parser
import gene/compiler
import gene/gir
import gene/commands/gir as gir_command

suite "GIR CLI":
  test "gir show renders instructions":
    let source_path = "examples/hello_world.gene"
    let code = readFile(source_path)
    let parsed = parser.read_all(code)
    let compiled = compiler.compile(parsed)

    let out_dir = "build/tests"
    createDir(out_dir)
    let gir_path = out_dir / "hello_world_test.gir"
    gir.save_gir(compiled, gir_path, source_path)

    let result = gir_command.handle("gir", @["show", gir_path])
    check result.success
    check result.output.contains("GIR File: " & gir_path)
    check result.output.contains("Instructions (")
    check result.output.contains("Timestamp: ")

    let aliasResult = gir_command.handle("gir", @["visualize", gir_path])
    check aliasResult.success

    removeFile(gir_path)

  test "gir show reports missing file":
    let result = gir_command.handle("gir", @["show", "build/does_not_exist.gir"])
    check not result.success
    check result.error.contains("not found")
