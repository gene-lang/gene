import unittest
import ./helpers
import gene/types except Exception

test_vm """
  ([1 2] .size)
""", 2

test_vm """
  ([1 2] ./0)
""", 1

test_vm """
  (var v [1 2])
  (v .set 0 3)
  v
""", proc(result: Value) =
  check result.kind == VkArray
  check result.ref.arr.len == 2
  check result.ref.arr[0] == 3.to_value()
  check result.ref.arr[1] == 2.to_value()

test_vm """
  ([1 2] .add 3)
""", proc(result: Value) =
  check result.kind == VkArray
  check result.ref.arr.len == 3
  check result.ref.arr[0] == 1.to_value()
  check result.ref.arr[1] == 2.to_value()
  check result.ref.arr[2] == 3.to_value()

test_vm """
  ([1 2] .del 0)
""", 1

test_vm """
  (fn inc i (i + 1))
  ([1 2] .map inc)
""", proc(result: Value) =
  check result.kind == VkArray
  check result.ref.arr.len == 2
  check result.ref.arr[0] == 2.to_value()
  check result.ref.arr[1] == 3.to_value()
