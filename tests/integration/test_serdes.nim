import os, strutils, tables
import unittest

import gene/serdes
import gene/types except Exception
import gene/vm
import gene/vm/module

import ../helpers

proc reset_module_cache() =
  ModuleCache = initTable[string, Namespace]()
  ModuleLoadState = initTable[string, bool]()
  ModuleLoadStack = @[]

type
  SerializableHandle = ref object of CustomValue
    id: int
    label: string

var serializable_handle_class {.threadvar.}: Class
var missing_serialize_handle_class {.threadvar.}: Class
var missing_deserialize_handle_class {.threadvar.}: Class

proc serializable_handle_payload(id: int, label: string): Value =
  new_map_value({
    "id".to_key(): id.to_value(),
    "label".to_key(): label.to_value(),
  }.to_table())

proc custom_serialize_native(vm: ptr VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int,
                             has_keyword_args: bool): Value {.gcsafe, nimcall.} =
  if get_positional_count(arg_count, has_keyword_args) == 0:
    not_allowed("serialize requires self")
  let self_value = get_positional_arg(args, 0, has_keyword_args)
  let data = cast[SerializableHandle](self_value.get_custom_data("SerializableHandle payload missing"))
  serializable_handle_payload(data.id, data.label)

proc custom_deserialize_native(vm: ptr VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int,
                               has_keyword_args: bool): Value {.gcsafe, nimcall.} =
  if get_positional_count(arg_count, has_keyword_args) < 2:
    not_allowed("deserialize requires class and state")
  let class_value = get_positional_arg(args, 0, has_keyword_args)
  let state = get_positional_arg(args, 1, has_keyword_args)
  if class_value.kind != VkClass:
    not_allowed("deserialize expects a class receiver")
  if state.kind != VkMap:
    not_allowed("deserialize expects a map payload")

  let payload = map_data(state)
  let id = payload["id".to_key()].to_int()
  let label = payload["label".to_key()].str
  new_custom_value(class_value.ref.class, SerializableHandle(id: id, label: label))

proc ensure_custom_serdes_classes() =
  init_all()

  if serializable_handle_class.is_nil:
    serializable_handle_class = new_class("SerializableHandle")
    serializable_handle_class.parent = App.app.object_class.ref.class
    serializable_handle_class.def_native_method("serialize", custom_serialize_native)
    serializable_handle_class.def_native_method("deserialize", custom_deserialize_native)

    var class_ref = new_ref(VkClass)
    class_ref.class = serializable_handle_class
    App.app.global_ns.ns["SerializableHandle".to_key()] = class_ref.to_ref_value()

  if missing_serialize_handle_class.is_nil:
    missing_serialize_handle_class = new_class("MissingSerializeHandle")
    missing_serialize_handle_class.parent = App.app.object_class.ref.class
    missing_serialize_handle_class.def_native_method("deserialize", custom_deserialize_native)

    var class_ref = new_ref(VkClass)
    class_ref.class = missing_serialize_handle_class
    App.app.global_ns.ns["MissingSerializeHandle".to_key()] = class_ref.to_ref_value()

  if missing_deserialize_handle_class.is_nil:
    missing_deserialize_handle_class = new_class("MissingDeserializeHandle")
    missing_deserialize_handle_class.parent = App.app.object_class.ref.class
    missing_deserialize_handle_class.def_native_method("serialize", custom_serialize_native)

    var class_ref = new_ref(VkClass)
    class_ref.class = missing_deserialize_handle_class
    App.app.global_ns.ns["MissingDeserializeHandle".to_key()] = class_ref.to_ref_value()

test_serdes """
  1
""", 1

test_serdes """
  "abc"
""", "abc"

test_serdes """
  [1 2]
""", @[1, 2]

test_serdes """
  {^a 1}
""", new_map_value({"a".to_key(): new_gene_int(1)}.to_table())

test "Serdes: frozen maps preserve immutable flag":
  init_all()
  init_serdes()
  let value = VM.exec("#{^a 1}", "serdes_frozen_map_source")
  check value.kind == VkMap
  check map_is_frozen(value)
  let serialized = serialize(value).to_s()
  let roundtripped = deserialize(serialized)
  check roundtripped.kind == VkMap
  check map_is_frozen(roundtripped)
  check map_data(roundtripped)["a".to_key()] == 1.to_value()

