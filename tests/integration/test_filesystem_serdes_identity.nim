import algorithm, os, strutils, tables, unittest

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
  FilesystemSerializableHandle = ref object of CustomValue
    id: int
    label: string

var filesystem_handle_class {.threadvar.}: Class

proc handle_payload(id: int, label: string): Value =
  new_map_value({
    "id".to_key(): id.to_value(),
    "label".to_key(): label.to_value(),
  }.to_table())

proc filesystem_handle_serialize(vm: ptr VirtualMachine, args: ptr UncheckedArray[Value],
                                 arg_count: int, has_keyword_args: bool): Value {.gcsafe, nimcall.} =
  discard vm
  if get_positional_count(arg_count, has_keyword_args) == 0:
    not_allowed("serialize requires self")
  let self_value = get_positional_arg(args, 0, has_keyword_args)
  let data = cast[FilesystemSerializableHandle](self_value.get_custom_data("FilesystemSerializableHandle payload missing"))
  handle_payload(data.id, data.label)

proc filesystem_handle_deserialize(vm: ptr VirtualMachine, args: ptr UncheckedArray[Value],
                                   arg_count: int, has_keyword_args: bool): Value {.gcsafe, nimcall.} =
  discard vm
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
  new_custom_value(class_value.ref.class, FilesystemSerializableHandle(id: id, label: label))

proc ensure_filesystem_handle_class() =
  if filesystem_handle_class.is_nil:
    filesystem_handle_class = new_class("FilesystemSerializableHandle")
    filesystem_handle_class.parent = App.app.object_class.ref.class
    filesystem_handle_class.def_native_method("serialize", filesystem_handle_serialize)
    filesystem_handle_class.def_native_method("deserialize", filesystem_handle_deserialize)

  var class_ref = new_ref(VkClass)
  class_ref.class = filesystem_handle_class
  App.app.global_ns.ref.ns["FilesystemSerializableHandle".to_key()] = class_ref.to_ref_value()

proc install_custom_handle_symbol(name: string, id: int, label: string) =
  ensure_filesystem_handle_class()
  App.app.global_ns.ref.ns[name.to_key()] = new_custom_value(
    filesystem_handle_class,
    FilesystemSerializableHandle(id: id, label: label),
  )

proc remove_tree(path: string) =
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
      remove_tree(child)
    of pcLinkToDir:
      removeDir(child)
    else:
      discard
  removeDir(path)

proc fresh_dir(name: string): string =
  result = joinPath(getTempDir(), "gene-filesystem-serdes-identity-" & name)
  remove_tree(result)
  createDir(result)

proc gene_string_literal(value: string): string =
  "\"" & value.replace("\\", "\\\\").replace("\"", "\\\"") & "\""

proc sorted_entries(path: string): seq[string] =
  for kind, entry in walkDir(path, relative = true):
    result.add($kind & ":" & entry)
  result.sort(system.cmp[string])

const TreeSerdesLeakFragments = ["_genetype", "_geneprops", "_genechildren", "_genearray", "^separate"]
const RemovedFilesystemPrefixes = ["read", "write"]

proc expect_no_tree_serdes_leak(label, text: string) =
  checkpoint(label & ": " & text)
  for fragment in TreeSerdesLeakFragments:
    checkpoint("forbidden tree-serdes fragment: " & fragment)
    check not text.contains(fragment)
  for prefix in RemovedFilesystemPrefixes:
    let api_name = prefix & "_" & "tree"
    checkpoint("forbidden removed API fragment: " & api_name)
    check not text.contains(api_name)

proc map_child(value: Value, key: string): Value =
  checkpoint("map child: " & key)
  check value.kind == VkMap
  if value.kind != VkMap:
    return NIL
  let k = key.to_key()
  check map_data(value).hasKey(k)
  if not map_data(value).hasKey(k):
    return NIL
  map_data(value)[k]

proc array_child(value: Value, index: int): Value =
  checkpoint("array child index: " & $index)
  check value.kind == VkArray
  if value.kind != VkArray:
    return NIL
  let items = array_data(value)
  check items.len > index
  if items.len <= index:
    return NIL
  items[index]

