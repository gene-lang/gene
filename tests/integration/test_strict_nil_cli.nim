import unittest, strutils

import commands/eval as eval_command

suite "Strict nil CLI":
  test "default eval remains nil-compatible for typed Int argument":
    let result = eval_command.handle("eval", @["(fn f [x: Int] x) (f nil)"])
    check result.success

  test "eval --strict-nil rejects nil at a typed Int argument boundary":
    let result = eval_command.handle("eval", @["--strict-nil", "(fn f [x: Int] x) (f nil)"])
    check not result.success
    checkpoint result.error
    check result.error.contains("GENE_TYPE_MISMATCH")
    check result.error.contains("strict nil mode")