test "Serdes: frozen genes preserve immutable flag":
  init_all()
  init_serdes()
  let value = VM.exec("#(1 ^a 2 3)", "serdes_frozen_gene_source")
  check value.kind == VkGene
  check gene_is_frozen(value)
  let serialized = serialize(value).to_s()
  let roundtripped = deserialize(serialized)
  check roundtripped.kind == VkGene
  check gene_is_frozen(roundtripped)
  check roundtripped.gene.type == 1.to_value()
  check roundtripped.gene.props["a".to_key()] == 2.to_value()
  check roundtripped.gene.children == @[3.to_value()]

test_serdes """
  `(a ^a 2 3 4)
""", proc(r: Value) =
  check r.gene_type == new_gene_symbol("a")
  check r.gene_props == {"a": new_gene_int(2)}.toTable
  check r.gene_children == @[3.to_value(), 4.to_value()]

test "Serdes: class refs use typed module paths and auto-import":
  init_all()
  init_serdes()
  let klass = VM.exec(cleanup("""
    (import ExportedThing from "tests/fixtures/serdes_objects")
    ExportedThing
  """), "serdes_class_source")
  let serialized = serialize(klass).to_s()
  check serialized.contains("ClassRef")
  check serialized.contains("^module")
  check serialized.contains("^path")

  reset_module_cache()
  discard VM.exec("1", "serdes_other_module")
  let roundtripped = deserialize(serialized)
  check roundtripped.kind == VkClass
  check roundtripped.ref.class.name == "ExportedThing"

test "Serdes: nested function refs roundtrip through typed refs":
  init_all()
  init_serdes()
  let fn_val = VM.exec(cleanup("""
    (import n/f from "tests/fixtures/mod1")
    f
  """), "serdes_fn_source")
  let serialized = serialize(fn_val).to_s()
  check serialized.contains("FunctionRef")
  check serialized.contains("n/f")

  reset_module_cache()
  discard VM.exec("1", "serdes_other_module")
  let roundtripped = deserialize(serialized)
  check roundtripped.kind == VkFunction
  check VM.exec_function(roundtripped, @[7.to_value()]) == 7.to_value()

test "Serdes: imported aliases keep canonical source paths":
  init_all()
  init_serdes()
  let values = VM.exec(cleanup("""
    (import ExportedThing:Thing make_exported:factory Status:State from "tests/fixtures/serdes_objects")
    [Thing factory State/ok]
  """), "serdes_alias_source")
  check values.kind == VkArray

  let class_ser = serialize(values[0]).to_s()
  check class_ser.contains("ClassRef")
  check class_ser.contains("ExportedThing")
  check not class_ser.contains("\"Thing\"")

  let fn_ser = serialize(values[1]).to_s()
  check fn_ser.contains("FunctionRef")
  check fn_ser.contains("make_exported")
  check not fn_ser.contains("\"factory\"")

  let enum_ser = serialize(values[2]).to_s()
  check enum_ser.contains("EnumRef")
  check enum_ser.contains("Status/ok")

test "Serdes: exported instances preserve identity via InstanceRef":
  init_all()
  init_serdes()
  let instance = VM.exec(cleanup("""
    (import DEFAULT_THING from "tests/fixtures/serdes_objects")
    DEFAULT_THING
  """), "serdes_instance_ref_source")
  let serialized = serialize(instance).to_s()
  check serialized.contains("InstanceRef")

  reset_module_cache()
  discard VM.exec("1", "serdes_other_module")
  let roundtripped = deserialize(serialized)
  check roundtripped.kind == VkInstance
  check instance_props(roundtripped)["name".to_key()] == "default".to_value()

test "Serdes: anonymous instances are rejected":
  init_all()
  init_serdes()
  let instance = VM.exec(cleanup("""
    (import ExportedThing from "tests/fixtures/serdes_objects")
    (var item (new ExportedThing "hammer"))
    item
  """), "serdes_instance_value_source")
  var raised = false
  try:
    discard serialize(instance)
  except CatchableError as e:
    raised = true
    check e.msg.contains("anonymous instances cannot be serialized")
  check raised

