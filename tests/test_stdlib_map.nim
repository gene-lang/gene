import unittest
import ./helpers
import gene/types except Exception

test_vm """
  ({^a 1 ^b 2} .size)
""", 2

test_vm """
  (fn toValue [k v] v)
  ({} .map toValue)
""", proc(result: Value) =
  check result.kind == VkArray
  check result.ref.arr.len == 0

test_vm """
  (fn toKey [k v] k)
  ({^a 1 ^b 2} .map toKey)
""", proc(result: Value) =
  check result.kind == VkArray
  check result.ref.arr.len == 2
  var keys: seq[string] = @[]
  for item in result.ref.arr:
    keys.add(item.str)
  check "a" in keys
  check "b" in keys

test_vm """
  (fn toValue [k v] v)
  ({^a 1 ^b 2} .map toValue)
""", proc(result: Value) =
  check result.kind == VkArray
  check result.ref.arr.len == 2
  var values: seq[int64] = @[]
  for item in result.ref.arr:
    values.add(item.int64)
  check 1 in values
  check 2 in values
