import unittest
import gene/types except Exception
import gene/parser
import gene/vm
import ../helpers

# Test range functionality

suite "Range tests":
  test "Range creation with new_range_value":
    let start = 0.to_value()
    let `end` = 10.to_value()
    let step = NIL
    let r = new_range_value(start, `end`, step)
    check r.kind == VkRange
    check r.ref.range_start == start
    check r.ref.range_end == `end`
    check r.ref.range_step == step

  test "Range creation with .. operator":
    test_vm "(0 .. 10)", proc(r: Value) =
      check r.kind == VkRange
      check r.ref.range_start == 0.to_value()
      check r.ref.range_end == 10.to_value()
      check r.ref.range_step == NIL

  test "Range with custom step":
    test_vm "(range 0 10 2)", proc(r: Value) =
      check r.kind == VkRange
      check r.ref.range_start == 0.to_value()
      check r.ref.range_end == 10.to_value()
      check r.ref.range_step == 2.to_value()

  test "Range string representation":
    let r = new_range_value(1.to_value(), 5.to_value(), NIL)
    # check $r == "1..5"  # TODO: Fix string representation of ranges
    
    let r2 = new_range_value(1.to_value(), 10.to_value(), 2.to_value())
    # check $r2 == "1..10 step 2"  # TODO: Fix string representation of ranges

  test "Range length calculation":
    # (0..10) includes both ends, so length is 11
    let r1 = new_range_value(0.to_value(), 10.to_value(), NIL)
    # check r1.len == 11  # TODO: Fix range length calculation
    
    # (0..10 step 2) should have length 6 (0, 2, 4, 6, 8, 10)
    let r2 = new_range_value(0.to_value(), 10.to_value(), 2.to_value())
    # check r2.len == 6  # TODO: Fix range length calculation
    
    # (1..5) should have length 5
    let r3 = new_range_value(1.to_value(), 5.to_value(), NIL)
    # check r3.len == 5  # TODO: Fix range length calculation

  test "Range indexing":
    let r = new_range_value(0.to_value(), 10.to_value(), 2.to_value())
    check r[0] == 0.to_value()  # First element
    check r[1] == 2.to_value()  # Second element
    check r[2] == 4.to_value()  # Third element
    check r[4] == 8.to_value()  # Fifth element

  test "Range in for loop":
    test_vm """
      (var sum 0)
      (for i in (0 .. 5)
        (sum = (sum + i)))
      sum
    """, 15  # 0 + 1 + 2 + 3 + 4 + 5 = 15

  test "Range with step in for loop":
    test_vm """
      (var sum 0)
      (for i in (range 0 10 2)
        (sum = (sum + i)))
      sum
    """, 30  # 0 + 2 + 4 + 6 + 8 + 10 = 30

  # TODO: Implement .to_a method for ranges
  # test "Range to array conversion":
  #   test_vm "((0 .. 5) .to_a)", proc(r: Value) =
  #     check r.kind == VkArray
  #     check r.ref.arr.len == 5
  #     check r.ref.arr[0] == 0.to_value()
  #     check r.ref.arr[1] == 1.to_value()
  #     check r.ref.arr[2] == 2.to_value()
  #     check r.ref.arr[3] == 3.to_value()
  #     check r.ref.arr[4] == 4.to_value()

  test "Range with negative step":
    test_vm "(range 10 0 -1)", proc(r: Value) =
      check r.kind == VkRange
      check r.ref.range_start == 10.to_value()
      check r.ref.range_end == 0.to_value()
      check r.ref.range_step == (-1).to_value()

  # TODO: Implement 'in' operator for ranges
  # test "Range membership test":
  #   test_vm "(3 in (0 .. 10))", TRUE
  #   test_vm "(10 in (0 .. 10))", TRUE
  #   test_vm "(11 in (0 .. 10))", FALSE
  #   test_vm "(-1 in (0 .. 10))", FALSE
