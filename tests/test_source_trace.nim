import unittest
import strutils
import gene/types except Exception
import gene/vm

import ./helpers

suite "Source trace diagnostics":
  test "Compile error includes source location":
    init_all()
    let code = "(match 1)"
    try:
      discard VM.exec(code, "sample.gene")
      check false
    except types.Exception as e:
      let msg = e.msg
      check "sample.gene" in msg
      check ":1:" in msg
      check "match expects exactly 2 arguments" in msg

  test "Runtime error includes source location":
    init_all()
    let code = "(do (throw \"boom\"))"
    try:
      discard VM.exec(code, "runtime.gene")
      check false
    except types.Exception as e:
      let msg = e.msg
      check "runtime.gene" in msg
      check ":1:" in msg
      check "boom" in msg
