import unittest, strutils

import gene/compiler
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


test "tuple declaration rejects malformed source syntax":
  expect_tuple_source_error("""
    (tuple Bad x: Int x: Int)
  """, "tuple Bad has duplicate field x")

  expect_tuple_source_error("""
    (tuple Bad x:)
  """, "tuple Bad field x is missing a type after ':'")

  expect_tuple_source_error("""
    (tuple Bad x: Int String)
  """, "tuple Bad cannot mix named fields and positional type slots")


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
