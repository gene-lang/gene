import unittest
import tables
import helpers
import gene/types except Exception
import gene/types/type_defs as type_defs except Exception
import gene/parser
import gene/serdes

suite "Thread message serialization":
  setup:
    helpers.init_all()

  test "literal payload roundtrips through serialize/deserialize":
    let value = read("{^a [1 2 3] ^b \"ok\"}")
    let ser = serialize_literal(value)
    let roundtripped = deserialize_literal(ser.to_s())
    check roundtripped.kind == VkMap
    check roundtripped.ref.map["a".to_key()].ref.arr.len == 3
    check roundtripped.ref.map["b".to_key()].str == "ok"

  test "non-literal payload is rejected":
    let non_literal = read("(fn [] 1)")
    expect type_defs.Exception:
      discard serialize_literal(non_literal)
