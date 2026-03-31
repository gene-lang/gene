import unittest
import strutils

import gene/types except Exception
import gene/vm

import ../helpers

suite "HashSet":
  test_vm """
    (do
      (var s (new HashSet 1 "two" [3 4] [3 4]))
      [(s .has 1) (s .has "two") (s .has [3 4]) (s .size)]
    )
  """, proc(result: Value) =
    check result.kind == VkArray
    check array_data(result) == @[TRUE, TRUE, TRUE, 3.to_value()]

  test_vm """
    (do
      (var s (new HashSet 1 2))
      (s .add 3 3)
      [(s .contains 3) (s .delete 2) (s .size) (s .delete 9) (do (s .clear) (s .size))]
    )
  """, proc(result: Value) =
    check result.kind == VkArray
    check array_data(result)[0] == TRUE
    check array_data(result)[1] == 2.to_value()
    check array_data(result)[2] == 2.to_value()
    check array_data(result)[3] == NIL
    check array_data(result)[4] == 0.to_value()

  test_vm """
    (do
      (var sum 0)
      (for x in (new HashSet 1 2 3)
        (sum += x)
      )
      sum
    )
  """, 6

  test_vm """
    (do
      (var a (new HashSet 1 2 3))
      (var b (new HashSet 3 4))
      [((a .union b) .to_array) ((a .intersect b) .to_array) ((a .diff b) .to_array) ((new HashSet 1 2) .subset? a)]
    )
  """, proc(result: Value) =
    check result.kind == VkArray
    check array_data(array_data(result)[0]) == @[1.to_value(), 2.to_value(), 3.to_value(), 4.to_value()]
    check array_data(array_data(result)[1]) == @[3.to_value()]
    check array_data(array_data(result)[2]) == @[1.to_value(), 2.to_value()]
    check array_data(result)[3] == TRUE

  test_vm """
    (do
      (class Key
        (ctor [id]
          (/id = id)
        )
        (method hash [] /id)
      )
      (var key (new Key 7))
      (var s (new HashSet key))
      (s .has key)
    )
  """, TRUE

  test_vm """
    (do
      (class BadKey
        (ctor [id]
          (/id = id)
        )
        (method hash [] 1)
      )
      (var k1 (new BadKey 1))
      (var k2 (new BadKey 2))
      (var s (new HashSet k1 k2))
      [(s .has k1) (s .has k2) (s .size)]
    )
  """, proc(result: Value) =
    check result.kind == VkArray
    check array_data(result)[0] == TRUE
    check array_data(result)[1] == TRUE
    check array_data(result)[2] == 2.to_value()

  test_vm """
    ((new HashSet 1 "two") .to_s)
  """, "(HashSet 1 \"two\")"

  test "unhashable objects are rejected":
    init_all()
    try:
      discard VM.exec("""
        (do
          (class NoHash
            (ctor []
              nil
            )
          )
          (var item (new NoHash))
          (new HashSet item)
        )
      """, "hash_set_unhashable.gene")
      fail()
    except CatchableError as e:
      check e.msg.contains("not hashable for HashSet")