proc tuple_def_from_tuple_value(value: Value): TupleDef =
  checkpoint("tuple value kind")
  check value.kind == VkTupleValue
  if value.kind != VkTupleValue or value.ref == nil:
    return nil
  let tuple_def_value = value.ref.tv_def
  check tuple_def_value.kind == VkTupleDef
  if tuple_def_value.kind != VkTupleDef or tuple_def_value.ref == nil:
    return nil
  result = tuple_def_value.ref.tuple_def
  check result != nil

proc expect_enum_box(value: Value, module_fragment: string, payload: int) =
  checkpoint("enum payload identity: " & module_fragment)
  check value.kind == VkEnumValue
  if value.kind != VkEnumValue:
    return
  let variant = value.ref.ev_variant
  check variant.kind == VkEnumMember
  if variant.kind == VkEnumMember:
    check variant.ref.enum_member.name == "Box"
    check variant.ref.enum_member.parent.ref.enum_def.name == "Identity"
    check variant.ref.enum_member.module_path.contains(module_fragment)
  check value.ref.ev_data == @[payload.to_value()]

proc expect_enum_member(value: Value, module_fragment, member_name: string) =
  checkpoint("enum member identity: " & module_fragment & "/" & member_name)
  check value.kind == VkEnumMember
  if value.kind != VkEnumMember:
    return
  check value.ref.enum_member.name == member_name
  check value.ref.enum_member.parent.ref.enum_def.name == "Identity"
  check value.ref.enum_member.module_path.contains(module_fragment)

proc expect_named_pair(value: Value, module_fragment: string, left, right: int): TupleDef =
  checkpoint("tuple value identity: " & module_fragment)
  result = tuple_def_from_tuple_value(value)
  if result == nil:
    return
  check result.name == "NamedPair"
  check result.module_path.contains(module_fragment)
  check value.ref.tv_data == @[left.to_value(), right.to_value()]

proc expect_class_ref(value: Value) =
  checkpoint("class ref identity")
  check value.kind == VkClass
  if value.kind == VkClass:
    check value.ref.class.name == "ExportedThing"
    check value.ref.class.module_path.contains("serdes_objects")

proc expect_function_ref(value: Value) =
  checkpoint("function ref identity")
  check value.kind == VkFunction
  if value.kind == VkFunction:
    check value.ref.fn.name == "make_exported"
    check value.ref.fn.module_path.contains("serdes_objects")
    let made = VM.exec_function(value, @[])
    check made.kind == VkInstance
    if made.kind == VkInstance:
      check instance_props(made)["name".to_key()] == "from_fn".to_value()

proc expect_native_ref(value: Value) =
  checkpoint("native ref identity")
  check value.kind == VkNativeFn

proc expect_named_instance(value: Value) =
  checkpoint("named instance identity")
  check value.kind == VkInstance
  if value.kind == VkInstance:
    check instance_props(value)["name".to_key()] == "default".to_value()

proc expect_custom_handle(value: Value, id: int, label: string) =
  checkpoint("custom hook identity")
  check value.kind == VkCustom
  if value.kind != VkCustom:
    return
  check value.ref.custom_class == filesystem_handle_class
  let payload = cast[FilesystemSerializableHandle](value.get_custom_data("FilesystemSerializableHandle payload missing"))
  check payload.id == id
  check payload.label == label

proc expect_frozen_map(value: Value, key: string, expected: Value) =
  checkpoint("frozen map identity")
  check value.kind == VkMap
  if value.kind != VkMap:
    return
  check map_is_frozen(value)
  check map_data(value)[key.to_key()] == expected

proc expect_frozen_array(value: Value, expected: seq[Value]) =
  checkpoint("frozen array identity")
  check value.kind == VkArray
  if value.kind != VkArray:
    return
  check array_is_frozen(value)
  check array_data(value) == expected

proc expect_frozen_gene(value: Value, expected_type: string) =
  checkpoint("frozen gene identity")
  check value.kind == VkGene
  if value.kind != VkGene:
    return
  check gene_is_frozen(value)
  check value.gene.type == expected_type.to_symbol_value()

proc global_value(name: string): Value =
  let key = name.to_key()
  check App.app.global_ns.ref.ns.hasKey(key)
  if not App.app.global_ns.ref.ns.hasKey(key):
    return NIL
  App.app.global_ns.ref.ns[key]

