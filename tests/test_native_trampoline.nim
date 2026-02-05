import unittest

import ../src/gene/vm
import ./helpers
import ../src/gene/types except Exception

const TRAMPOLINE_OK = """
(do
  (fn /helper [x: Int] -> Int
    (+ x 1))
  (fn caller [y: Int] -> Int
    (helper y))
  (caller 10)
  caller)
"""

const TRAMPOLINE_UNTYPED = """
(do
  (fn /helper [x]
    (+ x 1))
  (fn caller [y: Int] -> Int
    (helper y))
  (caller 10)
  caller)
"""

const FIB_NATIVE = """
(do
  (fn fib [n: Int] -> Int
    (if (n < 2)
      n
    else
      (+ (fib (n - 1)) (fib (n - 2)))))
  (var a (fib 10))
  (var b (fib 20))
  [a b fib])
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

test "native codegen: fib runs natively":
  init_all()
  let prev = VM.native_code
  VM.native_code = true
  let result = VM.exec(FIB_NATIVE, "test_native_fib")
  VM.native_code = prev
  check result.kind == VkArray
  let items = array_data(result)
  check items.len == 3
  check items[0].to_int() == 55
  check items[1].to_int() == 6765
  check items[2].kind == VkFunction
  let f = items[2].ref.fn
  check f.native_ready
  check not f.native_failed
  check f.native_entry != nil
