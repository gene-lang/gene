import unittest, strutils

import gene/compiler
import gene/parser
import gene/type_checker
import gene/types except Exception
import gene/vm

import ../helpers


template expect_tuple_error(expected_message_part: string, body: untyped) =
  try:
    body
    fail()
  except CatchableError as err:
    checkpoint err.msg
    check err.msg.contains(expected_message_part)


proc expect_tuple_source_error(code: string, expected_message_part: string) =
  init_all()
  try:
    discard VM.exec(cleanup(code), "test_code")
    fail()
  except CatchableError as err:
    checkpoint err.msg
    check err.msg.contains(expected_message_part)


proc expect_tuple_source_error_parts(code: string, expected_message_parts: openArray[string]) =
  init_all()
  try:
    discard VM.exec(cleanup(code), "test_code")
    fail()
  except CatchableError as err:
    checkpoint err.msg
    for expected_message_part in expected_message_parts:
      check err.msg.contains(expected_message_part)


proc typecheck_tuple_source(code: string) =
  let checker = type_checker.new_type_checker(strict = true, module_filename = "tuple_typecheck_test.gene")
  for node in parser.read_all(cleanup(code)):
    checker.type_check_node(node)


proc expect_tuple_typecheck_error_parts(code: string, expected_message_parts: openArray[string]) =
  try:
    typecheck_tuple_source(code)
    fail()
  except CatchableError as err:
    checkpoint err.msg
    for expected_message_part in expected_message_parts:
      check err.msg.contains(expected_message_part)


proc tuple_type_id_array_value(items: openArray[TypeId]): Value =
  var values: seq[Value] = @[]
  for item in items:
    values.add(item.to_value())
  new_array_value(values)


test_vm """
  (tuple Point x: Int y: Int)
  Point
""", proc(r: Value) =
  check r.kind == VkTupleDef
  if r.kind == VkTupleDef:
    let tupleDef = r.ref.tuple_def
    check tupleDef.name == "Point"
    check tupleDef.payload_shape == EpsNamed
    check tuple_payload_shape(tupleDef) == EpsNamed
    check tuple_payload_arity(tupleDef) == 2
    check tupleDef.fields == @["x", "y"]
    check tupleDef.field_type_ids == @[BUILTIN_TYPE_INT_ID, BUILTIN_TYPE_INT_ID]
    check tupleDef.field_type_descs.len > BUILTIN_TYPE_INT_ID.int
    if tupleDef.field_type_descs.len > BUILTIN_TYPE_INT_ID.int:
      let desc = tupleDef.field_type_descs[BUILTIN_TYPE_INT_ID]
      check desc.kind == TdkNamed
      check desc.name == "Int"


test_vm """
  (tuple Box Int)
  Box
""", proc(r: Value) =
  check r.kind == VkTupleDef
  if r.kind == VkTupleDef:
    let tupleDef = r.ref.tuple_def
    check tupleDef.name == "Box"
    check tupleDef.payload_shape == EpsPositional
    check tuple_payload_shape(tupleDef) == EpsPositional
    check tuple_payload_arity(tupleDef) == 1
    check tupleDef.fields.len == 0
    check tupleDef.field_type_ids == @[BUILTIN_TYPE_INT_ID]
    check tupleDef.field_type_descs.len > BUILTIN_TYPE_INT_ID.int
    if tupleDef.field_type_descs.len > BUILTIN_TYPE_INT_ID.int:
      let desc = tupleDef.field_type_descs[BUILTIN_TYPE_INT_ID]
      check desc.kind == TdkNamed
      check desc.name == "Int"


test_vm """
  (tuple Point x: Int y: Int)
  [Point (Point 1 2)]
""", proc(r: Value) =
  check r.kind == VkArray
  if r.kind == VkArray:
    let values = array_data(r)
    check values.len == 2
    if values.len == 2:
      let pointDef = values[0]
      let point = values[1]
      check pointDef.kind == VkTupleDef
      check point.kind == VkTupleValue
      if pointDef.kind == VkTupleDef and point.kind == VkTupleValue:
        check point.ref.tv_def == pointDef
        check point.ref.tv_data == @[1.to_value(), 2.to_value()]