test "Serdes: legacy inline anonymous instance payloads are rejected":
  init_all()
  init_serdes()
  let module_path = absolutePath("tests/fixtures/serdes_objects.gene")
  let serialized = """
(gene/serialization
  (Instance
    (ClassRef ^path "ExportedThing" ^module "$1")
    {^name "hammer"}))
""".replace("$1", module_path)

  var raised = false
  try:
    discard deserialize(serialized)
  except CatchableError:
    raised = true
  check raised

test "Serdes: enum members use EnumRef and auto-import":
  init_all()
  init_serdes()
  let member = VM.exec(cleanup("""
    (import Status from "tests/fixtures/serdes_objects")
    Status/ok
  """), "serdes_enum_source")
  let serialized = serialize(member).to_s()
  check serialized.contains("EnumRef")
  check serialized.contains("Status/ok")

  reset_module_cache()
  discard VM.exec("1", "serdes_other_module")
  let roundtripped = deserialize(serialized)
  check roundtripped.kind == VkEnumMember
  check roundtripped.ref.enum_member.name == "ok"

test "Serdes: exported refs reserialize stably":
  init_all()
  init_serdes()
  let refs = VM.exec(cleanup("""
    (import ExportedThing make_exported DEFAULT_THING Status from "tests/fixtures/serdes_objects")
    [ExportedThing make_exported DEFAULT_THING Status/ok]
  """), "serdes_stable_source")
  check refs.kind == VkArray

  for item in array_data(refs):
    let first = serialize(item).to_s()
    let second = serialize(deserialize(first)).to_s()
    check second == first

test "Serdes: custom values roundtrip through Instance payload hooks":
  init_all()
  init_serdes()
  ensure_custom_serdes_classes()

  let value = new_custom_value(serializable_handle_class, SerializableHandle(id: 7, label: "demo"))
  let serialized = serialize(value).to_s()
  check serialized.contains("(Instance ")
  check serialized.contains("SerializableHandle")

  let roundtripped = deserialize(serialized)
  check roundtripped.kind == VkCustom
  check roundtripped.ref.custom_class == serializable_handle_class
  let payload = cast[SerializableHandle](roundtripped.get_custom_data("SerializableHandle payload missing"))
  check payload.id == 7
  check payload.label == "demo"
  check serialize(roundtripped).to_s() == serialized

test "Serdes: custom values require serialize hook":
  init_all()
  init_serdes()
  ensure_custom_serdes_classes()

  let value = new_custom_value(missing_serialize_handle_class, SerializableHandle(id: 1, label: "x"))
  var raised = false
  try:
    discard serialize(value)
  except CatchableError as e:
    raised = true
    check e.msg.contains("define serialize")
  check raised

test "Serdes: custom values require deserialize hook before serialization":
  init_all()
  init_serdes()
  ensure_custom_serdes_classes()

  let value = new_custom_value(missing_deserialize_handle_class, SerializableHandle(id: 1, label: "x"))
  var raised = false
  try:
    discard serialize(value)
  except CatchableError as e:
    raised = true
    check e.msg.contains("define deserialize")
  check raised

test "Serdes: custom Instance payloads require both hooks on deserialize":
  init_all()
  init_serdes()
  ensure_custom_serdes_classes()

  let serialized = """
(gene/serialization
  (Instance
    (ClassRef ^path "MissingSerializeHandle")
    {^id 3 ^label "oops"}))
"""
  var raised = false
  try:
    discard deserialize(serialized)
  except CatchableError as e:
    raised = true
    check e.msg.contains("define serialize")
  check raised

test "Serdes: anonymous closures are rejected":
  init_all()
  init_serdes()
  let fn_val = VM.exec(cleanup("""
    (var captured 1)
    (var f (fn [] captured))
    f
  """), "serdes_closure_source")
  var raised = false
  try:
    discard serialize(fn_val)
  except CatchableError:
    raised = true
  check raised

test "Serdes: futures are rejected":
  init_all()
  init_serdes()
  let future_val = VM.exec(cleanup("""
    (async 1)
  """), "serdes_future_source")
  check future_val.kind == VkFuture
  var raised = false
  try:
    discard serialize(future_val)
  except CatchableError:
    raised = true
  check raised

proc expect_deserialize_error_contains(serialized: string, expected_parts: openArray[string]) =
  var raised = false
  var message = ""
  try:
    discard deserialize(serialized)
  except CatchableError as e:
    raised = true
    message = e.msg
  checkpoint("deserialize error message: " & message)
  check raised
  for part in expected_parts:
    checkpoint("expecting error part: " & part)
    check message.contains(part)