proc publish_global(name: string, value: Value) =
  App.app.global_ns.ref.ns[name.to_key()] = value

proc new_payload_map(): Value =
  result = new_map_value()
  map_data(result) = initTable[Key, Value]()

proc put(payload: Value, key: string, value: Value) =
  map_data(payload)[key.to_key()] = value

proc identity_value(expr, source_name: string): Value =
  checkpoint("identity source value: " & source_name & " -> " & expr)
  let source = cleanup("""
    (import Identity:LeftIdentity from "tests/fixtures/s05_identity_left")
    (import Identity:RightIdentity from "tests/fixtures/s05_identity_right")
    (import NamedPair:LeftPair from "tests/fixtures/s05_tuple_identity_left")
    (import NamedPair:RightPair from "tests/fixtures/s05_tuple_identity_right")
    (import ExportedThing make_exported DEFAULT_THING from "tests/fixtures/serdes_objects")
    $EXPR
  """).replace("$EXPR", expr)
  VM.exec(source, source_name)

proc write_identity_payload(file_path, custom_symbol: string) =
  var payload = new_payload_map()
  put(payload, "leftEnum", identity_value("(LeftIdentity/Box 42)", "filesystem_serdes_identity_source_exact_left_enum"))
  put(payload, "rightEnum", identity_value("(RightIdentity/Box 42)", "filesystem_serdes_identity_source_exact_right_enum"))
  put(payload, "leftUnit", identity_value("LeftIdentity/Unit", "filesystem_serdes_identity_source_exact_left_unit"))
  put(payload, "rightUnit", identity_value("RightIdentity/Unit", "filesystem_serdes_identity_source_exact_right_unit"))
  put(payload, "leftTuple", identity_value("(LeftPair 1 2)", "filesystem_serdes_identity_source_exact_left_tuple"))
  put(payload, "rightTuple", identity_value("(RightPair 1 2)", "filesystem_serdes_identity_source_exact_right_tuple"))
  put(payload, "classRef", identity_value("ExportedThing", "filesystem_serdes_identity_source_exact_class"))
  put(payload, "functionRef", identity_value("make_exported", "filesystem_serdes_identity_source_exact_function"))
  put(payload, "nativeRef", identity_value("gene/serdes/read", "filesystem_serdes_identity_source_exact_native"))
  put(payload, "namedInstance", identity_value("DEFAULT_THING", "filesystem_serdes_identity_source_exact_instance"))
  put(payload, "customHook", global_value(custom_symbol))
  put(payload, "frozenMap", new_map_value({"locked".to_key(): TRUE}.to_table(), frozen = true))
  put(payload, "frozenArray", new_frozen_array_value(@[1.to_value(), 2.to_value(), 3.to_value()]))
  let frozen_gene = new_gene("FrozenNode".to_symbol_value(), frozen = true)
  frozen_gene.props["kind".to_key()] = "identity".to_value()
  frozen_gene.children.add(9.to_value())
  put(payload, "frozenGene", frozen_gene.to_gene_value())
  publish_global("filesystem_identity_payload_exact", payload)

  discard VM.exec("(gene/serdes/write " & gene_string_literal(file_path) & " filesystem_identity_payload_exact)",
    "filesystem_serdes_identity_write_exact")

