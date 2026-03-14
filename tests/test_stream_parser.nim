import unittest

import gene/types except Exception
import gene/vm

import ./helpers

suite "Hash Array Runtime":
  init_all()

  test "empty immutable array literal":
    let result = VM.exec("#[]", "immutable_array_empty")
    check result.kind == VkArray
    check array_data(result).len == 0
    check array_is_frozen(result)
    check $result == "#[]"

  test "integer immutable array literal":
    let result = VM.exec("#[1 2 3]", "immutable_array_int")
    check result.kind == VkArray
    check array_data(result).len == 3
    check array_data(result)[0].to_int() == 1
    check array_data(result)[2].to_int() == 3
    check array_is_frozen(result)
    check $result == "#[1 2 3]"

  test "mixed immutable array literal":
    let result = VM.exec("#[\"hello\" 42 true]", "immutable_array_mixed")
    check result.kind == VkArray
    check array_data(result).len == 3
    check array_data(result)[0].str == "hello"
    check array_data(result)[1].to_int() == 42
    check array_data(result)[2] == TRUE
    check array_is_frozen(result)

  test "immutable array assignment and reuse":
    let script = """
      (var value #[1 2 3])
      value
    """
    let result = VM.exec(script, "immutable_array_assign")
    check result.kind == VkArray
    check array_data(result).len == 3
    check array_is_frozen(result)