proc s05_identity_left_module_path(): string =
  absolutePath("tests/fixtures/s05_identity_left")

proc s05_tuple_left_module_path(): string =
  absolutePath("tests/fixtures/s05_tuple_identity_left.gene")

proc s05_tuple_right_module_path(): string =
  absolutePath("tests/fixtures/s05_tuple_identity_right.gene")

proc remove_s05_tree(path: string) =
  if fileExists(path):
    removeFile(path)
    return
  if not dirExists(path):
    return

  for kind, child in walkDir(path):
    case kind
    of pcFile, pcLinkToFile:
      removeFile(child)
    of pcDir:
      remove_s05_tree(child)
    of pcLinkToDir:
      removeDir(child)
    else:
      discard
  removeDir(path)

proc fresh_s05_tree_path(name: string): string =
  result = joinPath(getTempDir(), "gene-s05-serdes-" & name)
  remove_s05_tree(result)
  remove_s05_tree(result & ".gene")

proc tuple_def_from_value(value: Value): TupleDef =
  check value.kind == VkTupleDef
  if value.kind != VkTupleDef or value.ref == nil:
    return nil
  result = value.ref.tuple_def
  check result != nil

proc tuple_def_from_tuple_value(value: Value): TupleDef =
  check value.kind == VkTupleValue
  if value.kind != VkTupleValue or value.ref == nil:
    return nil
  tuple_def_from_value(value.ref.tv_def)

test "Serdes: enum payload values use explicit EnumValue refs and stable roundtrip":
  init_all()
  init_serdes()
  let value = VM.exec(cleanup("""
    (import Identity:LeftIdentity from "tests/fixtures/s05_identity_left")
    (LeftIdentity/Box 42)
  """), "serdes_s05_enum_payload_source")
  check value.kind == VkEnumValue

  let serialized = serialize(value).to_s()
  check serialized.contains("EnumValue")
  check serialized.contains("EnumRef")
  check serialized.contains("Identity/Box")
  check serialized.contains("s05_identity_left")

  reset_module_cache()
  discard VM.exec("1", "serdes_s05_other_module")
  let roundtripped = deserialize(serialized)
  check roundtripped.kind == VkEnumValue
  if roundtripped.kind == VkEnumValue:
    let variant = roundtripped.ref.ev_variant
    check variant.kind == VkEnumMember
    if variant.kind == VkEnumMember:
      check variant.ref.enum_member.name == "Box"
      check variant.ref.enum_member.parent.ref.enum_def.name == "Identity"
      check variant.ref.enum_member.module_path.contains("s05_identity_left")
    check roundtripped.ref.ev_data == @[42.to_value()]
  check serialize(roundtripped).to_s() == serialized

test "Serdes: malformed EnumValue records reject before constructing values":
  init_all()
  init_serdes()
  let module_path = s05_identity_left_module_path()

  expect_deserialize_error_contains("""
(gene/serialization
  (EnumValue
    (ClassRef ^path "Identity" ^module "$MODULE")
    [1]))
""".replace("$MODULE", module_path), ["EnumValue", "EnumRef"])

  expect_deserialize_error_contains("""
(gene/serialization
  (EnumValue
    (EnumRef ^path "Identity/Missing" ^module "$MODULE")
    [1]))
""".replace("$MODULE", module_path), ["EnumValue", "Identity/Missing"])

  expect_deserialize_error_contains("""
(gene/serialization
  (EnumValue
    (EnumRef ^path "Identity/Box" ^module "$MODULE")
    []))
""".replace("$MODULE", module_path), ["EnumValue", "Identity/Box", "payload"])

  expect_deserialize_error_contains("""
(gene/serialization
  (EnumValue
    (EnumRef ^path "Identity/Box" ^module "$MODULE")
    ["wrong"]))
""".replace("$MODULE", module_path), ["GENE_TYPE_MISMATCH", "Identity/Box.value"])