test_vm """
  (tuple Point x: Int y: Int)
  [Point (Point ^y 20 ^x 10)]
""", proc(r: Value) =
  check r.kind == VkArray
  if r.kind == VkArray:
    let values = array_data(r)
    check values.len == 2
    if values.len == 2:
      let pointDef = values[0]
      let point = values[1]
      check pointDef.kind == VkTupleDef
      check point.kind == VkTupleValue
      if pointDef.kind == VkTupleDef and point.kind == VkTupleValue:
        check point.ref.tv_def == pointDef
        check point.ref.tv_data == @[10.to_value(), 20.to_value()]


test_vm """
  (tuple Box Int)
  [Box (Box 9)]
""", proc(r: Value) =
  check r.kind == VkArray
  if r.kind == VkArray:
    let values = array_data(r)
    check values.len == 2
    if values.len == 2:
      let boxDef = values[0]
      let box = values[1]
      check boxDef.kind == VkTupleDef
      check box.kind == VkTupleValue
      if boxDef.kind == VkTupleDef and box.kind == VkTupleValue:
        check box.ref.tv_def == boxDef
        check box.ref.tv_data == @[9.to_value()]


test_vm """
  (tuple Unit)
  [Unit (Unit)]
""", proc(r: Value) =
  check r.kind == VkArray
  if r.kind == VkArray:
    let values = array_data(r)
    check values.len == 2
    if values.len == 2:
      let unitDef = values[0]
      let unit = values[1]
      check unitDef.kind == VkTupleDef
      check unit.kind == VkTupleValue
      if unitDef.kind == VkTupleDef and unit.kind == VkTupleValue:
        check unit.ref.tv_def == unitDef
        check unit.ref.tv_data.len == 0


test_vm """
  (tuple Point label: String x: Int)
  (tuple Pair label: String x: Int)
  (var p (Point "hello" 7))
  [p (p .to_s) ((Point "hello" 7) == p) ((Point "hello" 8) == p) ((Pair "hello" 7) == p)]
""", proc(r: Value) =
  check r.kind == VkArray
  if r.kind == VkArray:
    let values = array_data(r)
    check values.len == 5
    if values.len == 5:
      check values[0].kind == VkTupleValue
      if values[0].kind == VkTupleValue:
        check values[0].str_no_quotes() == "(Point hello 7)"
        check $values[0] == "(Point \"hello\" 7)"
      check values[1] == "(Point \"hello\" 7)".to_value()
      check values[2] == TRUE
      check values[3] == FALSE
      check values[4] == FALSE


test "tuple equality compares nested payload values recursively":
  let descs = builtin_type_descs()
  let pointDef = new_tuple_def(
    name = "Point",
    fields = @[
      "x", "y",
    ],
    field_type_ids = @[BUILTIN_TYPE_INT_ID, BUILTIN_TYPE_INT_ID],
    field_type_descs = descs,
    payload_shape = EpsNamed,
  )
  let pointTypeValue = pointDef.to_value()
  let wrapperDef = new_tuple_def(
    name = "Wrapper",
    field_type_ids = @[NO_TYPE_ID],
    payload_shape = EpsPositional,
  )
  let wrapperTypeValue = wrapperDef.to_value()

  let left = new_tuple_value(wrapperTypeValue, @[
    new_tuple_value(pointTypeValue, @[1.to_value(), 2.to_value()]),
  ])
  let right = new_tuple_value(wrapperTypeValue, @[
    new_tuple_value(pointTypeValue, @[1.to_value(), 2.to_value()]),
  ])
  let differentNestedPayload = new_tuple_value(wrapperTypeValue, @[
    new_tuple_value(pointTypeValue, @[1.to_value(), 3.to_value()]),
  ])

  check left == right
  check left != differentNestedPayload


test "tuple equality and display reject malformed tuple metadata safely":
  let forgedDef = TupleDef(
    name: "Forged",
    payload_shape: EpsNamed,
    payload_arity: 2,
    fields: @[
      "x",
    ],
    field_type_ids: @[NO_TYPE_ID, NO_TYPE_ID],
  )
  let forgedTypeRef = new_ref(VkTupleDef)
  forgedTypeRef.tuple_def = forgedDef
  let forgedTypeValue = forgedTypeRef.to_ref_value()

  let leftRef = new_ref(VkTupleValue)
  leftRef.tv_def = forgedTypeValue
  leftRef.tv_data = @[1.to_value(), 2.to_value()]
  let left = leftRef.to_ref_value()

  let rightRef = new_ref(VkTupleValue)
  rightRef.tv_def = forgedTypeValue
  rightRef.tv_data = @[1.to_value(), 2.to_value()]
  let right = rightRef.to_ref_value()

  check not (left == left)
  check not (left == right)
  check left.str_no_quotes() == "<TupleValue>"
  check $left == "<TupleValue>"