proc write_externalized_identity_payload(file_path, custom_symbol: string) =
  var items = new_array_value()
  array_data(items).add(identity_value("(LeftIdentity/Box 7)", "filesystem_serdes_identity_source_external_left_enum"))
  array_data(items).add(identity_value("(RightIdentity/Box 7)", "filesystem_serdes_identity_source_external_right_enum"))
  array_data(items).add(identity_value("(LeftPair 3 4)", "filesystem_serdes_identity_source_external_left_tuple"))
  array_data(items).add(identity_value("(RightPair 3 4)", "filesystem_serdes_identity_source_external_right_tuple"))
  array_data(items).add(identity_value("ExportedThing", "filesystem_serdes_identity_source_external_class"))
  array_data(items).add(identity_value("make_exported", "filesystem_serdes_identity_source_external_function"))
  array_data(items).add(identity_value("gene/serdes/read", "filesystem_serdes_identity_source_external_native"))
  array_data(items).add(identity_value("DEFAULT_THING", "filesystem_serdes_identity_source_external_instance"))
  array_data(items).add(global_value(custom_symbol))

  var refs = new_payload_map()
  put(refs, "leftUnit", identity_value("LeftIdentity/Unit", "filesystem_serdes_identity_source_external_refs_left_unit"))
  put(refs, "rightUnit", identity_value("RightIdentity/Unit", "filesystem_serdes_identity_source_external_refs_right_unit"))
  put(refs, "classRef", identity_value("ExportedThing", "filesystem_serdes_identity_source_external_refs_class"))
  put(refs, "functionRef", identity_value("make_exported", "filesystem_serdes_identity_source_external_refs_function"))
  put(refs, "nativeRef", identity_value("gene/serdes/read", "filesystem_serdes_identity_source_external_refs_native"))
  put(refs, "namedInstance", identity_value("DEFAULT_THING", "filesystem_serdes_identity_source_external_refs_instance"))

  var frozen_map = new_map_value(frozen = true)
  map_data(frozen_map) = initTable[Key, Value]()
  put(frozen_map, "inner", identity_value("(LeftIdentity/Box 8)", "filesystem_serdes_identity_source_external_frozen_map_inner"))
  put(frozen_map, "locked", TRUE)

  let frozen_array = new_frozen_array_value(@["alpha".to_value(), "beta".to_value()])

  let frozen_gene = new_gene("FrozenNode".to_symbol_value(), frozen = true)
  frozen_gene.props["inner".to_key()] = identity_value("(LeftIdentity/Box 9)", "filesystem_serdes_identity_source_external_frozen_gene_inner")
  frozen_gene.children.add("leaf".to_value())

  var payload = new_payload_map()
  put(payload, "items", items)
  put(payload, "refs", refs)
  put(payload, "frozenMap", frozen_map)
  put(payload, "frozenArray", frozen_array)
  put(payload, "frozenGene", frozen_gene.to_gene_value())
  publish_global("filesystem_identity_payload_externalized", payload)

  discard VM.exec("(gene/serdes/write " & gene_string_literal(file_path) &
    " filesystem_identity_payload_externalized ^externalize [/items /refs /frozenMap /frozenArray /frozenGene/inner])",
    "filesystem_serdes_identity_write_externalized")

proc read_identity_payload(file_path: string, source_name: string): Value =
  reset_module_cache()
  discard VM.exec("1", source_name & "_module_reset")
  VM.exec("(gene/serdes/read " & gene_string_literal(file_path) & ")", source_name)

