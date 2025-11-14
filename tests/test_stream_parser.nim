import unittest

import gene/types except Exception
import gene/vm

import ./helpers

suite "Hash Stream Parser":
  init_all()

  test "empty stream literal":
    let result = VM.exec("#[]", "stream_empty")
    check result.kind == VkStream
    check result.ref.stream.len == 0
    check result.ref.stream_index == 0
    check not result.ref.stream_ended

  test "integer stream literal":
    let result = VM.exec("#[1 2 3]", "stream_int")
    check result.kind == VkStream
    check result.ref.stream.len == 3
    check result.ref.stream[0].to_int() == 1
    check result.ref.stream[2].to_int() == 3

  test "mixed stream literal":
    let result = VM.exec("#[\"hello\" 42 true]", "stream_mixed")
    check result.kind == VkStream
    check result.ref.stream.len == 3
    check result.ref.stream[0].str == "hello"
    check result.ref.stream[1].to_int() == 42
    check result.ref.stream[2] == TRUE

  test "stream assignment and reuse":
    let script = """
      (var value #[1 2 3])
      value
    """
    let result = VM.exec(script, "stream_assign")
    check result.kind == VkStream
    check result.ref.stream.len == 3

