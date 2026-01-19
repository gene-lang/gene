import unittest

import gene/parser
import gene/compiler
import gene/types except Exception

suite "Eager function compilation":

  test "IkFunction payload includes compiled body when eager enabled":
    let code = """
      (fn foo [] 42)
      (foo)
    """
    let parsed = parser.read_all(code)
    let cu = compiler.compile(parsed, eager_functions = true)

    var found = false
    for i in 0..<cu.instructions.len:
      let inst = cu.instructions[i]
      if inst.kind == IkFunction:
        let info = to_function_def_info(inst.arg0)
        check info.compiled_body != nil
        found = true
        break
    check found

  test "IkFunction payload keeps compiled body nil when eager disabled":
    let code = """
      (fn bar [] 99)
      (bar)
    """
    let parsed = parser.read_all(code)
    let cu = compiler.compile(parsed)

    var found = false
    for i in 0..<cu.instructions.len:
      let inst = cu.instructions[i]
      if inst.kind == IkFunction:
        let info = to_function_def_info(inst.arg0)
        check info.compiled_body == nil
        found = true
        break
    check found