test_vm """
  (tuple Point x: Int y: Int)
  (tuple Box Int)
  (var p (Point 10 20))
  (var box (Box 9))
  [p/x p/y p/0 p/1 box/0 (if (p/z == void) "missing-field" else "present") (if (box/1 == void) "missing-slot" else "present") (./ p "z" 99) (./ box 1 77)]
""", proc(r: Value) =
  check r.kind == VkArray
  if r.kind == VkArray:
    let values = array_data(r)
    check values.len == 9
    if values.len == 9:
      check values[0] == 10.to_value()
      check values[1] == 20.to_value()
      check values[2] == 10.to_value()
      check values[3] == 20.to_value()
      check values[4] == 9.to_value()
      check values[5] == "missing-field".to_value()
      check values[6] == "missing-slot".to_value()
      check values[7] == 99.to_value()
      check values[8] == 77.to_value()


test "tuple strict slash lookup reports missing fields before method fallback":
  expect_tuple_source_error("""
    (tuple Point x: Int y: Int)
    (var p (Point 1 2))
    (p/missing += 1)
  """, "Tuple Point has no field missing")


test "tuple payload dot access does not fall back to tuple fields":
  expect_tuple_source_error("""
    (tuple Point x: Int y: Int)
    (var p (Point 1 2))
    (p .x)
  """, "Unified method call not supported for VkTupleValue")


test "tuple constructors reject deterministic invalid call shapes":
  expect_tuple_source_error_parts("""
    (tuple Point x: Int y: Int)
    (Point 1)
  """, [
    "Tuple Point expects 2 arguments (x, y), got 1",
    "Point",
    "x, y",
  ])

  expect_tuple_source_error_parts("""
    (tuple Point x: Int y: Int)
    (Point 1 2 3)
  """, [
    "Tuple Point expects 2 arguments (x, y), got 3",
    "Point",
    "x, y",
  ])

  expect_tuple_source_error_parts("""
    (tuple Point x: Int y: Int)
    (Point 1 ^y 2)
  """, [
    "Tuple Point cannot mix positional and keyword arguments",
    "received 1 positional argument(s)",
    "keyword argument(s): y",
    "expected fields: x, y",
  ])

  expect_tuple_source_error_parts("""
    (tuple Point x: Int y: Int)
    (Point ^x 1)
  """, [
    "Tuple Point missing keyword argument(s): y; expected fields: x, y",
    "Point",
    "x, y",
  ])

  expect_tuple_source_error_parts("""
    (tuple Point x: Int y: Int)
    (Point ^x 1 ^z 3)
  """, [
    "Tuple Point got unknown keyword argument(s): z; expected fields: x, y",
    "Point",
    "z",
    "x, y",
  ])

  expect_tuple_source_error_parts("""
    (tuple Box Int)
    (Box)
  """, [
    "Tuple Box expects 1 arguments (#0), got 0",
    "Box",
    "#0",
  ])

  expect_tuple_source_error_parts("""
    (tuple Box Int)
    (Box 9 10)
  """, [
    "Tuple Box expects 1 arguments (#0), got 2",
    "Box",
    "#0",
  ])

  expect_tuple_source_error_parts("""
    (tuple Box Int)
    (Box ^value 9)
  """, [
    "Tuple Box has positional payload slots and does not accept keyword argument(s): value",
    "expected slots: #0",
  ])

  expect_tuple_source_error_parts("""
    (tuple Unit)
    (Unit 1)
  """, [
    "Unit tuple Unit expects 0 arguments, got 1",
    "Unit",
  ])

  expect_tuple_source_error_parts("""
    (tuple Unit)
    (Unit ^value 1)
  """, [
    "Unit tuple Unit expects 0 keyword arguments, got: value",
    "Unit",
    "value",
  ])

  # Duplicate `^key` source syntax remains parser-owned; this matrix covers
  # constructor-visible arity, mixed-call, missing, unknown, positional-keyword,
  # and unit payload failures.