suite "filesystem serdes identity":
  test "write/read exact files preserve nominal identity values and frozen containers":
    init_all()
    init_serdes()
    install_custom_handle_symbol("filesystem_identity_custom_exact", 101, "exact")
    let root = fresh_dir("exact")
    defer: remove_tree(root)
    let file_path = joinPath(root, "state.gene")

    write_identity_payload(file_path, "filesystem_identity_custom_exact")
    let serialized = readFile(file_path)
    expect_no_tree_serdes_leak("exact identity payload", serialized)
    check serialized.contains("EnumValue")
    check serialized.contains("TupleValue")
    check serialized.contains("ClassRef")
    check serialized.contains("FunctionRef")
    check serialized.contains("InstanceRef")
    check serialized.contains("s05_identity_left")
    check serialized.contains("s05_identity_right")

    let read_back = read_identity_payload(file_path, "filesystem_serdes_identity_read_exact")
    let left_enum = map_child(read_back, "leftEnum")
    let right_enum = map_child(read_back, "rightEnum")
    expect_enum_box(left_enum, "s05_identity_left", 42)
    expect_enum_box(right_enum, "s05_identity_right", 42)
    if left_enum.kind == VkEnumValue and right_enum.kind == VkEnumValue:
      check left_enum != right_enum
      check left_enum.ref.ev_variant.ref.enum_member != right_enum.ref.ev_variant.ref.enum_member

    let left_unit = map_child(read_back, "leftUnit")
    let right_unit = map_child(read_back, "rightUnit")
    expect_enum_member(left_unit, "s05_identity_left", "Unit")
    expect_enum_member(right_unit, "s05_identity_right", "Unit")
    if left_unit.kind == VkEnumMember and right_unit.kind == VkEnumMember:
      check left_unit.ref.enum_member != right_unit.ref.enum_member

    let left_def = expect_named_pair(map_child(read_back, "leftTuple"), "s05_tuple_identity_left", 1, 2)
    let right_def = expect_named_pair(map_child(read_back, "rightTuple"), "s05_tuple_identity_right", 1, 2)
    if left_def != nil and right_def != nil:
      check left_def != right_def

    expect_class_ref(map_child(read_back, "classRef"))
    expect_function_ref(map_child(read_back, "functionRef"))
    expect_native_ref(map_child(read_back, "nativeRef"))
    expect_named_instance(map_child(read_back, "namedInstance"))
    expect_custom_handle(map_child(read_back, "customHook"), 101, "exact")
    expect_frozen_map(map_child(read_back, "frozenMap"), "locked", TRUE)
    expect_frozen_array(map_child(read_back, "frozenArray"), @[1.to_value(), 2.to_value(), 3.to_value()])
    expect_frozen_gene(map_child(read_back, "frozenGene"), "FrozenNode")

  test "externalized children use filesystem refs and preserve identity-sensitive payloads":
    init_all()
    init_serdes()
    install_custom_handle_symbol("filesystem_identity_custom_external", 202, "external")
    let root = fresh_dir("externalized")
    defer: remove_tree(root)
    let file_path = joinPath(root, "state.gene")
    let external_dir = joinPath(root, "state.files")
    let items_dir = joinPath(external_dir, "items")
    let refs_dir = joinPath(external_dir, "refs")
    let frozen_map_dir = joinPath(external_dir, "frozenMap")
    let frozen_array_dir = joinPath(external_dir, "frozenArray")
    let frozen_gene_inner = joinPath(external_dir, "frozenGene", "inner.gene")

    write_externalized_identity_payload(file_path, "filesystem_identity_custom_external")

    check fileExists(file_path)
    check dirExists(items_dir)
    check dirExists(refs_dir)
    check dirExists(frozen_map_dir)
    check dirExists(frozen_array_dir)
    check fileExists(frozen_gene_inner)

    let parent = readFile(file_path)
    expect_no_tree_serdes_leak("externalized identity parent", parent)
    check parent.contains("(gene/serdes/read_dir")
    check parent.contains(gene_string_literal(joinPath("state.files", "items")))
    check parent.contains(gene_string_literal(joinPath("state.files", "refs")))
    check parent.contains(gene_string_literal(joinPath("state.files", "frozenMap")))
    check parent.contains(gene_string_literal(joinPath("state.files", "frozenArray")))
    check parent.contains("^frozen true")
    check parent.contains("(gene/serdes/read_file " & gene_string_literal(joinPath("state.files", "frozenGene", "inner.gene")) & ")")

    check sorted_entries(items_dir) == @[
      $pcFile & ":000000.gene",
      $pcFile & ":000001.gene",
      $pcFile & ":000002.gene",
      $pcFile & ":000003.gene",
      $pcFile & ":000004.gene",
      $pcFile & ":000005.gene",
      $pcFile & ":000006.gene",
      $pcFile & ":000007.gene",
      $pcFile & ":000008.gene",
    ]
    check sorted_entries(refs_dir) == @[
      $pcFile & ":classRef.gene",
      $pcFile & ":functionRef.gene",
      $pcFile & ":leftUnit.gene",
      $pcFile & ":namedInstance.gene",
      $pcFile & ":nativeRef.gene",
      $pcFile & ":rightUnit.gene",
    ]

    let left_enum_child = readFile(joinPath(items_dir, "000000.gene"))
    let right_enum_child = readFile(joinPath(items_dir, "000001.gene"))
    let left_tuple_child = readFile(joinPath(items_dir, "000002.gene"))
    let right_tuple_child = readFile(joinPath(items_dir, "000003.gene"))
    let class_child = readFile(joinPath(items_dir, "000004.gene"))
    let function_child = readFile(joinPath(items_dir, "000005.gene"))
    let native_child = readFile(joinPath(items_dir, "000006.gene"))
    let instance_child = readFile(joinPath(items_dir, "000007.gene"))
    let custom_child = readFile(joinPath(items_dir, "000008.gene"))
    let frozen_map_inner = readFile(joinPath(frozen_map_dir, "inner.gene"))
    let frozen_array_first = readFile(joinPath(frozen_array_dir, "000000.gene"))
    let frozen_gene_inner_payload = readFile(frozen_gene_inner)

    for label, text in {
      "left enum child": left_enum_child,
      "right enum child": right_enum_child,
      "left tuple child": left_tuple_child,
      "right tuple child": right_tuple_child,
      "class child": class_child,
      "function child": function_child,
      "native child": native_child,
      "instance child": instance_child,
      "custom child": custom_child,
      "frozen map child": frozen_map_inner,
      "frozen array child": frozen_array_first,
      "frozen gene child": frozen_gene_inner_payload,
    }.to_table():
      expect_no_tree_serdes_leak(label, text)

    check left_enum_child.contains("EnumValue")
    check left_enum_child.contains("EnumRef")
    check left_enum_child.contains("s05_identity_left")
    check right_enum_child.contains("s05_identity_right")
    check left_tuple_child.contains("TupleValue")
    check left_tuple_child.contains("TupleRef")
    check left_tuple_child.contains("s05_tuple_identity_left")
    check right_tuple_child.contains("s05_tuple_identity_right")
    check class_child.contains("ClassRef")
    check function_child.contains("FunctionRef")
    check native_child.contains("FunctionRef")
    check native_child.contains("gene/serdes/read")
    check instance_child.contains("InstanceRef")
    check custom_child.contains("Instance")
    check custom_child.contains("FilesystemSerializableHandle")
    check frozen_map_inner.contains("EnumValue")
    check frozen_gene_inner_payload.contains("EnumValue")

    let read_back = read_identity_payload(file_path, "filesystem_serdes_identity_read_externalized")
    let items = map_child(read_back, "items")
    check items.kind == VkArray
    if items.kind == VkArray:
      check array_data(items).len == 9
      expect_enum_box(array_child(items, 0), "s05_identity_left", 7)
      expect_enum_box(array_child(items, 1), "s05_identity_right", 7)
      let left_def = expect_named_pair(array_child(items, 2), "s05_tuple_identity_left", 3, 4)
      let right_def = expect_named_pair(array_child(items, 3), "s05_tuple_identity_right", 3, 4)
      if left_def != nil and right_def != nil:
        check left_def != right_def
      expect_class_ref(array_child(items, 4))
      expect_function_ref(array_child(items, 5))
      expect_native_ref(array_child(items, 6))
      expect_named_instance(array_child(items, 7))
      expect_custom_handle(array_child(items, 8), 202, "external")

    let refs = map_child(read_back, "refs")
    expect_enum_member(map_child(refs, "leftUnit"), "s05_identity_left", "Unit")
    expect_enum_member(map_child(refs, "rightUnit"), "s05_identity_right", "Unit")
    expect_class_ref(map_child(refs, "classRef"))
    expect_function_ref(map_child(refs, "functionRef"))
    expect_native_ref(map_child(refs, "nativeRef"))
    expect_named_instance(map_child(refs, "namedInstance"))

    let frozen_map = map_child(read_back, "frozenMap")
    check frozen_map.kind == VkMap
    if frozen_map.kind == VkMap:
      check map_is_frozen(frozen_map)
      check map_child(frozen_map, "locked") == TRUE
      expect_enum_box(map_child(frozen_map, "inner"), "s05_identity_left", 8)

    let frozen_array = map_child(read_back, "frozenArray")
    expect_frozen_array(frozen_array, @["alpha".to_value(), "beta".to_value()])

    let frozen_gene = map_child(read_back, "frozenGene")
    expect_frozen_gene(frozen_gene, "FrozenNode")
    if frozen_gene.kind == VkGene:
      expect_enum_box(frozen_gene.gene.props["inner".to_key()], "s05_identity_left", 9)
      check frozen_gene.gene.children == @[
        "leaf".to_value(),
      ]