test "Serdes: tuple definitions use TupleRef and auto-import":
  init_all()
  init_serdes()
  let defs = VM.exec(cleanup("""
    (import NamedPair PosBox UnitTuple from "tests/fixtures/s05_tuple_identity_left")
    [NamedPair PosBox UnitTuple]
  """), "serdes_s05_tuple_defs_source")
  check defs.kind == VkArray

  let names = @["NamedPair", "PosBox", "UnitTuple"]
  for i, expected_name in names:
    let tuple_def_value = array_data(defs)[i]
    let serialized = serialize(tuple_def_value).to_s()
    check serialized.contains("TupleRef")
    check serialized.contains(expected_name)
    check serialized.contains("s05_tuple_identity_left")

    reset_module_cache()
    discard VM.exec("1", "serdes_s05_tuple_defs_other_module")
    let roundtripped = deserialize(serialized)
    let tuple_def = tuple_def_from_value(roundtripped)
    check tuple_def.name == expected_name
    check tuple_def.module_path.contains("s05_tuple_identity_left")
    check tuple_def.internal_path == expected_name
    case expected_name
    of "NamedPair":
      check tuple_payload_shape(tuple_def) == EpsNamed
      check tuple_payload_arity(tuple_def) == 2
      check tuple_def.fields == @[
        "left",
        "right",
      ]
    of "PosBox":
      check tuple_payload_shape(tuple_def) == EpsPositional
      check tuple_payload_arity(tuple_def) == 2
      check tuple_def.fields.len == 0
    of "UnitTuple":
      check tuple_payload_shape(tuple_def) == EpsUnit
      check tuple_payload_arity(tuple_def) == 0
      check tuple_def.fields.len == 0
    else:
      fail()

    check serialize(roundtripped).to_s() == serialized

test "Serdes: tuple values use TupleValue refs and preserve ordered payloads":
  init_all()
  init_serdes()
  let values = VM.exec(cleanup("""
    (import NamedPair PosBox UnitTuple from "tests/fixtures/s05_tuple_identity_left")
    [(NamedPair ^right 8 ^left 7) (PosBox "token" 3) (UnitTuple)]
  """), "serdes_s05_tuple_values_source")
  check values.kind == VkArray

  let serialized = serialize(values).to_s()
  check serialized.contains("TupleValue")
  check serialized.contains("TupleRef")
  check serialized.contains("NamedPair")
  check serialized.contains("PosBox")
  check serialized.contains("UnitTuple")
  check serialized.contains("s05_tuple_identity_left")

  reset_module_cache()
  discard VM.exec("1", "serdes_s05_tuple_values_other_module")
  let roundtripped = deserialize(serialized)
  check roundtripped.kind == VkArray
  let items = array_data(roundtripped)
  check items.len == 3
  if items.len == 3:
    let named_def = tuple_def_from_tuple_value(items[0])
    check named_def.name == "NamedPair"
    check items[0].ref.tv_data == @[7.to_value(), 8.to_value()]

    let positional_def = tuple_def_from_tuple_value(items[1])
    check positional_def.name == "PosBox"
    check items[1].ref.tv_data == @[
      "token".to_value(),
      3.to_value(),
    ]

    let unit_def = tuple_def_from_tuple_value(items[2])
    check unit_def.name == "UnitTuple"
    check items[2].ref.tv_data.len == 0

  check serialize(roundtripped).to_s() == serialized

test "Serdes: same-shaped tuple values from different modules stay nominally distinct":
  init_all()
  init_serdes()
  let values = VM.exec(cleanup("""
    (import NamedPair:LeftPair from "tests/fixtures/s05_tuple_identity_left")
    (import NamedPair:RightPair from "tests/fixtures/s05_tuple_identity_right")
    [(LeftPair 1 2) (RightPair 1 2)]
  """), "serdes_s05_tuple_cross_module_source")
  let serialized = serialize(values).to_s()
  check serialized.contains("s05_tuple_identity_left")
  check serialized.contains("s05_tuple_identity_right")

  let roundtripped = deserialize(serialized)
  check roundtripped.kind == VkArray
  let items = array_data(roundtripped)
  check items.len == 2
  if items.len == 2:
    check items[0] != items[1]
    let left_def = tuple_def_from_tuple_value(items[0])
    let right_def = tuple_def_from_tuple_value(items[1])
    check left_def.name == "NamedPair"
    check right_def.name == "NamedPair"
    check left_def.module_path.contains("s05_tuple_identity_left")
    check right_def.module_path.contains("s05_tuple_identity_right")