test "tuple typed payload constructor diagnostics include tuple guard context":
  expect_tuple_source_error_parts("""
    (tuple Point x: Int y: Int)
    (Point "bad" 2)
  """, [
    "Type error [GENE_TYPE_MISMATCH]",
    "expected Int",
    "got String",
    "field Point.x",
    "phase=tuple-payload",
    "producer=tuple-constructor",
    "consumer=tuple-definition",
    "site=",
  ])

  expect_tuple_source_error_parts("""
    (tuple Point x: Int y: Int)
    (Point ^x "bad" ^y 2)
  """, [
    "Type error [GENE_TYPE_MISMATCH]",
    "expected Int",
    "got String",
    "field Point.x",
    "phase=tuple-payload",
    "producer=tuple-constructor",
    "consumer=tuple-definition",
    "site=",
  ])

  expect_tuple_source_error_parts("""
    (tuple Box Int)
    (Box "bad")
  """, [
    "Type error [GENE_TYPE_MISMATCH]",
    "expected Int",
    "got String",
    "field Box[0]",
    "phase=tuple-payload",
    "producer=tuple-constructor",
    "consumer=tuple-definition",
    "site=",
  ])


test "tuple declaration rejects malformed source syntax":
  expect_tuple_source_error("""
    (tuple Bad : Int)
  """, "tuple Bad has an empty field name")

  expect_tuple_source_error("""
    (tuple Bad x: 123)
  """, "tuple Bad field x has an invalid type annotation")

  expect_tuple_source_error("""
    (tuple Bad ^x Int)
  """, "tuple Bad field declarations must be positional, not properties")

  expect_tuple_source_error("""
    (tuple Bad x: Int x: Int)
  """, "tuple Bad has duplicate field x")

  expect_tuple_source_error("""
    (tuple Bad x:)
  """, "tuple Bad field x is missing a type after ':'")

  expect_tuple_source_error("""
    (tuple Bad x: Int String)
  """, "tuple Bad cannot mix named fields and positional type slots")


test_vm """
  (tuple Point x: Int y: Int)
  (tuple Box Int)
  (tuple Unit)
  (tuple Other x: Int y: Int)
  (var p (Point 10 20))
  (var b (Box 9))
  (var u (Unit))
  (var other (Other 10 20))
  [
    (case p
      when (Point x y:yy) (+ x yy)
      else -1)
    (case b
      when (Box value) value
      else -1)
    (case u
      when (Unit) 30
      else -1)
    (case other
      when (Point x y) (+ x y)
      else 40)
  ]
""", proc(r: Value) =
  check r == @[30, 9, 30, 40].to_value()


test "tuple case patterns type branch locals from tuple payload metadata":
  typecheck_tuple_source("""
    (tuple Point x: Int y: String)
    (fn use_int [value: Int] -> Int value)
    (fn use_string [value: String] -> String value)
    (var p (Point 10 "label"))
    (case p
      when (Point x y:label)
        (do
          (use_int x)
          (use_string label))
      else 0)
  """)

  expect_tuple_typecheck_error_parts("""
    (tuple Point x: Int y: String)
    (fn use_string [value: String] -> String value)
    (var p (Point 10 "label"))
    (case p
      when (Point x y)
        (use_string x)
      else "fallback")
  """, [
    "Type error: expected String, got Int",
    "call",
  ])


test "tuple type checker validates tuple case pattern diagnostics":
  expect_tuple_typecheck_error_parts("""
    (tuple Point x: Int y: String)
    (var p (Point 1 "two"))
    (case p
      when (Point x) x
      else 0)
  """, [
    "tuple Point pattern expects 2 binding(s)",
    "fields: x, y",
    "got 1",
  ])

  expect_tuple_typecheck_error_parts("""
    (tuple Point x: Int y: String)
    (var p (Point 1 "two"))
    (case p
      when (Point z:local y) local
      else 0)
  """, [
    "tuple pattern Point references unknown field z",
    "binding z:local",
    "expected fields: x, y",
  ])

  expect_tuple_typecheck_error_parts("""
    (tuple Box Int)
    (var b (Box 9))
    (case b
      when (Box value:v) v
      else 0)
  """, [
    "tuple pattern Box uses field alias value:v on a positional tuple",
    "expected slots: #0",
  ])

  expect_tuple_typecheck_error_parts("""
    (tuple Unit)
    (var u (Unit))
    (case u
      when (Unit extra) extra
      else 0)
  """, [
    "tuple Unit pattern expects 0 binding(s)",
    "got 1",
  ])

  expect_tuple_typecheck_error_parts("""
    (tuple Point x: Int y: String)
    (var p (Point 1 "two"))
    (case p
      when (Point 1 y) y
      else "fallback")
  """, [
    "tuple pattern Point binding must be a symbol",
    "expected fields: x, y",
  ])

  typecheck_tuple_source("""
    (tuple Point x: Int y: String)
    (fn use_string [value: String] -> String value)
    (var p (Point 1 "two"))
    (case p
      when (Point _ y)
        (use_string y)
      else "fallback")
  """)

  typecheck_tuple_source("""
    (fn use_string [value: String] -> String value)
    (var v "not-a-tuple")
    (case v
      when (UnknownTuple x)
        (use_string x)
      else "fallback")
  """)


