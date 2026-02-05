import unittest

import ./helpers
import ../src/gene/types except Exception

const TRAMPOLINE_OK = """
(do
  (fn helper [x: Int] -> Int
    (+ x 1))
  (fn caller [y: Int] -> Int
    (helper y))
  (caller 10)
  caller)
"""

const TRAMPOLINE_UNTYPED = """
(do
  (fn helper [x]
    (+ x 1))
  (fn caller [y: Int] -> Int
    (helper y))
  (caller 10)
  caller)
"""

test "native trampoline: typed helper call compiles natively":
  init_all()
  let prev = VM.native_code
  VM.native_code = true
  let result = VM.exec(TRAMPOLINE_OK, "test_native_trampoline_ok")
  VM.native_code = prev
  check result.kind == VkFunction
  let f = result.ref.fn
  check f.native_ready
  check not f.native_failed
  check f.native_descriptors.len == 1

test "native trampoline: untyped callee disables native compile":
  init_all()
  let prev = VM.native_code
  VM.native_code = true
  let result = VM.exec(TRAMPOLINE_UNTYPED, "test_native_trampoline_untyped")
  VM.native_code = prev
  check result.kind == VkFunction
  let f = result.ref.fn
  check not f.native_ready
  check f.native_failed
