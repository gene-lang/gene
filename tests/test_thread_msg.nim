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
    check array_data(map_data(roundtripped)["a".to_key()]).len == 3
    check map_data(roundtripped)["b".to_key()].str == "ok"

  test "non-literal payload is rejected":
    var r = new_ref(VkFuture)
    r.future = FutureObj(
      state: FsPending,
      value: NIL,
      success_callbacks: @[],
      failure_callbacks: @[],
      nim_future: nil
    )
    let non_literal = r.to_ref_value()
    expect type_defs.Exception:
      discard serialize_literal(non_literal)