test "tuple case patterns validate binder shape and field names":
  expect_tuple_source_error_parts("""
    (tuple Point x: Int y: Int)
    (var p (Point 1 2))
    (case p
      when (Point x) x
      else -1)
  """, [
    "tuple Point pattern expects 2 binding(s)",
    "fields: x, y",
    "got 1",
  ])

  expect_tuple_source_error_parts("""
    (tuple Point x: Int y: Int)
    (var p (Point 1 2))
    (case p
      when (Point z y) y
      else -1)
  """, [
    "tuple pattern Point references unknown field z",
    "binding z",
    "expected fields: x, y",
  ])

  expect_tuple_source_error_parts("""
    (tuple Point x: Int y: Int)
    (var p (Point 1 2))
    (case p
      when (Point z:zz y) zz
      else -1)
  """, [
    "tuple pattern Point references unknown field z",
    "binding z:zz",
    "expected fields: x, y",
  ])

  expect_tuple_source_error_parts("""
    (tuple Point x: Int y: Int)
    (var p (Point 1 2))
    (case p
      when (Point x x) x
      else -1)
  """, [
    "tuple pattern Point references duplicate field x",
    "binding x",
    "expected fields: x, y",
  ])

  expect_tuple_source_error_parts("""
    (tuple Box Int)
    (var b (Box 9))
    (case b
      when (Box value:v) v
      else -1)
  """, [
    "tuple pattern Box uses field alias value:v on a positional tuple",
    "expected slots: #0",
  ])

  expect_tuple_source_error_parts("""
    (tuple Unit)
    (var u (Unit))
    (case u
      when (Unit extra) extra
      else -1)
  """, [
    "tuple Unit pattern expects 0 binding(s)",
    "got 1",
  ])