test "Serdes: tuple tree serialization roundtrips recursive tuple payloads":
  init_all()
  init_serdes()
  let root_path = fresh_s05_tree_path("tuple-recursive")
  let code = cleanup("""
    (import NamedPair Wrapper from "tests/fixtures/s05_tuple_identity_left")
    (var nested (Wrapper (NamedPair 3 4)))
    (var second (NamedPair 5 6))
    (gene/serdes/write_tree "$ROOT" [nested second] ^separate [/*])
    (var loaded (gene/serdes/read_tree "$ROOT"))
    (assert ((loaded/0 == nested) == true))
    (assert (loaded/0/payload/left == 3))
    (assert (loaded/0/payload/right == 4))
    (assert (loaded/1/left == 5))
    (assert (loaded/1/right == 6))
    true
  """).replace("$ROOT", root_path)
  check VM.exec(code, "serdes_s05_tuple_tree_roundtrip") == TRUE

  let manifest = deserialize(readFile(joinPath(root_path, "_genearray.gene")))
  check manifest.kind == VkArray
  let ids = array_data(manifest)
  check ids.len == 2
  for item in ids:
    check item.kind == VkString
    if item.kind == VkString:
      let serialized_child = readFile(joinPath(root_path, item.str & ".gene"))
      check serialized_child.contains("TupleValue")
      check serialized_child.contains("TupleRef")

test "Serdes: malformed TupleValue records reject before constructing values":
  init_all()
  init_serdes()
  let module_path = s05_tuple_left_module_path()

  expect_deserialize_error_contains("""
(gene/serialization
  (TupleValue
    (ClassRef ^path "NamedPair" ^module "$MODULE")
    [1 2]))
""".replace("$MODULE", module_path), ["TupleValue", "TupleRef"])

  expect_deserialize_error_contains("""
(gene/serialization
  (TupleValue
    (TupleRef ^module "$MODULE")
    [1 2]))
""".replace("$MODULE", module_path), ["TupleValue", "TupleRef", "path"])

  expect_deserialize_error_contains("""
(gene/serialization
  (TupleValue
    (TupleRef ^path "NamedPair" ^module "$MODULE.missing")
    [1 2]))
""".replace("$MODULE", module_path), ["TupleValue", "TupleRef", "module"])

  expect_deserialize_error_contains("""
(gene/serialization
  (TupleValue
    (TupleRef ^path "MissingPair" ^module "$MODULE")
    [1 2]))
""".replace("$MODULE", module_path), ["TupleValue", "MissingPair"])

  expect_deserialize_error_contains("""
(gene/serialization
  (TupleValue
    (TupleRef ^path "NamedPair" ^module "$MODULE")
    {^left 1 ^right 2}))
""".replace("$MODULE", module_path), ["TupleValue", "payload", "array"])

  expect_deserialize_error_contains("""
(gene/serialization
  (TupleValue
    (TupleRef ^path "NamedPair" ^module "$MODULE")
    [1]))
""".replace("$MODULE", module_path), ["TupleValue", "NamedPair", "expects 2"])

  expect_deserialize_error_contains("""
(gene/serialization
  (TupleValue
    (TupleRef ^path "NamedPair" ^module "$MODULE")
    ["wrong" 2]))
""".replace("$MODULE", module_path), ["GENE_TYPE_MISMATCH", "NamedPair.left"])

  let tuple_def_value = VM.exec(cleanup("""
    (import NamedPair from "tests/fixtures/s05_tuple_identity_left")
    NamedPair
  """), "serdes_s05_tuple_malformed_metadata_source")
  let tuple_def = tuple_def_from_value(tuple_def_value)
  tuple_def.field_type_ids = @[1.TypeId]
  expect_deserialize_error_contains("""
(gene/serialization
  (TupleValue
    (TupleRef ^path "NamedPair" ^module "$MODULE")
    [1 2]))
""".replace("$MODULE", module_path), ["TupleValue", "NamedPair", "field type metadata"])

  tuple_def.field_type_ids = @[99.TypeId, 1.TypeId]
  tuple_def.field_type_descs = builtin_type_descs()
  expect_deserialize_error_contains("""
(gene/serialization
  (TupleValue
    (TupleRef ^path "NamedPair" ^module "$MODULE")
    [1 2]))
""".replace("$MODULE", module_path), ["TupleValue", "NamedPair", "left", "TypeId"])