test "tuple declaration metadata verifier rejects invalid field TypeId":
  let cu = new_compilation_unit()
  cu.type_registry = populate_registry(cu.type_descriptors, cu.module_path)
  cu.instructions.add(Instruction(
    kind: IkCreateTuple,
    arg0: tuple_type_id_array_value([999'i32])))

  expect_tuple_error(TypeMetadataInvalidMarker):
    verify_type_metadata(cu, phase = "tuple metadata verifier", source_path = "tuple_metadata_test.gene")


test "tuple declarations are collected as module type metadata":
  let cu = compiler.parse_and_compile(cleanup("""
    (tuple Point x: Int y: Int)
  """), "tuple_module.gene", module_mode = true)

  check cu.module_types.len == 1
  if cu.module_types.len == 1:
    check cu.module_types[0].name == "Point"
    check cu.module_types[0].kind == MtkTuple


test_vm """
  (tuple Point x: Int y: Int)
  (tuple Box Int)
  (tuple Unit)
  [Point Box Unit]
""", proc(r: Value) =
  check r.kind == VkArray
  if r.kind == VkArray:
    let values = array_data(r)
    check values.len == 3
    if values.len == 3:
      for i, expectedName in ["Point", "Box", "Unit"]:
        let tupleType = values[i]
        check tupleType.kind == VkTupleDef
        if tupleType.kind == VkTupleDef:
          let tupleDef = tupleType.ref.tuple_def
          check tupleDef.name == expectedName
          check tupleDef.module_path == "test_code"
          check tupleDef.internal_path == expectedName


test "direct named tuple definition and value allocation":
  let descs = builtin_type_descs()
  let pointDef = new_tuple_def(
    name = "Point",
    fields = @["x", "y"],
    field_type_ids = @[BUILTIN_TYPE_INT_ID, BUILTIN_TYPE_INT_ID],
    field_type_descs = descs,
    payload_shape = EpsNamed,
  )

  check pointDef.name == "Point"
  check pointDef.module_path == ""
  check pointDef.internal_path == ""
  check pointDef.payload_shape == EpsNamed
  check tuple_payload_shape(pointDef) == EpsNamed
  check tuple_payload_arity(pointDef) == 2
  check tuple_payload_slot_label(pointDef, 0) == "x"
  check tuple_payload_slot_label(pointDef, 1) == "y"
  check pointDef.fields == @["x", "y"]
  check pointDef.field_type_ids == @[BUILTIN_TYPE_INT_ID, BUILTIN_TYPE_INT_ID]
  check pointDef.field_type_descs.len == descs.len

  let pointTypeValue = pointDef.to_value()
  check pointTypeValue.kind == VkTupleDef
  check pointTypeValue.ref.tuple_def == pointDef

  let pointValue = new_tuple_value(pointTypeValue, @[10.to_value(), 20.to_value()])
  check pointValue.kind == VkTupleValue
  check pointValue.ref.tv_def == pointTypeValue
  check pointValue.ref.tv_data == @[10.to_value(), 20.to_value()]


test "direct positional tuple definition and value allocation":
  let descs = builtin_type_descs()
  let boxDef = new_tuple_def(
    name = "Box",
    field_type_ids = @[BUILTIN_TYPE_INT_ID],
    field_type_descs = descs,
    payload_shape = EpsPositional,
  )

  check boxDef.name == "Box"
  check boxDef.payload_shape == EpsPositional
  check tuple_payload_shape(boxDef) == EpsPositional
  check tuple_payload_arity(boxDef) == 1
  check tuple_payload_slot_label(boxDef, 0) == "#0"
  check boxDef.fields.len == 0
  check boxDef.field_type_ids == @[BUILTIN_TYPE_INT_ID]
  check boxDef.field_type_descs.len == descs.len

  let boxTypeValue = boxDef.to_value()
  check boxTypeValue.kind == VkTupleDef
  check boxTypeValue.ref.tuple_def == boxDef

  let boxValue = new_tuple_value(boxTypeValue, @[99.to_value()])
  check boxValue.kind == VkTupleValue
  check boxValue.ref.tv_def == boxTypeValue
  check boxValue.ref.tv_data == @[99.to_value()]


test "tuple metadata validation rejects malformed definitions":
  let descs = builtin_type_descs()

  expect_tuple_error("named payload metadata count 1 does not match payload arity 2"):
    discard new_tuple_def(
      name = "BadNamed",
      fields = @["x"],
      field_type_ids = @[BUILTIN_TYPE_INT_ID, BUILTIN_TYPE_INT_ID],
      field_type_descs = descs,
      payload_shape = EpsNamed,
      payload_arity = 2,
    )

  expect_tuple_error("positional payload metadata must not contain field names"):
    discard new_tuple_def(
      name = "BadPositional",
      fields = @["x"],
      field_type_ids = @[BUILTIN_TYPE_INT_ID],
      field_type_descs = descs,
      payload_shape = EpsPositional,
      payload_arity = 1,
    )

  expect_tuple_error("requires a tuple name"):
    discard new_tuple_def(name = "")

  var nilDef: TupleDef = nil
  expect_tuple_error("requires tuple metadata"):
    discard nilDef.to_value()

  let malformed = TupleDef(
    name: "Forged",
    payload_shape: EpsNamed,
    payload_arity: 2,
    fields: @["x"],
    field_type_ids: @[NO_TYPE_ID, NO_TYPE_ID],
  )
  expect_tuple_error("named payload metadata count 1 does not match payload arity 2"):
    discard malformed.to_value()

  let forgedShape = TupleDef(
    name: "ForgedShape",
    payload_shape: EpsUnit,
    payload_arity: 1,
    field_type_ids: @[NO_TYPE_ID],
  )
  expect_tuple_error("unit payload metadata must be empty"):
    discard forgedShape.to_value()


test "tuple value construction rejects invalid definition and payload shapes":
  let unitTypeValue = new_tuple_def(name = "Unit").to_value()

  expect_tuple_error("expects 0 payload value(s), got 1"):
    discard new_tuple_value(unitTypeValue, @[1.to_value()])

  expect_tuple_error("requires a tuple definition"):
    discard new_tuple_value(1.to_value(), @[])
