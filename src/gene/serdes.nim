import tables, strutils, sets, os, algorithm, hashes
import std/json
import std/uri

import ./types
from ./types/runtime_types import validate_or_coerce_type, emit_type_warning
import ./parser

type
  FilesystemReadContext* = ref object
    containing_file*: string
    base_dir*: string
    read_stack*: seq[string]

  Serialization* = ref object
    references*: Table[string, Value]
    data*: Value
    filesystem_context*: FilesystemReadContext

  SerializationRefKind* = enum
    SrkNamespace
    SrkClass
    SrkFunction
    SrkEnum
    SrkTuple
    SrkInstance

  SerializationOrigin* = object
    module_path*: string
    internal_path*: string
    kind*: SerializationRefKind

  SerdesModuleLoaderHook* = proc(module_path: string): Namespace {.nimcall.}

  TreeWriteOptions = object
    directory_nodes: HashSet[string]

  WriteSelector = object
    segments: seq[string]
    display: string

  PendingWriteChild = object
    selector_display: string
    relative_path: string
    absolute_path: string
    serialized_text: string
    child_label: string

  PendingWriteDirectory = object
    selector_display: string
    relative_path: string
    absolute_path: string

  WriteOptions = object
    externalize_selectors: seq[WriteSelector]
    selectors_by_key: Table[string, WriteSelector]
    external_dir_rel: string
    external_dir_abs: string
    parent_dir_abs: string
    target_path: string

  WritePayloadState = object
    serializer: Serialization
    directories: seq[PendingWriteDirectory]
    children: seq[PendingWriteChild]
    child_paths: Table[string, string]
    found_selectors: HashSet[string]

  LazyTreeReadOptions = object
    enabled: bool
    lazy_nodes: HashSet[string]

  ReadDirShape = enum
    RdsArray
    RdsMap

  ReadDirOrder = enum
    RdoName

  ReadDirOptions = object
    shape: ReadDirShape
    order: ReadDirOrder

  FilesystemTreeReadStats* = object
    serialized_file_reads*: int
    dir_listings*: int

  LazyTreeSourceKind = enum
    LtsFile
    LtsDirectory

  LazyTreeValueData = ref object of CustomValue
    path: string
    source_kind: LazyTreeSourceKind
    node_segments: seq[string]
    options: LazyTreeReadOptions
    materialized: Value
    materialized_loaded: bool

  LazyFileRefValueData = ref object of CustomValue
    target_path: string
    filesystem_context: FilesystemReadContext
    ref_kind: string
    materialized: Value
    materialized_loaded: bool

var
  tree_read_stats {.threadvar.}: FilesystemTreeReadStats
  lazy_tree_value_class {.threadvar.}: Class
  lazy_file_ref_value_class {.threadvar.}: Class
  # Cache serialization origins per thread by raw Value identity.
  #
  # Using value.raw is appropriate for Gene's NaN-boxed Value model: the same
  # runtime object is normally observed through the same raw payload, and the
  # canonical origin is also stamped onto the underlying object when available.
  value_origin_registry {.threadvar.}: Table[uint64, SerializationOrigin]
  value_origin_registry_ready {.threadvar.}: bool
  serdes_module_loader_hook*: SerdesModuleLoaderHook

proc serialize*(self: Serialization, value: Value): Value {.gcsafe.}
proc to_path*(self: Value): string {.gcsafe.}
proc to_path*(self: Class): string {.gcsafe.}
proc is_literal_value*(v: Value): bool {.inline, gcsafe.}
proc serialize_literal*(value: Value): Serialization {.gcsafe.}
proc deserialize*(s: string): Value {.gcsafe.}
proc deserialize_literal*(s: string): Value {.gcsafe.}
proc to_s*(self: Serialization): string
proc path_to_value*(path: string): Value {.gcsafe.}
proc tag_namespace_serialization_origins*(ns: Namespace, module_path: string, prefix = "") {.gcsafe.}
proc tag_stdlib_serialization_origins*() {.gcsafe.}
proc set_serdes_module_loader_hook*(hook: SerdesModuleLoaderHook) {.inline.}

proc key_to_string(k: Key): string {.inline, gcsafe.}
proc filesystem_is_subpath(base_path, candidate_path: string): bool {.inline, gcsafe.}

proc read_tree_dir(path: string, node_segments: seq[string], options: LazyTreeReadOptions, shallow: bool): Value {.gcsafe.}

const
  TreeGeneTypeName = "_genetype"
  TreeGenePropsName = "_geneprops"
  TreeGeneChildrenName = "_genechildren"
  TreeArrayName = "_genearray"

proc reset_tree_read_stats*() =
  tree_read_stats = FilesystemTreeReadStats()

proc filesystem_tree_read_stats*(): FilesystemTreeReadStats =
  tree_read_stats

proc count_tree_serialized_file_read() {.inline, gcsafe.} =
  tree_read_stats.serialized_file_reads.inc()

proc count_tree_dir_listing() {.inline, gcsafe.} =
  tree_read_stats.dir_listings.inc()

proc is_lazy_tree_value*(value: Value): bool {.inline, gcsafe.} =
  if value.kind != VkCustom:
    return false
  let ref_data = value.ref
  if cast[pointer](ref_data) == nil:
    return false
  let custom_data = ref_data.custom_data
  if cast[pointer](custom_data) == nil:
    return false
  custom_data of LazyTreeValueData

proc is_lazy_file_ref_value*(value: Value): bool {.inline, gcsafe.} =
  if value.kind != VkCustom:
    return false
  let ref_data = value.ref
  if cast[pointer](ref_data) == nil:
    return false
  let custom_data = ref_data.custom_data
  if cast[pointer](custom_data) == nil:
    return false
  custom_data of LazyFileRefValueData

proc materialize_lazy_tree_value*(value: Value): Value {.gcsafe.}
proc materialize_lazy_file_ref_value*(value: Value): Value {.gcsafe.}
proc materialize_custom_value(value: Value): Value {.inline, gcsafe.}
proc materialize_custom_deep*(value: Value): Value {.gcsafe.}
proc materialize_lazy_tree_deep*(value: Value): Value {.gcsafe.}
proc find_live_origin(target: Value): tuple[found: bool, origin: SerializationOrigin] {.gcsafe.}
proc class_to_value(self: Class): Value {.inline, gcsafe.}
proc namespace_runtime_module_path(ns: Namespace): string {.gcsafe.}
proc simple_member_origin(ns: Namespace, name: string, target: Value,
                          kind: SerializationRefKind): tuple[found: bool, origin: SerializationOrigin] {.gcsafe.}

proc set_serdes_module_loader_hook*(hook: SerdesModuleLoaderHook) {.inline.} =
  serdes_module_loader_hook = hook

proc ensure_value_origin_registry() {.inline, gcsafe.} =
  if not value_origin_registry_ready:
    value_origin_registry = initTable[uint64, SerializationOrigin]()
    value_origin_registry_ready = true

proc ref_kind_name(kind: SerializationRefKind): string {.inline.} =
  case kind:
  of SrkNamespace: "NamespaceRef"
  of SrkClass: "ClassRef"
  of SrkFunction: "FunctionRef"
  of SrkEnum: "EnumRef"
  of SrkTuple: "TupleRef"
  of SrkInstance: "InstanceRef"

proc make_origin(kind: SerializationRefKind, module_path, internal_path: string): SerializationOrigin {.inline.} =
  SerializationOrigin(
    module_path: module_path,
    internal_path: internal_path,
    kind: kind,
  )

proc join_origin_path(prefix, name: string): string {.inline.} =
  if prefix.len == 0:
    return name
  prefix & "/" & name

proc new_typed_ref(kind: SerializationRefKind, internal_path: string, module_path = ""): Value =
  let gene = new_gene(ref_kind_name(kind).to_symbol_value())
  gene.props["path".to_key()] = internal_path.to_value()
  if module_path.len > 0:
    gene.props["module".to_key()] = module_path.to_value()
  gene.to_gene_value()

proc new_serialized_instance(class_ref: Value, props: Value): Value =
  let gene = new_gene("Instance".to_symbol_value())
  gene.children.add(class_ref)
  gene.children.add(props)
  gene.to_gene_value()

proc new_serialized_enum_value(member_ref: Value, payloads: Value): Value =
  let gene = new_gene("EnumValue".to_symbol_value())
  gene.children.add(member_ref)
  gene.children.add(payloads)
  gene.to_gene_value()

proc new_serialized_tuple_value(tuple_ref: Value, payloads: Value): Value =
  let gene = new_gene("TupleValue".to_symbol_value())
  gene.children.add(tuple_ref)
  gene.children.add(payloads)
  gene.to_gene_value()

proc new_legacy_gene_ref(path: string): Value =
  let gene = new_gene("gene/ref".to_symbol_value())
  gene.children.add(path.to_value())
  gene.to_gene_value()

proc new_legacy_gene_instance(class_ref: Value, props: Value): Value =
  let gene = new_gene("gene/instance".to_symbol_value())
  gene.children.add(class_ref)
  gene.children.add(props)
  gene.to_gene_value()

proc should_skip_origin_member(name: string): bool {.inline.} =
  name.len == 0 or name.startsWith("__") or name == "gene" or name == "genex"

proc namespace_has_explicit_exports(ns: Namespace): bool {.inline, gcsafe.} =
  if ns == nil:
    return false
  let exports_val = ns.members.getOrDefault("__exports__".to_key(), NIL)
  exports_val != NIL and exports_val.kind == VkMap

proc namespace_path_is_exported(ns: Namespace, path: string): bool {.gcsafe.} =
  if ns == nil:
    return false
  let exports_val = ns.members.getOrDefault("__exports__".to_key(), NIL)
  if exports_val == NIL or exports_val.kind != VkMap:
    return true
  let exports_map = map_data(exports_val)
  if exports_map.hasKey(path.to_key()):
    return true
  let parts = path.split("/")
  if parts.len > 1:
    var prefix = ""
    for i in 0..<parts.len - 1:
      prefix = join_origin_path(prefix, parts[i])
      if exports_map.hasKey(prefix.to_key()):
        return true
  false

proc register_value_origin(value: Value, origin: SerializationOrigin) {.gcsafe.} =
  ensure_value_origin_registry()
  value_origin_registry[value.raw] = origin

proc assign_value_origin(value: Value, origin: SerializationOrigin) {.gcsafe.} =
  register_value_origin(value, origin)
  case value.kind:
  of VkNamespace:
    if value.ref.ns != nil:
      value.ref.ns.module_path = origin.module_path
      value.ref.ns.internal_path = origin.internal_path
  of VkClass:
    if value.ref.class != nil:
      value.ref.class.module_path = origin.module_path
      value.ref.class.internal_path = origin.internal_path
  of VkFunction:
    if value.ref.fn != nil:
      value.ref.fn.module_path = origin.module_path
      value.ref.fn.internal_path = origin.internal_path
  of VkEnum:
    if value.ref.enum_def != nil:
      value.ref.enum_def.module_path = origin.module_path
      value.ref.enum_def.internal_path = origin.internal_path
      for member_name, member in value.ref.enum_def.members:
        if member != nil:
          let member_origin = make_origin(SrkEnum, origin.module_path,
            join_origin_path(origin.internal_path, member_name))
          member.module_path = member_origin.module_path
          member.internal_path = member_origin.internal_path
          register_value_origin(member.to_value(), member_origin)
  of VkEnumMember:
    if value.ref.enum_member != nil:
      value.ref.enum_member.module_path = origin.module_path
      value.ref.enum_member.internal_path = origin.internal_path
  of VkTupleDef:
    if value.ref.tuple_def != nil:
      value.ref.tuple_def.module_path = origin.module_path
      value.ref.tuple_def.internal_path = origin.internal_path
  of VkInstance:
    let data = instance_ptr(value)
    if data != nil:
      data.module_path = origin.module_path
      data.internal_path = origin.internal_path
  else:
    discard

proc lookup_class_origin(self: Class): tuple[found: bool, origin: SerializationOrigin] {.gcsafe.} =
  if self != nil and self.internal_path.len > 0:
    return (true, make_origin(SrkClass, self.module_path, self.internal_path))
  if self != nil and self.name.len > 0:
    let target = class_to_value(self)
    if VM != nil and VM.frame != nil and VM.frame.ns != nil:
      let current = simple_member_origin(VM.frame.ns, self.name, target, SrkClass)
      if current.found:
        self.module_path = current.origin.module_path
        self.internal_path = current.origin.internal_path
        return current
    if App != NIL and App.kind == VkApplication and App.app.global_ns.kind == VkNamespace:
      let global = simple_member_origin(App.app.global_ns.ref.ns, self.name, target, SrkClass)
      if global.found:
        self.module_path = global.origin.module_path
        self.internal_path = global.origin.internal_path
        return global
  if self != nil:
    let live = find_live_origin(class_to_value(self))
    if live.found:
      self.module_path = live.origin.module_path
      self.internal_path = live.origin.internal_path
      return (true, make_origin(SrkClass, self.module_path, self.internal_path))
  (false, SerializationOrigin())

proc namespace_runtime_module_path(ns: Namespace): string {.gcsafe.} =
  if ns == nil:
    return ""
  let module_name = ns.members.getOrDefault("__module_name__".to_key(), NIL)
  if module_name.kind in {VkString, VkSymbol}:
    return module_name.str
  ns.module_path

proc simple_member_origin(ns: Namespace, name: string, target: Value,
                          kind: SerializationRefKind): tuple[found: bool, origin: SerializationOrigin] {.gcsafe.} =
  if ns == nil or name.len == 0:
    return (false, SerializationOrigin())
  let member = ns.members.getOrDefault(name.to_key(), NIL)
  if member == NIL:
    return (false, SerializationOrigin())
  case kind:
  of SrkClass:
    if member.kind == VkClass and target.kind == VkClass and member.ref.class == target.ref.class:
      return (true, make_origin(kind, namespace_runtime_module_path(ns), name))
  of SrkFunction:
    if member.kind == target.kind and member.raw == target.raw:
      return (true, make_origin(kind, namespace_runtime_module_path(ns), name))
    if member.kind == VkFunction and target.kind == VkFunction and member.ref.fn == target.ref.fn:
      return (true, make_origin(kind, namespace_runtime_module_path(ns), name))
  of SrkTuple:
    if member.kind == VkTupleDef and target.kind == VkTupleDef and member.ref.tuple_def == target.ref.tuple_def:
      return (true, make_origin(kind, namespace_runtime_module_path(ns), name))
  else:
    discard
  (false, SerializationOrigin())

proc find_live_origin_in_namespace(ns: Namespace, target: Value, module_path: string,
                                   prefix: string, seen: var HashSet[pointer]): tuple[found: bool, origin: SerializationOrigin] {.gcsafe.} =
  if ns == nil:
    return (false, SerializationOrigin())
  let key = cast[pointer](ns)
  if seen.contains(key):
    return (false, SerializationOrigin())
  seen.incl(key)

  for member_key, member_value in ns.members:
    let name = key_to_string(member_key)
    if should_skip_origin_member(name):
      continue
    let path = join_origin_path(prefix, name)

    case target.kind:
    of VkNamespace:
      if member_value.kind == VkNamespace and member_value.ref.ns == target.ref.ns:
        return (true, make_origin(SrkNamespace, module_path, path))
    of VkClass:
      if member_value.kind == VkClass and member_value.ref.class == target.ref.class:
        return (true, make_origin(SrkClass, module_path, path))
    of VkFunction:
      if member_value.kind == VkFunction and member_value.ref.fn == target.ref.fn:
        return (true, make_origin(SrkFunction, module_path, path))
    of VkNativeFn, VkNativeMacro:
      if member_value.raw == target.raw:
        return (true, make_origin(SrkFunction, module_path, path))
    of VkEnum:
      if member_value.kind == VkEnum and member_value.ref.enum_def == target.ref.enum_def:
        return (true, make_origin(SrkEnum, module_path, path))
    of VkEnumMember:
      if member_value.kind == VkEnum:
        for member_name, enum_member in member_value.ref.enum_def.members:
          if enum_member == target.ref.enum_member:
            return (true, make_origin(SrkEnum, module_path, join_origin_path(path, member_name)))
    of VkTupleDef:
      if member_value.kind == VkTupleDef and member_value.ref.tuple_def == target.ref.tuple_def:
        return (true, make_origin(SrkTuple, module_path, path))
    of VkInstance:
      if member_value.raw == target.raw:
        return (true, make_origin(SrkInstance, module_path, path))
    else:
      discard

    if member_value.kind == VkNamespace:
      let nested = find_live_origin_in_namespace(member_value.ref.ns, target, module_path, path, seen)
      if nested.found:
        return nested
    elif member_value.kind == VkClass and member_value.ref.class != nil and member_value.ref.class.ns != nil:
      let nested = find_live_origin_in_namespace(member_value.ref.class.ns, target, module_path, path, seen)
      if nested.found:
        return nested

  (false, SerializationOrigin())

proc find_live_origin(target: Value): tuple[found: bool, origin: SerializationOrigin] {.gcsafe.} =
  # Last-resort canonicalization for already-live values.
  # This is intentionally only attempted after direct object fields and the
  # per-thread origin registry miss, because it walks reachable namespaces.
  var seen: HashSet[pointer]
  if VM != nil and VM.frame != nil and VM.frame.ns != nil:
    let live = find_live_origin_in_namespace(VM.frame.ns, target,
      namespace_runtime_module_path(VM.frame.ns), "", seen)
    if live.found:
      return live
  if App != NIL and App.kind == VkApplication:
    if App.app.global_ns.kind == VkNamespace:
      let global_live = find_live_origin_in_namespace(App.app.global_ns.ref.ns, target, "", "", seen)
      if global_live.found:
        return global_live
    if App.app.gene_ns.kind == VkNamespace:
      let gene_live = find_live_origin_in_namespace(App.app.gene_ns.ref.ns, target, "", "gene", seen)
      if gene_live.found:
        return gene_live
    if App.app.genex_ns.kind == VkNamespace:
      let genex_live = find_live_origin_in_namespace(App.app.genex_ns.ref.ns, target, "", "genex", seen)
      if genex_live.found:
        return genex_live
  (false, SerializationOrigin())

proc lookup_value_origin(value: Value): tuple[found: bool, origin: SerializationOrigin] {.gcsafe.} =
  case value.kind:
  of VkNamespace:
    if value.ref.ns != nil and value.ref.ns.internal_path.len > 0:
      return (true, make_origin(SrkNamespace, value.ref.ns.module_path, value.ref.ns.internal_path))
  of VkClass:
    return lookup_class_origin(value.ref.class)
  of VkFunction:
    if value.ref.fn != nil and value.ref.fn.internal_path.len > 0:
      return (true, make_origin(SrkFunction, value.ref.fn.module_path, value.ref.fn.internal_path))
    if value.ref.fn != nil and value.ref.fn.name.len > 0:
      if value.ref.fn.ns != nil and value.ref.fn.ns.module_path.len > 0:
        value.ref.fn.module_path = value.ref.fn.ns.module_path
        value.ref.fn.internal_path = join_origin_path(value.ref.fn.ns.internal_path, value.ref.fn.name)
        return (true, make_origin(SrkFunction, value.ref.fn.module_path, value.ref.fn.internal_path))
      if value.ref.fn.ns != nil:
        let direct = simple_member_origin(value.ref.fn.ns, value.ref.fn.name, value, SrkFunction)
        if direct.found:
          value.ref.fn.module_path = direct.origin.module_path
          value.ref.fn.internal_path = direct.origin.internal_path
          return direct
      if VM != nil and VM.frame != nil and VM.frame.ns != nil:
        let current = simple_member_origin(VM.frame.ns, value.ref.fn.name, value, SrkFunction)
        if current.found:
          value.ref.fn.module_path = current.origin.module_path
          value.ref.fn.internal_path = current.origin.internal_path
          return current
  of VkEnum:
    if value.ref.enum_def != nil and value.ref.enum_def.internal_path.len > 0:
      return (true, make_origin(SrkEnum, value.ref.enum_def.module_path, value.ref.enum_def.internal_path))
  of VkEnumMember:
    if value.ref.enum_member != nil and value.ref.enum_member.internal_path.len > 0:
      return (true, make_origin(SrkEnum, value.ref.enum_member.module_path, value.ref.enum_member.internal_path))
  of VkTupleDef:
    if value.ref.tuple_def != nil and value.ref.tuple_def.internal_path.len > 0:
      return (true, make_origin(SrkTuple, value.ref.tuple_def.module_path, value.ref.tuple_def.internal_path))
    if value.ref.tuple_def != nil and value.ref.tuple_def.name.len > 0:
      if VM != nil and VM.frame != nil and VM.frame.ns != nil:
        let current = simple_member_origin(VM.frame.ns, value.ref.tuple_def.name, value, SrkTuple)
        if current.found:
          value.ref.tuple_def.module_path = current.origin.module_path
          value.ref.tuple_def.internal_path = current.origin.internal_path
          return current
  of VkInstance:
    let data = instance_ptr(value)
    if data != nil and data.internal_path.len > 0:
      return (true, make_origin(SrkInstance, data.module_path, data.internal_path))
  else:
    discard

  ensure_value_origin_registry()
  if value_origin_registry.hasKey(value.raw):
    return (true, value_origin_registry[value.raw])

  let live = find_live_origin(value)
  if live.found:
    assign_value_origin(value, live.origin)
    return live
  (false, SerializationOrigin())

proc not_serializable(value: Value, detail = "") {.noreturn, gcsafe.} =
  var msg = "Value of kind " & $value.kind & " is not serializable"
  if detail.len > 0:
    msg &= ": " & detail
  not_allowed(msg)

proc typed_ref_for_value(value: Value): Value {.gcsafe.} =
  let (found, origin) = lookup_value_origin(value)
  if not found or origin.internal_path.len == 0:
    not_serializable(value, "no canonical module/path origin")
  new_typed_ref(origin.kind, origin.internal_path, origin.module_path)

proc serialized_gene_type_name(value: Value): string {.gcsafe.} =
  if value.kind != VkGene:
    return ""
  let typ = value.gene.type
  case typ.kind:
  of VkSymbol:
    typ.str
  of VkComplexSymbol:
    typ.ref.csymbol.join("/")
  else:
    ""

proc require_enum_value_member(variant: Value, context: string): EnumMember {.gcsafe.} =
  if variant.kind != VkEnumMember or variant.ref.enum_member == nil:
    not_allowed(context & " requires a resolved VkEnumMember, got " & $variant.kind)
  variant.ref.enum_member

proc validate_enum_payload_types(member: EnumMember, payload: var seq[Value], context: string) {.gcsafe.} =
  let qualified_name = qualified_enum_member_name(member)
  let expected = enum_payload_arity(member)
  if member.field_type_ids.len != expected:
    not_allowed(context & " " & qualified_name & " has malformed field type metadata: expected " &
                $expected & " field type id(s), got " & $member.field_type_ids.len)

  for i in 0..<expected:
    let type_id = member.field_type_ids[i]
    if type_id == NO_TYPE_ID:
      continue
    if type_id < 0 or type_id.int >= member.field_type_descs.len:
      not_allowed(context & " " & qualified_name &
                  " has malformed field type descriptor metadata for " &
                  enum_payload_slot_label(member, i) & ": TypeId " & $type_id & " is unavailable")

    var item = payload[i]
    if item == NIL:
      continue
    var warning = ""
    {.cast(gcsafe).}:
      warning = validate_or_coerce_type(item, type_id, member.field_type_descs,
        "field " & qualified_name & (if enum_payload_shape(member) == EpsNamed and i < member.fields.len: "." & member.fields[i] else: "[" & $i & "]"))
    payload[i] = item
    emit_type_warning(warning)

proc qualified_tuple_name(tuple_def: TupleDef): string {.gcsafe.} =
  if tuple_def == nil:
    return "<nil>"
  if tuple_def.module_path.len > 0:
    return tuple_def.module_path & ":" & tuple_def.name
  tuple_def.name

proc tuple_payload_type_label(tuple_def: TupleDef, index: int): string {.gcsafe.} =
  if tuple_def != nil and tuple_payload_shape(tuple_def) == EpsNamed and
      index >= 0 and index < tuple_def.fields.len:
    return tuple_def.name & "." & tuple_def.fields[index]
  (if tuple_def == nil: "<tuple>" else: tuple_def.name) & "[" & $index & "]"

proc require_tuple_def_value(tuple_def_value: Value, context: string): TupleDef {.gcsafe.} =
  if tuple_def_value.kind != VkTupleDef or tuple_def_value.ref == nil or tuple_def_value.ref.tuple_def == nil:
    not_allowed(context & " requires a resolved VkTupleDef, got " & $tuple_def_value.kind)
  result = tuple_def_value.ref.tuple_def
  try:
    validate_tuple_metadata(result, context)
  except CatchableError as e:
    not_allowed(context & " " & qualified_tuple_name(result) & " metadata validation failed: " & e.msg)

proc validate_tuple_payload_arity_for_serdes(tuple_def: TupleDef, actual: int, context: string) {.gcsafe.} =
  let expected = tuple_payload_arity(tuple_def)
  if actual != expected:
    let field_names = if expected > 0 and tuple_payload_shape(tuple_def) == EpsNamed: " (" & tuple_def.fields.join(", ") & ")" else: ""
    not_allowed(context & " " & qualified_tuple_name(tuple_def) &
                " expects " & $expected & " payload value(s)" & field_names &
                ", got " & $actual)

proc validate_tuple_payload_types(tuple_def: TupleDef, payload: var seq[Value], context: string) {.gcsafe.} =
  let expected = tuple_payload_arity(tuple_def)
  if tuple_def.field_type_ids.len != expected:
    not_allowed(context & " " & qualified_tuple_name(tuple_def) & " has malformed field type metadata: expected " &
                $expected & " field type id(s), got " & $tuple_def.field_type_ids.len)

  for i in 0..<expected:
    let type_id = tuple_def.field_type_ids[i]
    if type_id == NO_TYPE_ID:
      continue
    let label = tuple_payload_type_label(tuple_def, i)
    if type_id < 0 or type_id.int >= tuple_def.field_type_descs.len:
      not_allowed(context & " " & qualified_tuple_name(tuple_def) &
                  " has malformed field type descriptor metadata for " & label &
                  ": TypeId " & $type_id & " is unavailable")

    var item = payload[i]
    if item == NIL:
      continue
    var warning = ""
    {.cast(gcsafe).}:
      warning = validate_or_coerce_type(item, type_id, tuple_def.field_type_descs,
        "field " & label)
    payload[i] = item
    emit_type_warning(warning)

proc typed_ref_for_class(self: Class): Value {.gcsafe.} =
  let (found, origin) = lookup_class_origin(self)
  if not found or origin.internal_path.len == 0:
    not_allowed("Class '" & (if self == nil: "<nil>" else: self.name) &
      "' is not serializable: no canonical module/path origin")
  new_typed_ref(SrkClass, origin.internal_path, origin.module_path)

proc class_to_value(self: Class): Value {.inline, gcsafe.} =
  let r = new_ref(VkClass)
  r.class = self
  r.to_ref_value()

proc resolve_from_namespace(ns: Namespace, path: string): Value {.gcsafe.} =
  if ns == nil or path.len == 0:
    return NIL
  let parts = path.split("/")
  if parts.len == 0:
    return NIL

  var current_ns = ns
  var i = 0
  while i < parts.len:
    let part = parts[i]
    if part.len == 0:
      i.inc()
      continue
    let key = part.to_key()
    if current_ns == nil or not current_ns.members.hasKey(key):
      return NIL
    let current = current_ns.members[key]
    if i == parts.len - 1:
      return current
    case current.kind:
    of VkNamespace:
      current_ns = current.ref.ns
    of VkClass:
      if current.ref.class == nil:
        return NIL
      if i == parts.len - 2:
        let member = current.ref.class.get_member(parts[i + 1].to_key())
        if member != NIL:
          return member
      if current.ref.class.ns == nil:
        return NIL
      current_ns = current.ref.class.ns
    of VkEnum:
      if i == parts.len - 2 and current.ref.enum_def.members.hasKey(parts[i + 1]):
        return current.ref.enum_def.members[parts[i + 1]].to_value()
      return NIL
    else:
      return NIL
    i.inc()
  NIL

proc current_module_namespace(module_path: string): Namespace {.gcsafe.} =
  if module_path.len == 0 or VM == nil or VM.frame == nil or VM.frame.ns == nil:
    return nil
  let module_name = VM.frame.ns.members.getOrDefault("__module_name__".to_key(), NIL)
  if module_name.kind in {VkString, VkSymbol} and module_name.str == module_path:
    return VM.frame.ns
  nil

proc ensure_module_namespace(module_path: string): Namespace {.gcsafe.} =
  if module_path.len == 0:
    return nil
  let current_ns = current_module_namespace(module_path)
  if current_ns != nil:
    return current_ns
  if not serdes_module_loader_hook.isNil:
    {.cast(gcsafe).}:
      return serdes_module_loader_hook(module_path)
  nil

proc resolve_named_reference(module_path, path: string): Value {.gcsafe.} =
  if path.len == 0:
    not_allowed("Serialization reference is missing ^path")

  if module_path.len > 0:
    let module_ns = ensure_module_namespace(module_path)
    if module_ns == nil:
      not_allowed("Module '" & module_path & "' is not available for deserialization")
    let resolved = resolve_from_namespace(module_ns, path)
    if resolved != NIL:
      return resolved
    not_allowed("Serialized reference not found in module '" & module_path & "': " & path)

  result = path_to_value(path)
  if result == NIL:
    not_allowed("Serialized reference not found: " & path)

proc parse_typed_ref(gene: ptr Gene): tuple[module_path: string, path: string] {.gcsafe.} =
  let path_value = gene.props.getOrDefault("path".to_key(), NIL)
  if path_value.kind notin {VkString, VkSymbol}:
    not_allowed("Serialized reference expects string/symbol ^path")
  result.path = path_value.str

  let module_value = gene.props.getOrDefault("module".to_key(), NIL)
  if module_value != NIL:
    if module_value.kind notin {VkString, VkSymbol}:
      not_allowed("Serialized reference expects string/symbol ^module")
    result.module_path = module_value.str

proc resolve_typed_ref(gene: ptr Gene): Value {.gcsafe.} =
  let parsed = parse_typed_ref(gene)
  resolve_named_reference(parsed.module_path, parsed.path)

proc resolve_tuple_ref(gene: ptr Gene, context: string): Value {.gcsafe.} =
  var parsed: tuple[module_path: string, path: string]
  try:
    parsed = parse_typed_ref(gene)
  except CatchableError as e:
    not_allowed(context & " TupleRef parse failed: " & e.msg)

  try:
    result = resolve_named_reference(parsed.module_path, parsed.path)
  except CatchableError as e:
    not_allowed(context & " TupleRef resolution failed for module '" & parsed.module_path &
                "' path '" & parsed.path & "': " & e.msg)

  discard require_tuple_def_value(result, context & " TupleRef")

proc find_serialize_hook(cls: Class): Value =
  if cls == nil:
    return NIL
  for name in [".serialize", "serialize"]:
    let meth = cls.get_method(name)
    if meth != nil:
      return meth.callable
  return NIL

proc find_deserialize_hook(cls: Class): Value =
  if cls == nil:
    return NIL
  for name in [".deserialize", "deserialize"]:
    let meth = cls.get_method(name)
    if meth != nil:
      return meth.callable
  return NIL

proc class_display_name(cls: Class): string {.inline.} =
  if cls == nil or cls.name.len == 0:
    "<nil>"
  else:
    cls.name

proc require_custom_serdes_hooks(cls: Class): tuple[serialize_hook: Value, deserialize_hook: Value] =
  result.serialize_hook = find_serialize_hook(cls)
  if result.serialize_hook == NIL:
    not_allowed("Custom serialization requires class '" & class_display_name(cls) & "' to define serialize")

  result.deserialize_hook = find_deserialize_hook(cls)
  if result.deserialize_hook == NIL:
    not_allowed("Custom serialization requires class '" & class_display_name(cls) & "' to define deserialize")

proc invoke_serialize_hook(hook: Value, value: Value): Value {.gcsafe.} =
  case hook.kind:
  of VkFunction, VkBlock:
    if VM == nil:
      not_allowed("Serialization hook requires an active VM")
    {.cast(gcsafe).}:
      return vm_exec_callable(VM, hook, @[value])
  of VkNativeFn:
    return call_native_fn(hook.ref.native_fn, VM, [value])
  else:
    not_allowed("Serialize hook must be a function or native function")

proc invoke_deserialize_hook(cls: Class, state: Value): tuple[handled: bool, value: Value] {.gcsafe.} =
  let hook = find_deserialize_hook(cls)
  if hook == NIL:
    return (false, NIL)

  let class_val = class_to_value(cls)
  case hook.kind:
  of VkFunction, VkBlock:
    if VM == nil:
      not_allowed("Deserialization hook requires an active VM")
    {.cast(gcsafe).}:
      return (true, vm_exec_callable(VM, hook, @[class_val, state]))
  of VkNativeFn:
    return (true, call_native_fn(hook.ref.native_fn, VM, [class_val, state]))
  else:
    not_allowed("Deserialize hook must be a function or native function")

proc has_direct_value_origin(value: Value): tuple[has_origin: bool, origin: SerializationOrigin] {.gcsafe.} =
  case value.kind:
  of VkNamespace:
    if value.ref.ns != nil and value.ref.ns.internal_path.len > 0:
      return (true, make_origin(SrkNamespace, value.ref.ns.module_path, value.ref.ns.internal_path))
  of VkClass:
    if value.ref.class != nil and value.ref.class.internal_path.len > 0:
      return (true, make_origin(SrkClass, value.ref.class.module_path, value.ref.class.internal_path))
  of VkFunction:
    if value.ref.fn != nil and value.ref.fn.internal_path.len > 0:
      return (true, make_origin(SrkFunction, value.ref.fn.module_path, value.ref.fn.internal_path))
  of VkEnum:
    if value.ref.enum_def != nil and value.ref.enum_def.internal_path.len > 0:
      return (true, make_origin(SrkEnum, value.ref.enum_def.module_path, value.ref.enum_def.internal_path))
  of VkEnumMember:
    if value.ref.enum_member != nil and value.ref.enum_member.internal_path.len > 0:
      return (true, make_origin(SrkEnum, value.ref.enum_member.module_path, value.ref.enum_member.internal_path))
  of VkTupleDef:
    if value.ref.tuple_def != nil and value.ref.tuple_def.internal_path.len > 0:
      return (true, make_origin(SrkTuple, value.ref.tuple_def.module_path, value.ref.tuple_def.internal_path))
  of VkInstance:
    let data = instance_ptr(value)
    if data != nil and data.internal_path.len > 0:
      return (true, make_origin(SrkInstance, data.module_path, data.internal_path))
  else:
    discard
  (false, SerializationOrigin())

proc tag_value_origin(value: Value, module_path, internal_path: string) {.gcsafe.} =
  if value == NIL or internal_path.len == 0:
    return
  let existing = has_direct_value_origin(value)
  if existing.has_origin:
    register_value_origin(value, existing.origin)
    return
  let kind = case value.kind:
    of VkNamespace: SrkNamespace
    of VkClass: SrkClass
    of VkFunction, VkNativeFn, VkNativeMacro: SrkFunction
    of VkEnum, VkEnumMember: SrkEnum
    of VkTupleDef: SrkTuple
    of VkInstance: SrkInstance
    else: return
  assign_value_origin(value, make_origin(kind, module_path, internal_path))

proc tag_namespace_serialization_origins*(ns: Namespace, module_path: string, prefix = "") =
  if ns == nil:
    return

  var seen: HashSet[pointer]
  let export_root = ns

  proc walk(current: Namespace, current_prefix: string, tag_self: bool) =
    if current == nil:
      return
    let ns_key = cast[pointer](current)
    if seen.contains(ns_key):
      return
    seen.incl(ns_key)

    if tag_self and current_prefix.len > 0:
      tag_value_origin(current.to_value(), module_path, current_prefix)

    for key, value in current.members:
      let name = key_to_string(key)
      if should_skip_origin_member(name):
        continue
      let path = join_origin_path(current_prefix, name)
      if not namespace_path_is_exported(export_root, path):
        continue
      tag_value_origin(value, module_path, path)
      if value.kind == VkNamespace:
        walk(value.ref.ns, path, true)
      elif value.kind == VkClass and value.ref.class != nil and value.ref.class.ns != nil:
        walk(value.ref.class.ns, path, false)

  walk(ns, prefix, prefix.len > 0)

proc tag_stdlib_serialization_origins*() =
  if App == NIL or App.kind != VkApplication:
    return
  if App.app.global_ns.kind == VkNamespace:
    tag_namespace_serialization_origins(App.app.global_ns.ref.ns, "", "")
  if App.app.gene_ns.kind == VkNamespace:
    tag_namespace_serialization_origins(App.app.gene_ns.ref.ns, "", "gene")
  if App.app.genex_ns.kind == VkNamespace:
    tag_namespace_serialization_origins(App.app.genex_ns.ref.ns, "", "genex")

# Serialize a value into a form that can be stored and later deserialized
proc serialize*(value: Value): Serialization =
  result = Serialization(
    references: initTable[string, Value](),
  )
  result.data = result.serialize(value)

proc serialize*(self: Serialization, value: Value): Value =
  let value = materialize_custom_value(value)
  case value.kind:
  of VkNil, VkVoid, VkBool, VkInt, VkFloat, VkChar:
    return value
  of VkString, VkSymbol:
    return value
  of VkArray:
    var arr_val = new_array_value(@[], frozen = array_is_frozen(value))
    for item in array_data(value):
      array_data(arr_val).add(self.serialize(item))
    return arr_val
  of VkMap:
    let map = new_map_value(map_is_frozen(value))
    map_data(map) = initTable[Key, Value]()
    for k, v in map_data(value):
      map_data(map)[k] = self.serialize(v)
    return map
  of VkGene:
    let gene = new_gene(self.serialize(value.gene.type), frozen = gene_is_frozen(value))
    for k, v in value.gene.props:
      gene.props[k] = self.serialize(v)
    for child in value.gene.children:
      gene.children.add(self.serialize(child))
    return gene.to_gene_value()
  of VkNamespace, VkClass, VkFunction, VkNativeFn, VkNativeMacro, VkEnum, VkEnumMember, VkTupleDef:
    return typed_ref_for_value(value)
  of VkEnumValue:
    let variant = value.ref.ev_variant
    let member = require_enum_value_member(variant, "EnumValue serialization")
    validate_enum_payload_arity(member, value.ref.ev_data.len, "EnumValue")
    var payload = value.ref.ev_data
    validate_enum_payload_types(member, payload, "EnumValue")
    let payloads = new_array_value(@[])
    for item in payload:
      array_data(payloads).add(self.serialize(item))
    return new_serialized_enum_value(typed_ref_for_value(variant), payloads)
  of VkTupleValue:
    if value.ref == nil:
      not_allowed("TupleValue serialization requires tuple value data")
    let tuple_def_value = value.ref.tv_def
    let tuple_def = require_tuple_def_value(tuple_def_value, "TupleValue serialization")
    validate_tuple_payload_arity_for_serdes(tuple_def, value.ref.tv_data.len, "TupleValue")
    var payload = value.ref.tv_data
    validate_tuple_payload_types(tuple_def, payload, "TupleValue")
    let payloads = new_array_value(@[])
    for item in payload:
      array_data(payloads).add(self.serialize(item))
    return new_serialized_tuple_value(typed_ref_for_value(tuple_def_value), payloads)
  of VkInstance:
    let (named, _) = lookup_value_origin(value)
    if named:
      return typed_ref_for_value(value)
    not_serializable(value, "anonymous instances cannot be serialized")
  of VkCustom:
    let cls = value.ref.custom_class
    let hooks = require_custom_serdes_hooks(cls)
    let payload = invoke_serialize_hook(hooks.serialize_hook, value)
    return new_serialized_instance(typed_ref_for_class(cls), self.serialize(payload))
  else:
    not_serializable(value)

# Fast literal checker: primitives, strings/symbols, arrays/maps/genes with literal children
proc is_literal_value*(v: Value): bool {.inline, gcsafe.} =
  var stack: seq[Value] = @[v]
  var seen_arrays: HashSet[ptr ArrayObj]
  var seen_maps: HashSet[ptr MapObj]
  var seen_genes: HashSet[ptr Gene]

  while stack.len > 0:
    let cur = stack.pop()
    case cur.kind:
    of VkVoid, VkNil, VkPlaceholder, VkBool, VkInt, VkFloat, VkChar,
       VkString, VkSymbol, VkComplexSymbol, VkByte, VkBytes, VkBin, VkBin64,
       VkDate, VkDateTime:
      continue
    of VkArray:
      let r = array_ptr(cur)
      if seen_arrays.contains(r): continue
      seen_arrays.incl(r)
      for item in r.arr: stack.add(item)
    of VkMap:
      let r = map_ptr(cur)
      if seen_maps.contains(r): continue
      seen_maps.incl(r)
      for _, val in r.map: stack.add(val)
    of VkGene:
      let gptr = cur.gene
      if seen_genes.contains(gptr): continue
      seen_genes.incl(gptr)
      if gptr.type != NIL:
        stack.add(gptr.type)
      for _, val in gptr.props: stack.add(val)
      for child in gptr.children: stack.add(child)
    else:
      return false
  true

# Serialize only literal values; reject unsupported kinds early.
#
# Thread messaging only supports "literal" values - primitives and containers
# with literal contents. This constraint exists because:
# 1. Functions/closures may reference thread-local state
# 2. Class/instance objects have complex object graphs
# 3. Thread/Future handles are thread-specific
#
# Allowed types: nil, bool, int, float, char, string, symbol, byte, bytes,
#                date, datetime, arrays/maps/genes with literal contents
# Not allowed: functions, classes, instances, threads, futures, namespaces, etc.
proc serialize_literal*(value: Value): Serialization {.gcsafe.} =
  if not is_literal_value(value):
    not_allowed("Thread message payload must be a literal value. Got " & $value.kind &
                ". Allowed: primitives (nil/bool/int/float/char/string/symbol/byte/bytes/date/datetime) " &
                "and containers (array/map/gene) with literal contents. " &
                "Not allowed: functions, classes, instances, threads, futures.")
  serialize(value)

proc deserialize_literal*(s: string): Value {.gcsafe.} =
  deserialize(s)

proc to_path*(self: Class): string =
  let (found, origin) = lookup_class_origin(self)
  if not found:
    not_allowed("Class '" & (if self == nil: "<nil>" else: self.name) & "' has no canonical serialization path")
  origin.internal_path

# A path looks like
# Class C => "pkgP:modM:nsN/C" or just "nsN/C" or "C"
proc to_path*(self: Value): string =
  let (found, origin) = lookup_value_origin(self)
  if not found:
    not_allowed("Value of kind " & $self.kind & " has no canonical serialization path")
  origin.internal_path

proc path_to_value*(path: string): Value =
  if App != NIL and App.kind == VkApplication:
    if path == "gene":
      return App.app.gene_ns
    if path == "genex":
      return App.app.genex_ns
    if path.startsWith("gene/") and App.app.gene_ns.kind == VkNamespace:
      let resolved = resolve_from_namespace(App.app.gene_ns.ref.ns, path["gene/".len .. ^1])
      if resolved != NIL:
        return resolved
    if path.startsWith("genex/") and App.app.genex_ns.kind == VkNamespace:
      let resolved = resolve_from_namespace(App.app.genex_ns.ref.ns, path["genex/".len .. ^1])
      if resolved != NIL:
        return resolved

  if VM != nil and VM.frame != nil and VM.frame.ns != nil:
    let resolved = resolve_from_namespace(VM.frame.ns, path)
    if resolved != NIL:
      return resolved

  if App != NIL and App.kind == VkApplication and App.app.global_ns.kind == VkNamespace:
    let resolved = resolve_from_namespace(App.app.global_ns.ref.ns, path)
    if resolved != NIL:
      return resolved

  not_allowed("path_to_value: not found: " & path)

proc value_to_gene_str*(self: Value): string

proc key_to_string(k: Key): string {.inline, gcsafe.} =
  let symbol_value = cast[Value](k)
  let symbol_index = cast[uint64](symbol_value) and PAYLOAD_MASK
  get_symbol(symbol_index.int)

proc is_tree_structural(value: Value): bool {.inline.} =
  value.kind in {VkMap, VkArray, VkGene}

proc split_tree_selector_path(path: string): seq[string] {.gcsafe.} =
  if '\\' notin path:
    return path.split('/')

  result = @[]
  var part = ""
  var i = 0
  while i < path.len:
    if path[i] == '\\' and i + 1 < path.len and path[i + 1] == '/':
      part.add('/')
      i += 2
    elif path[i] == '/':
      result.add(part)
      part = ""
      inc(i)
    else:
      part.add(path[i])
      inc(i)
  result.add(part)

proc encode_path_segment(segment: string): string =
  encodeUrl(segment, usePlus = false)

proc decode_path_segment(segment: string): string =
  decodeUrl(segment, decodePlus = false)

proc tree_path_key(segments: openArray[string]): string {.gcsafe.} =
  if segments.len == 0:
    return "/"

  var encoded: seq[string] = @[]
  for segment in segments:
    encoded.add(encode_path_segment(segment))
  encoded.join("/")

proc tree_path_display(segments: openArray[string]): string =
  if segments.len == 0:
    return "/"
  "/" & segments.join("/")

proc has_lazy_requests(options: LazyTreeReadOptions): bool {.inline, gcsafe.} =
  options.enabled and options.lazy_nodes.len > 0

proc parse_lazy_selector(selector: Value): seq[string] {.gcsafe.} =
  var parts: seq[string]
  case selector.kind
  of VkComplexSymbol:
    parts = selector.ref.csymbol
  of VkSelector:
    parts = @[""]
    for segment in selector.ref.selector_path:
      case segment.kind
      of VkString, VkSymbol:
        parts.add(segment.str)
      of VkInt:
        parts.add($segment.to_int())
      else:
        not_allowed("read_tree ^lazy selectors only support string, symbol, and integer path segments")
  of VkString, VkSymbol:
    parts = split_tree_selector_path(selector.str)
  else:
    not_allowed("read_tree ^lazy entries must be selectors, strings, or symbols")

  if parts.len > 0 and parts[0] == "self":
    parts[0] = ""

  if parts.len == 0 or parts[0] != "":
    not_allowed("read_tree ^lazy entries must be absolute node selectors")

  if parts.len == 1:
    return @[]
  parts[1 .. ^1]

proc build_tree_read_options(lazy_value: Value): LazyTreeReadOptions {.gcsafe.} =
  result.lazy_nodes = initHashSet[string]()
  if lazy_value.kind == VkNil:
    return
  if lazy_value.kind != VkArray:
    not_allowed("read_tree ^lazy expects an array")

  result.enabled = true
  for selector in array_data(lazy_value):
    let segments = parse_lazy_selector(selector)
    result.lazy_nodes.incl(tree_path_key(segments))

proc materialize_lazy_tree_data(data: CustomValue): Value {.gcsafe.}

proc make_lazy_tree_value(path: string, source_kind: LazyTreeSourceKind, node_segments: seq[string], options: LazyTreeReadOptions): Value {.gcsafe.} =
  if lazy_tree_value_class.is_nil:
    not_allowed("Lazy tree class is not initialized")
  let data = LazyTreeValueData(
    path: path,
    source_kind: source_kind,
    node_segments: node_segments,
    options: options,
    materialized: NIL,
    materialized_loaded: false,
  )
  data.materialize_hook = materialize_lazy_tree_data
  new_custom_value(lazy_tree_value_class, data)

proc materialize_lazy_tree_value*(value: Value): Value {.gcsafe.} =
  if not is_lazy_tree_value(value):
    return value
  let data = LazyTreeValueData(value.ref.custom_data)
  if data.materialized_loaded:
    return data.materialized
  let materialized = data.materialize_hook(data)
  if not data.materialized_loaded:
    data.materialized = materialized
    data.materialized_loaded = true
  data.materialized

proc materialize_custom_value(value: Value): Value {.inline, gcsafe.} =
  if has_custom_materializer(value):
    return materialize_custom(value)
  value

proc materialize_custom_deep*(value: Value): Value {.gcsafe.} =
  let current = materialize_custom_value(value)
  case current.kind
  of VkArray:
    result = new_array_value(@[], frozen = array_is_frozen(current))
    for item in array_data(current):
      array_data(result).add(materialize_custom_deep(item))
  of VkMap:
    result = new_map_value(map_is_frozen(current))
    for k, v in map_data(current):
      map_data(result)[k] = materialize_custom_deep(v)
  of VkGene:
    let gene = new_gene(materialize_custom_deep(current.gene.type), frozen = gene_is_frozen(current))
    for k, v in current.gene.props:
      gene.props[k] = materialize_custom_deep(v)
    for child in current.gene.children:
      gene.children.add(materialize_custom_deep(child))
    result = gene.to_gene_value()
  else:
    result = current

proc materialize_lazy_tree_deep*(value: Value): Value {.gcsafe.} =
  materialize_custom_deep(value)

proc payload_to_serialized_text(payload: Value): string =
  "(gene/serialization " & value_to_gene_str(payload) & ")"

proc value_to_serialized_text(value: Value): string =
  payload_to_serialized_text(serialize(value).data)

proc tree_serialized_hash(value: Value): Hash

proc mix_tree_hash(result: var Hash, marker: string) {.inline.} =
  result = result !& hash(marker)

proc tree_serialized_hash(value: Value): Hash =
  let value = materialize_custom_value(value)
  var result_hash: Hash = 0
  case value.kind:
  of VkNil:
    result_hash.mix_tree_hash("nil")
  of VkBool:
    result_hash.mix_tree_hash(if value == TRUE: "true" else: "false")
  of VkInt:
    result_hash.mix_tree_hash("int")
    result_hash = result_hash !& hash(value.to_int())
  of VkFloat:
    result_hash.mix_tree_hash("float")
    result_hash = result_hash !& hash(value.to_float())
  of VkChar:
    result_hash.mix_tree_hash("char")
    result_hash = result_hash !& hash((value.raw and 0xFF).int)
  of VkString:
    result_hash.mix_tree_hash("string")
    result_hash = result_hash !& hash(value.str)
  of VkSymbol:
    result_hash.mix_tree_hash("symbol")
    result_hash = result_hash !& hash(value.str)
  of VkArray:
    result_hash.mix_tree_hash("array")
    for item in array_data(value):
      result_hash = result_hash !& tree_serialized_hash(item)
  of VkMap:
    result_hash.mix_tree_hash("map")
    for k, v in map_data(value):
      result_hash = result_hash !& hash(key_to_string(k))
      result_hash = result_hash !& tree_serialized_hash(v)
  of VkGene:
    result_hash.mix_tree_hash("gene")
    result_hash = result_hash !& tree_serialized_hash(value.gene.type)
    for k, v in value.gene.props:
      result_hash = result_hash !& hash(key_to_string(k))
      result_hash = result_hash !& tree_serialized_hash(v)
    for child in value.gene.children:
      result_hash = result_hash !& tree_serialized_hash(child)
  of VkNamespace, VkClass, VkFunction, VkNativeFn, VkNativeMacro, VkEnum, VkEnumMember, VkTupleDef:
    let (_, origin) = lookup_value_origin(value)
    let typed_ref = typed_ref_for_value(value)
    result_hash.mix_tree_hash(ref_kind_name(origin.kind))
    result_hash = result_hash !& hash(value_to_gene_str(typed_ref))
  of VkEnumValue:
    let variant = value.ref.ev_variant
    let member = require_enum_value_member(variant, "EnumValue tree hash")
    validate_enum_payload_arity(member, value.ref.ev_data.len, "EnumValue")
    let typed_ref = typed_ref_for_value(variant)
    result_hash.mix_tree_hash("EnumValue")
    result_hash = result_hash !& hash(value_to_gene_str(typed_ref))
    for item in value.ref.ev_data:
      result_hash = result_hash !& tree_serialized_hash(item)
  of VkTupleValue:
    if value.ref == nil:
      not_allowed("TupleValue tree hash requires tuple value data")
    let tuple_def_value = value.ref.tv_def
    let tuple_def = require_tuple_def_value(tuple_def_value, "TupleValue tree hash")
    validate_tuple_payload_arity_for_serdes(tuple_def, value.ref.tv_data.len, "TupleValue")
    let typed_ref = typed_ref_for_value(tuple_def_value)
    result_hash.mix_tree_hash("TupleValue")
    result_hash = result_hash !& hash(value_to_gene_str(typed_ref))
    for item in value.ref.tv_data:
      result_hash = result_hash !& tree_serialized_hash(item)
  of VkInstance:
    let (named, _) = lookup_value_origin(value)
    if named:
      let typed_ref = typed_ref_for_value(value)
      result_hash.mix_tree_hash("InstanceRef")
      result_hash = result_hash !& hash(value_to_gene_str(typed_ref))
    else:
      result_hash.mix_tree_hash("Instance")
      result_hash = result_hash !& hash(value_to_gene_str(typed_ref_for_class(value.instance_class)))
      for k, v in value.instance_props:
        result_hash = result_hash !& hash(key_to_string(k))
        result_hash = result_hash !& tree_serialized_hash(v)
  else:
    not_serializable(value)
  !$result_hash

proc add_directory_node(options: var TreeWriteOptions, segments: openArray[string]) =
  options.directory_nodes.incl(tree_path_key(segments))

proc should_write_dir(options: TreeWriteOptions, segments: openArray[string]): bool =
  options.directory_nodes.contains(tree_path_key(segments))

proc parse_tree_selector(selector: Value): seq[string] =
  var parts: seq[string]
  case selector.kind
  of VkComplexSymbol:
    parts = selector.ref.csymbol
  of VkSelector:
    parts = @[""]
    for segment in selector.ref.selector_path:
      case segment.kind
      of VkString, VkSymbol:
        parts.add(segment.str)
      of VkInt:
        parts.add($segment.to_int())
      else:
        not_allowed("write_tree ^separate selectors only support string, symbol, and integer path segments")
  of VkString, VkSymbol:
    parts = split_tree_selector_path(selector.str)
  else:
    not_allowed("write_tree ^separate entries must be selectors, strings, or symbols")

  if parts.len > 0 and parts[0] == "self":
    parts[0] = ""

  if parts.len < 2 or parts[0] != "" or parts[^1] != "*":
    not_allowed("write_tree ^separate entries must be absolute child selectors ending with /*")

  if parts.len == 2:
    return @[]
  parts[1 .. ^2]

proc build_tree_write_options(separate_value: Value): TreeWriteOptions =
  result.directory_nodes = initHashSet[string]()
  if separate_value == NIL:
    return
  if separate_value.kind != VkArray:
    not_allowed("write_tree ^separate expects an array")

  for selector in array_data(separate_value):
    let parent_segments = parse_tree_selector(selector)
    for prefix_len in 0 .. parent_segments.len:
      result.add_directory_node(parent_segments[0 ..< prefix_len])

proc ensure_parent_dir(path: string) =
  let parent = parentDir(path)
  if parent.len > 0 and parent != ".":
    createDir(parent)

proc write_serialized_text_file(path: string, serialized_text: string) =
  ensure_parent_dir(path)
  let temp_path = path & ".tmp"
  if fileExists(temp_path):
    removeFile(temp_path)
  writeFile(temp_path, serialized_text)
  moveFile(temp_path, path)

proc write_serialized_file(path: string, value: Value) =
  write_serialized_text_file(path, value_to_serialized_text(value))

proc filesystem_write_error(target_path, reason, detail: string,
                            option = "", child_path = "", selector = "") {.noreturn, gcsafe.} =
  var message = "gene/serdes/write failed"
  message &= "; reason: " & reason
  message &= "; target: " & (if target_path.len > 0: target_path else: "<missing>")
  if option.len > 0:
    message &= "; option: ^" & option
  if selector.len > 0:
    message &= "; selector: " & selector
  if child_path.len > 0:
    message &= "; child: " & child_path
  if detail.len > 0:
    message &= "; detail: " & detail
  not_allowed(message)

proc is_filesystem_write_error(message: string): bool {.inline, gcsafe.} =
  message.startsWith("gene/serdes/write failed")

proc write_selector_display(segments: openArray[string]): string =
  if segments.len == 0:
    return "/"
  "/" & @segments.join("/")

proc raw_write_selector_label(selector: Value): string =
  case selector.kind
  of VkString, VkSymbol:
    selector.str
  of VkComplexSymbol:
    selector.ref.csymbol.join("/")
  of VkSelector:
    "@(" & selector.ref.selector_pattern & ")"
  else:
    $selector.kind

proc parse_write_selector(selector: Value, target_path: string): WriteSelector {.gcsafe.} =
  var parts: seq[string]
  case selector.kind
  of VkComplexSymbol:
    parts = selector.ref.csymbol
  of VkSelector:
    parts = @[""]
    for segment in selector.ref.selector_path:
      case segment.kind
      of VkString, VkSymbol:
        parts.add(segment.str)
      of VkInt:
        parts.add($segment.to_int())
      else:
        filesystem_write_error(target_path, "malformed selector",
                               "^externalize selector segments must be strings, symbols, or integers; got " & $segment.kind,
                               "externalize", "", raw_write_selector_label(selector))
  of VkString, VkSymbol:
    parts = split_tree_selector_path(selector.str)
  else:
    filesystem_write_error(target_path, "malformed selector",
                           "^externalize entries must be selectors, strings, or symbols; got " & $selector.kind,
                           "externalize", "", raw_write_selector_label(selector))

  if parts.len > 0 and parts[0] == "self":
    parts[0] = ""

  if parts.len == 0 or parts[0] != "":
    filesystem_write_error(target_path, "malformed selector",
                           "^externalize selectors must be absolute child selectors such as /profile",
                           "externalize", "", raw_write_selector_label(selector))
  if parts.len < 2:
    filesystem_write_error(target_path, "malformed selector",
                           "^externalize selectors must target a child value, got root selector",
                           "externalize", "", raw_write_selector_label(selector))

  result.segments = @[]
  for part in parts[1 .. ^1]:
    if part.len == 0:
      filesystem_write_error(target_path, "malformed selector",
                             "^externalize selectors cannot contain empty path segments",
                             "externalize", "", raw_write_selector_label(selector))
    if part in ["*", "**", "@", "@@", "!"]:
      filesystem_write_error(target_path, "malformed selector",
                             "wildcard/old selector forms are unsupported for ^externalize; use exact child selectors",
                             "externalize", "", write_selector_display(result.segments & @[part]))
    result.segments.add(part)
  result.display = write_selector_display(result.segments)

proc write_selector_key(selector: WriteSelector): string {.inline, gcsafe.} =
  tree_path_key(selector.segments)

proc selector_is_strict_prefix(prefix, value: openArray[string]): bool {.gcsafe.} =
  if prefix.len >= value.len:
    return false
  for i in 0..<prefix.len:
    if prefix[i] != value[i]:
      return false
  true

proc add_write_selector(options: var WriteOptions, selector: WriteSelector) {.gcsafe.} =
  let key = write_selector_key(selector)
  if options.selectors_by_key.hasKey(key):
    filesystem_write_error(options.target_path, "duplicate selector",
                           "duplicate ^externalize selector " & selector.display,
                           "externalize", "", selector.display)

  for existing in options.externalize_selectors:
    if selector_is_strict_prefix(existing.segments, selector.segments) or
       selector_is_strict_prefix(selector.segments, existing.segments):
      filesystem_write_error(options.target_path, "conflicting selector",
                             "^externalize selectors cannot select both an ancestor and descendant: " &
                               existing.display & " conflicts with " & selector.display,
                             "externalize", "", selector.display)

  options.externalize_selectors.add(selector)
  options.selectors_by_key[key] = selector

proc target_parent_dir_abs(target_path: string): string {.gcsafe.} =
  let parent = parentDir(target_path)
  let effective_parent = if parent.len == 0 or parent == ".": "." else: parent
  normalizedPath(absolutePath(effective_parent))

proc default_external_dir_rel(target_path: string): string =
  let split = splitFile(target_path)
  let stem = if split.name.len > 0: split.name else: "externalized"
  stem & ".files"

proc resolve_default_external_dir(target_path, parent_dir_abs: string): tuple[relPath: string, absPath: string] {.gcsafe.} =
  result.relPath = default_external_dir_rel(target_path)
  result.absPath = normalizedPath(absolutePath(result.relPath, parent_dir_abs))

proc resolve_external_dir_option(value: Value, target_path, parent_dir_abs: string): tuple[relPath: string, absPath: string] {.gcsafe.} =
  if value.kind != VkString:
    filesystem_write_error(target_path, "unsafe external dir",
                           "^external_dir must be a non-empty relative string, got " & $value.kind,
                           "external_dir")
  let raw = value.str
  if raw.len == 0:
    filesystem_write_error(target_path, "unsafe external dir",
                           "^external_dir must not be empty",
                           "external_dir")
  if raw.isAbsolute:
    filesystem_write_error(target_path, "unsafe external dir",
                           "^external_dir must be relative, got absolute path",
                           "external_dir")

  let parts = raw.split({'/', '\\'})
  for part in parts:
    if part.len == 0 or part == "." or part == "..":
      filesystem_write_error(target_path, "unsafe external dir",
                             "^external_dir must contain only non-traversing relative path segments",
                             "external_dir")

  result.relPath = parts.join($DirSep)
  result.absPath = normalizedPath(absolutePath(result.relPath, parent_dir_abs))
  if result.absPath == parent_dir_abs or not filesystem_is_subpath(parent_dir_abs, result.absPath):
    filesystem_write_error(target_path, "unsafe external dir",
                           "^external_dir resolves outside the parent file directory",
                           "external_dir", result.relPath)

  let target_abs = normalizedPath(absolutePath(target_path))
  if result.absPath == target_abs:
    filesystem_write_error(target_path, "unsafe external dir",
                           "^external_dir collides with the target file path",
                           "external_dir", result.relPath)

proc build_write_options(props: Table[Key, Value], target_path: string): WriteOptions {.gcsafe.} =
  result.selectors_by_key = initTable[string, WriteSelector]()
  result.externalize_selectors = @[]
  result.parent_dir_abs = target_parent_dir_abs(target_path)
  result.target_path = target_path
  let default_dir = resolve_default_external_dir(target_path, result.parent_dir_abs)
  result.external_dir_rel = default_dir.relPath
  result.external_dir_abs = default_dir.absPath
  var saw_external_dir = false

  for key, prop_value in props:
    let option_name = key_to_string(key)
    case option_name
    of "externalize":
      if prop_value.kind != VkArray:
        filesystem_write_error(target_path, "malformed selector",
                               "^externalize expects an array of absolute selectors",
                               "externalize")
      for selector_value in array_data(prop_value):
        result.add_write_selector(parse_write_selector(selector_value, target_path))
    of "external_dir":
      saw_external_dir = true
      let resolved = resolve_external_dir_option(prop_value, target_path, result.parent_dir_abs)
      result.external_dir_rel = resolved.relPath
      result.external_dir_abs = resolved.absPath
    of "separate":
      filesystem_write_error(target_path, "unsupported option",
                             "old ^separate tree-serdes input is not supported; use ^externalize",
                             option_name)
    else:
      filesystem_write_error(target_path, "unsupported option",
                             "unknown property ^" & option_name, option_name)

  if saw_external_dir and result.externalize_selectors.len == 0:
    filesystem_write_error(target_path, "unsupported option",
                           "^external_dir requires at least one ^externalize selector",
                           "external_dir", result.external_dir_rel)

proc selected_write_selector(options: WriteOptions, segments: openArray[string]): tuple[found: bool, selector: WriteSelector] {.gcsafe.} =
  let key = tree_path_key(segments)
  if options.selectors_by_key.hasKey(key):
    return (true, options.selectors_by_key[key])
  (false, WriteSelector())

proc safe_encoded_child_segment(segment: string, options: WriteOptions, selector: WriteSelector): string {.gcsafe.} =
  if segment.len == 0:
    filesystem_write_error(options.target_path, "unsafe child name",
                           "generated child path contains an empty selector segment",
                           "externalize", "", selector.display)
  result = encode_path_segment(segment)
  if result.len == 0 or result == "." or result == ".." or '/' in result or '\\' in result:
    filesystem_write_error(options.target_path, "unsafe child name",
                           "generated child path segment is unsafe: " & result,
                           "externalize", "", selector.display)

proc externalized_child_file(options: WriteOptions, selector: WriteSelector): tuple[relativePath: string, absolutePath: string] {.gcsafe.} =
  result.relativePath = options.external_dir_rel
  for index, segment in selector.segments:
    var encoded = safe_encoded_child_segment(segment, options, selector)
    if index == selector.segments.len - 1:
      encoded &= ".gene"
    result.relativePath = joinPath(result.relativePath, encoded)

  result.absolutePath = normalizedPath(absolutePath(result.relativePath, options.parent_dir_abs))
  if result.absolutePath == options.external_dir_abs or not filesystem_is_subpath(options.external_dir_abs, result.absolutePath):
    filesystem_write_error(options.target_path, "unsafe child name",
                           "generated child path escapes the external directory",
                           "externalize", result.relativePath, selector.display)
  if dirExists(result.absolutePath):
    filesystem_write_error(options.target_path, "child path collision",
                           "generated child file path is already a directory",
                           "externalize", result.relativePath, selector.display)

  var parent = parentDir(result.absolutePath)
  while parent.len > 0 and parent != options.external_dir_abs and filesystem_is_subpath(options.external_dir_abs, parent):
    if fileExists(parent):
      filesystem_write_error(options.target_path, "child path collision",
                             "generated child parent path is already a file",
                             "externalize", result.relativePath, selector.display)
    let next_parent = parentDir(parent)
    if next_parent == parent:
      break
    parent = next_parent

proc externalized_child_directory(options: WriteOptions, selector: WriteSelector): tuple[relativePath: string, absolutePath: string] {.gcsafe.} =
  result.relativePath = options.external_dir_rel
  for segment in selector.segments:
    let encoded = safe_encoded_child_segment(segment, options, selector)
    result.relativePath = joinPath(result.relativePath, encoded)

  result.absolutePath = normalizedPath(absolutePath(result.relativePath, options.parent_dir_abs))
  if result.absolutePath == options.external_dir_abs or not filesystem_is_subpath(options.external_dir_abs, result.absolutePath):
    filesystem_write_error(options.target_path, "unsafe child name",
                           "phase: pre-validation; generated child directory escapes the external directory",
                           "externalize", result.relativePath, selector.display)
  if fileExists(result.absolutePath):
    filesystem_write_error(options.target_path, "child path collision",
                           "phase: pre-validation; generated child directory path is already a file",
                           "externalize", result.relativePath, selector.display)

  var parent = parentDir(result.absolutePath)
  while parent.len > 0 and parent != options.external_dir_abs and filesystem_is_subpath(options.external_dir_abs, parent):
    if fileExists(parent):
      filesystem_write_error(options.target_path, "child path collision",
                             "phase: pre-validation; generated child directory parent path is already a file",
                             "externalize", result.relativePath, selector.display)
    let next_parent = parentDir(parent)
    if next_parent == parent:
      break
    parent = next_parent

proc safe_collection_child_stem(stem: string, options: WriteOptions, selector: WriteSelector,
                                child_label: string): string {.gcsafe.} =
  if stem.len == 0:
    filesystem_write_error(options.target_path, "unsafe child name",
                           "phase: pre-validation; " & child_label & " produced an empty child file name",
                           "externalize", "", selector.display)
  if stem == "." or stem == ".." or stem.isAbsolute() or stem.contains('/') or stem.contains('\\'):
    filesystem_write_error(options.target_path, "unsafe child name",
                           "phase: pre-validation; " & child_label & " produced unsafe child file name: " & stem,
                           "externalize", "", selector.display)
  stem

proc externalized_collection_child_file(options: WriteOptions, selector: WriteSelector,
                                        directory: PendingWriteDirectory, stem: string,
                                        child_label: string): tuple[relativePath: string, absolutePath: string] {.gcsafe.} =
  let safe_stem = safe_collection_child_stem(stem, options, selector, child_label)
  result.relativePath = joinPath(directory.relative_path, safe_stem & ".gene")
  result.absolutePath = normalizedPath(absolutePath(result.relativePath, options.parent_dir_abs))
  if result.absolutePath == directory.absolute_path or not filesystem_is_subpath(directory.absolute_path, result.absolutePath):
    filesystem_write_error(options.target_path, "unsafe child name",
                           "phase: pre-validation; " & child_label & " child file escapes directory",
                           "externalize", result.relativePath, selector.display)
  if dirExists(result.absolutePath):
    filesystem_write_error(options.target_path, "child path collision",
                           "phase: pre-validation; " & child_label & " child file path is already a directory",
                           "externalize", result.relativePath, selector.display)

proc zero_padded_array_child_stem(index, count: int): string {.inline.} =
  let max_index = if count <= 0: 0 else: count - 1
  let width = max(6, ($max_index).len)
  let raw = $index
  repeat("0", width - raw.len) & raw

proc new_read_dir_ref(relative_path: string, shape: ReadDirShape): Value =
  let gene = new_gene(@["gene", "serdes", "read_dir"].to_complex_symbol())
  gene.children.add(relative_path.to_value())
  case shape
  of RdsArray:
    gene.props["shape".to_key()] = "array".to_symbol_value()
  of RdsMap:
    gene.props["shape".to_key()] = "map".to_symbol_value()
  gene.props["order".to_key()] = "name".to_symbol_value()
  gene.to_gene_value()

proc new_read_file_ref(relative_path: string): Value =
  let gene = new_gene(@["gene", "serdes", "read_file"].to_complex_symbol())
  gene.children.add(relative_path.to_value())
  gene.to_gene_value()

proc pending_child_text(value: Value, options: WriteOptions, selector: WriteSelector,
                        child_path, child_label: string): string =
  try:
    result = value_to_serialized_text(value)
  except CatchableError as e:
    if is_filesystem_write_error(e.msg):
      raise
    var detail = "phase: pre-validation"
    if child_label.len > 0:
      detail &= "; " & child_label
    detail &= "; " & e.msg
    filesystem_write_error(options.target_path, "serialization failed", detail,
                           "externalize", child_path, selector.display)

proc register_pending_path(state: var WritePayloadState, options: WriteOptions,
                           selector: WriteSelector, relative_path, absolute_path,
                           child_label: string) {.gcsafe.} =
  if state.child_paths.hasKey(absolute_path):
    var detail = "phase: pre-validation; generated child path collides with selector " & state.child_paths[absolute_path]
    if child_label.len > 0:
      detail &= "; " & child_label
    filesystem_write_error(options.target_path, "child path collision", detail,
                           "externalize", relative_path, selector.display)
  state.child_paths[absolute_path] = selector.display & (if child_label.len > 0: " " & child_label else: "")

proc externalize_array_value(value: Value, options: WriteOptions, selector: WriteSelector,
                             state: var WritePayloadState): Value =
  let directory_path = externalized_child_directory(options, selector)
  register_pending_path(state, options, selector, directory_path.relativePath,
                        directory_path.absolutePath, "directory")
  let directory = PendingWriteDirectory(
    selector_display: selector.display,
    relative_path: directory_path.relativePath,
    absolute_path: directory_path.absolutePath,
  )
  state.directories.add(directory)

  let values = array_data(value)
  for index, item in values:
    let child_label = "index: " & $index
    let stem = zero_padded_array_child_stem(index, values.len)
    let child = externalized_collection_child_file(options, selector, directory, stem, child_label)
    register_pending_path(state, options, selector, child.relativePath, child.absolutePath, child_label)
    state.children.add(PendingWriteChild(
      selector_display: selector.display,
      relative_path: child.relativePath,
      absolute_path: child.absolutePath,
      serialized_text: pending_child_text(item, options, selector, child.relativePath, child_label),
      child_label: child_label,
    ))

  new_read_dir_ref(directory.relative_path, RdsArray)

proc safe_encoded_map_child_stem(key_name: string, options: WriteOptions,
                                 selector: WriteSelector): string {.gcsafe.} =
  let child_label = "key: " & key_name
  if key_name.len == 0:
    filesystem_write_error(options.target_path, "unsafe child name",
                           "phase: pre-validation; map key is empty",
                           "externalize", "", selector.display)
  result = encode_path_segment(key_name)
  discard safe_collection_child_stem(result, options, selector, child_label)

proc externalize_map_value(value: Value, options: WriteOptions, selector: WriteSelector,
                           state: var WritePayloadState): Value =
  let directory_path = externalized_child_directory(options, selector)
  register_pending_path(state, options, selector, directory_path.relativePath,
                        directory_path.absolutePath, "directory")
  let directory = PendingWriteDirectory(
    selector_display: selector.display,
    relative_path: directory_path.relativePath,
    absolute_path: directory_path.absolutePath,
  )
  state.directories.add(directory)

  var entries: seq[tuple[keyName: string, stem: string, item: Value]] = @[]
  var stems = initTable[string, string]()
  for k, item in map_data(value):
    let key_name = key_to_string(k)
    let stem = safe_encoded_map_child_stem(key_name, options, selector)
    if stems.hasKey(stem):
      filesystem_write_error(options.target_path, "child path collision",
                             "phase: pre-validation; key: " & key_name &
                               " encodes to duplicate child name used by key: " & stems[stem],
                             "externalize", joinPath(directory.relative_path, stem & ".gene"), selector.display)
    stems[stem] = key_name
    entries.add((keyName: key_name, stem: stem, item: item))

  entries.sort(proc(a, b: tuple[keyName: string, stem: string, item: Value]): int = cmp(a.keyName, b.keyName))
  for entry in entries:
    let child_label = "key: " & entry.keyName
    let child = externalized_collection_child_file(options, selector, directory, entry.stem, child_label)
    register_pending_path(state, options, selector, child.relativePath, child.absolutePath, child_label)
    state.children.add(PendingWriteChild(
      selector_display: selector.display,
      relative_path: child.relativePath,
      absolute_path: child.absolutePath,
      serialized_text: pending_child_text(entry.item, options, selector, child.relativePath, child_label),
      child_label: child_label,
    ))

  new_read_dir_ref(directory.relative_path, RdsMap)

proc externalize_selected_value(value: Value, options: WriteOptions, selector: WriteSelector,
                                state: var WritePayloadState): Value =
  if value.kind == VkArray:
    return externalize_array_value(value, options, selector, state)
  if value.kind == VkMap:
    return externalize_map_value(value, options, selector, state)

  let child = externalized_child_file(options, selector)
  register_pending_path(state, options, selector, child.relativePath, child.absolutePath, "file")

  state.children.add(PendingWriteChild(
    selector_display: selector.display,
    relative_path: child.relativePath,
    absolute_path: child.absolutePath,
    serialized_text: pending_child_text(value, options, selector, child.relativePath, "file"),
    child_label: "file",
  ))
  new_read_file_ref(child.relativePath)

proc build_write_payload(value: Value, segments: seq[string], options: WriteOptions,
                         state: var WritePayloadState): Value =
  let current = materialize_custom_value(value)
  let selected = selected_write_selector(options, segments)
  if selected.found:
    let key = tree_path_key(segments)
    state.found_selectors.incl(key)
    return externalize_selected_value(current, options, selected.selector, state)

  case current.kind
  of VkArray:
    result = new_array_value(@[], frozen = array_is_frozen(current))
    for index, item in array_data(current):
      array_data(result).add(build_write_payload(item, segments & @[$index], options, state))
  of VkMap:
    result = new_map_value(map_is_frozen(current))
    map_data(result) = initTable[Key, Value]()
    for k, v in map_data(current):
      let key_name = key_to_string(k)
      map_data(result)[k] = build_write_payload(v, segments & @[key_name], options, state)
  of VkGene:
    let gene = new_gene(state.serializer.serialize(current.gene.type), frozen = gene_is_frozen(current))
    for k, v in current.gene.props:
      let key_name = key_to_string(k)
      gene.props[k] = build_write_payload(v, segments & @[key_name], options, state)
    for index, child in current.gene.children:
      gene.children.add(build_write_payload(child, segments & @[$index], options, state))
    result = gene.to_gene_value()
  else:
    result = state.serializer.serialize(current)

proc build_externalized_write(path: string, value: Value, options: WriteOptions): tuple[parentText: string, directories: seq[PendingWriteDirectory], children: seq[PendingWriteChild]] =
  var state = WritePayloadState(
    serializer: Serialization(references: initTable[string, Value]()),
    directories: @[],
    children: @[],
    child_paths: initTable[string, string](),
    found_selectors: initHashSet[string](),
  )

  var parent_payload: Value
  try:
    parent_payload = build_write_payload(value, @[], options, state)
    for selector in options.externalize_selectors:
      let key = write_selector_key(selector)
      if not state.found_selectors.contains(key):
        filesystem_write_error(path, "missing selector target",
                               "^externalize selector did not match any value",
                               "externalize", "", selector.display)
    result.parentText = payload_to_serialized_text(parent_payload)
  except CatchableError as e:
    if is_filesystem_write_error(e.msg):
      raise
    filesystem_write_error(path, "serialization failed", e.msg)

  state.directories.sort(proc(a, b: PendingWriteDirectory): int = cmp(a.relative_path, b.relative_path))
  state.children.sort(proc(a, b: PendingWriteChild): int = cmp(a.relative_path, b.relative_path))
  result.directories = state.directories
  result.children = state.children

proc reset_externalized_directory(path: string) =
  if dirExists(path):
    for kind, child in walkDir(path):
      case kind
      of pcFile, pcLinkToFile:
        removeFile(child)
      of pcDir:
        reset_externalized_directory(child)
      of pcLinkToDir:
        removeDir(child)
      else:
        discard
    removeDir(path)
  ensure_parent_dir(path)
  createDir(path)

proc write_externalized_value_file*(path: string, value: Value, options: WriteOptions) =
  when defined(gene_wasm):
    filesystem_write_error(path, "unsupported option", "filesystem writes are not supported in gene_wasm")
  else:
    let materialized = materialize_custom_deep(value)
    let built = build_externalized_write(path, materialized, options)

    try:
      ensure_parent_dir(path)
    except CatchableError as e:
      filesystem_write_error(path, "filesystem write failed", e.msg)

    if dirExists(path):
      filesystem_write_error(path, "filesystem write failed", "target path is a directory")
    if fileExists(options.external_dir_abs):
      filesystem_write_error(path, "child path collision",
                             "external directory path is already a file",
                             "externalize", options.external_dir_rel)

    for directory in built.directories:
      try:
        reset_externalized_directory(directory.absolute_path)
      except CatchableError as e:
        filesystem_write_error(path, "filesystem write failed", "phase: cleanup; " & e.msg,
                               "externalize", directory.relative_path, directory.selector_display)

    for child in built.children:
      try:
        write_serialized_text_file(child.absolute_path, child.serialized_text)
      except CatchableError as e:
        var detail = "phase: child write"
        if child.child_label.len > 0:
          detail &= "; " & child.child_label
        detail &= "; " & e.msg
        filesystem_write_error(path, "filesystem write failed", detail,
                               "externalize", child.relative_path, child.selector_display)

    try:
      write_serialized_text_file(path, built.parentText)
    except CatchableError as e:
      filesystem_write_error(path, "filesystem write failed", "phase: parent write; " & e.msg)

proc write_value_file*(path: string, value: Value) =
  when defined(gene_wasm):
    filesystem_write_error(path, "unsupported option", "filesystem writes are not supported in gene_wasm")
  else:
    let materialized = materialize_custom_deep(value)
    var serialized_text: string
    try:
      serialized_text = value_to_serialized_text(materialized)
    except CatchableError as e:
      filesystem_write_error(path, "serialization failed", e.msg)

    try:
      write_serialized_text_file(path, serialized_text)
    except CatchableError as e:
      filesystem_write_error(path, "filesystem write failed", e.msg)

proc read_serialized_file(path: string): Value {.gcsafe.} =
  count_tree_serialized_file_read()
  deserialize(readFile(path))

proc remove_tree_dir(path: string) =
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
      remove_tree_dir(child)
    of pcLinkToDir:
      removeDir(child)
  removeDir(path)

proc remove_tree_base(path: string) =
  let file_path = path & ".gene"
  if fileExists(file_path):
    removeFile(file_path)
  if dirExists(path):
    remove_tree_dir(path)

proc write_tree_node(path: string, value: Value, node_segments: seq[string], options: TreeWriteOptions, known_map = false)
proc write_tree_dir(path: string, value: Value, node_segments: seq[string], options: TreeWriteOptions, known_map = false)
proc read_tree_path(path: string, node_segments: seq[string], options: LazyTreeReadOptions, shallow: bool): Value {.gcsafe.}
proc read_tree_root_path(path: string, options: LazyTreeReadOptions): Value {.gcsafe.}
proc read_known_map_dir(path: string, node_segments: seq[string], options: LazyTreeReadOptions, shallow: bool): Value {.gcsafe.}
proc read_array_dir(path: string, node_segments: seq[string], options: LazyTreeReadOptions, shallow: bool): Value {.gcsafe.}
proc read_gene_dir(path: string, node_segments: seq[string], options: LazyTreeReadOptions, shallow: bool): Value {.gcsafe.}
proc list_tree_dir_entries(path: string): seq[(PathComponent, string)] {.gcsafe.}
proc resolve_tree_named_child(path: string, child_name: string, child_segments: seq[string], options: LazyTreeReadOptions, shallow: bool): Value {.gcsafe.}
proc can_decode_as_array_dir(path: string): bool {.gcsafe.}

proc make_array_child_id(value: Value, used_ids: var Table[string, int]): string =
  let base = "v" & toHex(cast[uint64](tree_serialized_hash(value)), 12)
  let next_count = used_ids.getOrDefault(base, 0) + 1
  used_ids[base] = next_count
  if next_count == 1:
    base
  else:
    base & "-" & $next_count

proc write_map_dir(path: string, map_value: Value, node_segments: seq[string], options: TreeWriteOptions, allow_root_markers: bool) =
  createDir(path)
  var keys: seq[string] = @[]
  var key_values = initTable[string, Value]()
  for k, v in map_data(map_value):
    let key_name = key_to_string(k)
    if not allow_root_markers and key_name == TreeGeneTypeName:
      not_allowed("Exploded generic map roots cannot use reserved entry name: " & key_name)
    keys.add(key_name)
    key_values[key_name] = v

  keys.sort()
  for key_name in keys:
    let child = key_values[key_name]
    let encoded = encode_path_segment(key_name)
    let child_segments = node_segments & @[key_name]
    write_tree_node(joinPath(path, encoded), child, child_segments, options, false)

proc write_array_dir(path: string, array_value: Value, node_segments: seq[string], options: TreeWriteOptions) =
  createDir(path)
  var order = new_array_value()
  var used_ids = initTable[string, int]()
  for index, child in array_data(array_value):
    let child_id = make_array_child_id(child, used_ids)
    array_data(order).add(child_id.to_value())
    let child_segments = node_segments & @[$index]
    write_tree_node(joinPath(path, child_id), child, child_segments, options, false)
  write_serialized_file(joinPath(path, TreeArrayName & ".gene"), order)

proc write_gene_dir(path: string, gene_value: Value, node_segments: seq[string], options: TreeWriteOptions) =
  createDir(path)
  let type_segments = node_segments & @[TreeGeneTypeName]
  write_tree_node(joinPath(path, TreeGeneTypeName), gene_value.gene.type, type_segments, options, false)

  let props_segments = node_segments & @[TreeGenePropsName]
  if gene_value.gene.props.len > 0 or should_write_dir(options, props_segments):
    let props_path = joinPath(path, TreeGenePropsName)
    var props_value = new_map_value()
    map_data(props_value) = initTable[Key, Value]()
    for k, v in gene_value.gene.props:
      map_data(props_value)[k] = v
    write_map_dir(props_path, props_value, props_segments, options, true)

  let children_segments = node_segments & @[TreeGeneChildrenName]
  if gene_value.gene.children.len > 0 or should_write_dir(options, children_segments):
    let children_path = joinPath(path, TreeGeneChildrenName)
    var children_value = new_array_value()
    for child in gene_value.gene.children:
      array_data(children_value).add(child)
    write_array_dir(children_path, children_value, children_segments, options)

proc write_tree_node(path: string, value: Value, node_segments: seq[string], options: TreeWriteOptions, known_map = false) =
  let value = materialize_custom_deep(value)
  remove_tree_base(path)

  if should_write_dir(options, node_segments):
    if not is_tree_structural(value):
      not_allowed("write_tree ^separate targets a non-structural value at " & tree_path_display(node_segments))
    write_tree_dir(path, value, node_segments, options, known_map)
  else:
    write_serialized_file(path & ".gene", value)

proc write_tree_dir(path: string, value: Value, node_segments: seq[string], options: TreeWriteOptions, known_map = false) =
  case value.kind
  of VkMap:
    write_map_dir(path, value, node_segments, options, known_map)
  of VkArray:
    write_array_dir(path, value, node_segments, options)
  of VkGene:
    write_gene_dir(path, value, node_segments, options)
  else:
    not_allowed("Directory tree serialization requires a Map, Array, or Gene root")

proc list_tree_dir_entries(path: string): seq[(PathComponent, string)] {.gcsafe.} =
  count_tree_dir_listing()
  for kind, entry in walkDir(path, relative = true):
    result.add((kind, entry))
  result.sort(proc(a, b: (PathComponent, string)): int = cmp(a[1], b[1]))

proc resolve_tree_named_child(path: string, child_name: string, child_segments: seq[string], options: LazyTreeReadOptions, shallow: bool): Value {.gcsafe.} =
  let inline_path = joinPath(path, child_name & ".gene")
  let dir_path = joinPath(path, child_name)
  let has_inline = fileExists(inline_path)
  let has_dir = dirExists(dir_path)
  if has_inline and has_dir:
    not_allowed("Filesystem tree child is ambiguous, both file and directory exist: " & joinPath(path, child_name))
  if has_inline:
    if shallow:
      return make_lazy_tree_value(inline_path, LtsFile, child_segments, options)
    return read_serialized_file(inline_path)
  if has_dir:
    if shallow:
      return make_lazy_tree_value(dir_path, LtsDirectory, child_segments, options)
    return read_tree_dir(dir_path, child_segments, options, false)
  not_allowed("Filesystem tree child not found: " & joinPath(path, child_name))

proc read_known_map_dir(path: string, node_segments: seq[string], options: LazyTreeReadOptions, shallow: bool): Value {.gcsafe.} =
  result = new_map_value()
  map_data(result) = initTable[Key, Value]()
  for (kind, entry) in list_tree_dir_entries(path):
    case kind
    of pcFile:
      if not entry.endsWith(".gene"):
        continue
      let decoded = decode_path_segment(splitFile(entry).name)
      let child_segments = node_segments & @[decoded]
      if shallow:
        map_data(result)[decoded.to_key()] = make_lazy_tree_value(joinPath(path, entry), LtsFile, child_segments, options)
      else:
        map_data(result)[decoded.to_key()] = read_serialized_file(joinPath(path, entry))
    of pcDir:
      let decoded = decode_path_segment(entry)
      let child_segments = node_segments & @[decoded]
      if shallow:
        map_data(result)[decoded.to_key()] = make_lazy_tree_value(joinPath(path, entry), LtsDirectory, child_segments, options)
      else:
        map_data(result)[decoded.to_key()] = read_tree_dir(joinPath(path, entry), child_segments, options, false)
    else:
      discard

proc safe_tree_array_child_id(child_id: string): bool {.gcsafe.} =
  if child_id.len == 0:
    return false
  if child_id == "." or child_id == "..":
    return false
  if child_id.isAbsolute():
    return false
  if child_id.contains('/') or child_id.contains('\\'):
    return false
  true

proc reject_unsafe_tree_array_child_id(child_id: string) {.gcsafe.} =
  if not safe_tree_array_child_id(child_id):
    not_allowed(TreeArrayName & ".gene contains unsafe child id: " & child_id)

proc can_decode_as_array_dir(path: string): bool {.gcsafe.} =
  let manifest_path = joinPath(path, TreeArrayName & ".gene")
  if not fileExists(manifest_path):
    return false

  let manifest = read_serialized_file(manifest_path)
  if manifest.kind != VkArray:
    return false

  var child_ids = initHashSet[string]()
  for item in array_data(manifest):
    if item.kind != VkString:
      return false
    let child_id = item.str
    reject_unsafe_tree_array_child_id(child_id)
    if child_ids.contains(child_id):
      return false
    child_ids.incl(child_id)

  for (kind, entry) in list_tree_dir_entries(path):
    case kind
    of pcFile:
      if not entry.endsWith(".gene"):
        continue
      let entry_name = splitFile(entry).name
      if entry_name == TreeArrayName:
        continue
      if not child_ids.contains(entry_name):
        return false
    of pcDir:
      if not child_ids.contains(entry):
        return false
    else:
      discard

  for child_id in child_ids:
    let inline_path = joinPath(path, child_id & ".gene")
    let dir_path = joinPath(path, child_id)
    let has_inline = fileExists(inline_path)
    let has_dir = dirExists(dir_path)
    if has_inline == has_dir:
      return false

  true

proc read_array_dir(path: string, node_segments: seq[string], options: LazyTreeReadOptions, shallow: bool): Value {.gcsafe.} =
  let order_path = joinPath(path, TreeArrayName & ".gene")
  if not fileExists(order_path):
    not_allowed("Exploded array is missing " & TreeArrayName & ".gene: " & path)

  let order = read_serialized_file(order_path)
  if order.kind != VkArray:
    not_allowed(TreeArrayName & ".gene must contain an array of child ids")

  result = new_array_value()
  for index, item in array_data(order):
    if item.kind != VkString:
      not_allowed(TreeArrayName & ".gene child ids must be strings")
    let child_id = item.str
    reject_unsafe_tree_array_child_id(child_id)
    let inline_path = joinPath(path, child_id & ".gene")
    let dir_path = joinPath(path, child_id)
    let child_segments = node_segments & @[$index]
    if fileExists(inline_path):
      if shallow:
        array_data(result).add(make_lazy_tree_value(inline_path, LtsFile, child_segments, options))
      else:
        array_data(result).add(read_serialized_file(inline_path))
    elif dirExists(dir_path):
      if shallow:
        array_data(result).add(make_lazy_tree_value(dir_path, LtsDirectory, child_segments, options))
      else:
        array_data(result).add(read_tree_dir(dir_path, child_segments, options, false))
    else:
      not_allowed("Missing exploded array child: " & child_id)

proc read_gene_dir(path: string, node_segments: seq[string], options: LazyTreeReadOptions, shallow: bool): Value {.gcsafe.} =
  let type_file_path = joinPath(path, TreeGeneTypeName & ".gene")
  let type_dir_path = joinPath(path, TreeGeneTypeName)
  if not fileExists(type_file_path) and not dirExists(type_dir_path):
    not_allowed("Exploded Gene value is missing " & TreeGeneTypeName & ": " & path)

  let type_segments = node_segments & @[TreeGeneTypeName]
  let gene = new_gene(resolve_tree_named_child(path, TreeGeneTypeName, type_segments, options, shallow))

  let props_path = joinPath(path, TreeGenePropsName)
  if dirExists(props_path):
    let props_segments = node_segments & @[TreeGenePropsName]
    let props_value = read_known_map_dir(props_path, props_segments, options, shallow)
    for k, v in map_data(props_value):
      gene.props[k] = v

  let children_path = joinPath(path, TreeGeneChildrenName)
  if dirExists(children_path):
    let children_segments = node_segments & @[TreeGeneChildrenName]
    let children_value = read_array_dir(children_path, children_segments, options, shallow)
    for child in array_data(children_value):
      gene.children.add(child)

  gene.to_gene_value()

proc read_tree_dir(path: string, node_segments: seq[string], options: LazyTreeReadOptions, shallow: bool): Value {.gcsafe.} =
  let type_file_path = joinPath(path, TreeGeneTypeName & ".gene")
  let type_dir_path = joinPath(path, TreeGeneTypeName)
  if fileExists(type_file_path) or dirExists(type_dir_path):
    return read_gene_dir(path, node_segments, options, shallow)

  if can_decode_as_array_dir(path):
    return read_array_dir(path, node_segments, options, shallow)

  read_known_map_dir(path, node_segments, options, shallow)

proc read_tree_path(path: string, node_segments: seq[string], options: LazyTreeReadOptions, shallow: bool): Value {.gcsafe.} =
  if fileExists(path):
    if shallow:
      return make_lazy_tree_value(path, LtsFile, node_segments, options)
    return read_serialized_file(path)
  if dirExists(path):
    if shallow:
      return make_lazy_tree_value(path, LtsDirectory, node_segments, options)
    return read_tree_dir(path, node_segments, options, false)
  not_allowed("Filesystem tree path not found: " & path)

proc read_tree_root_path(path: string, options: LazyTreeReadOptions): Value {.gcsafe.} =
  if path.endsWith(".gene"):
    if options.lazy_nodes.contains(tree_path_key(@[])):
      return make_lazy_tree_value(path, LtsFile, @[], options)
    return read_tree_path(path, @[], options, false)

  let inline_path = path & ".gene"
  let has_inline = fileExists(inline_path)
  let has_dir = dirExists(path)

  if has_inline and has_dir:
    not_allowed("Filesystem tree root is ambiguous, both file and directory exist: " & path)
  if has_inline:
    if options.lazy_nodes.contains(tree_path_key(@[])):
      return make_lazy_tree_value(inline_path, LtsFile, @[], options)
    return read_serialized_file(inline_path)
  if has_dir:
    return read_tree_dir(path, @[], options, options.enabled)
  read_tree_path(path, @[], options, false)

proc materialize_lazy_tree_data(data: CustomValue): Value {.gcsafe.} =
  let lazy_data = LazyTreeValueData(data)
  if lazy_data.materialized_loaded:
    return lazy_data.materialized

  case lazy_data.source_kind
  of LtsFile:
    lazy_data.materialized = read_serialized_file(lazy_data.path)
  of LtsDirectory:
    lazy_data.materialized = read_tree_dir(lazy_data.path, lazy_data.node_segments, lazy_data.options, true)
  lazy_data.materialized_loaded = true

  lazy_data.materialized

proc to_s*(self: Serialization): string =
  result = payload_to_serialized_text(self.data)

proc value_to_gene_str*(self: Value): string =
  let self = materialize_custom_value(self)
  case self.kind:
  of VkNil:
    result = "nil"
  of VkVoid:
    result = "void"
  of VkBool:
    result = if self == TRUE: "true" else: "false"
  of VkInt:
    result = $self.to_int()
  of VkFloat:
    result = $self.to_float()
  of VkChar:
    # Extract char from NaN-boxed value
    result = "'" & $chr((self.raw and 0xFF).int) & "'"
  of VkString:
    result = json.escapeJson(self.str)
  of VkSymbol:
    result = self.str
  of VkArray:
    result = if array_is_frozen(self): "#[" else: "["
    for i, v in array_data(self):
      if i > 0:
        result &= " "
      result &= value_to_gene_str(v)
    result &= "]"
  of VkMap:
    result = if map_is_frozen(self): "#{" else: "{"
    var first = true
    for k, v in map_data(self):
      if not first:
        result &= " "
      # k is a Key (distinct int64), which is a packed symbol value
      # Extract the symbol index from the packed value
      let symbol_value = cast[Value](k)
      let symbol_index = cast[uint64](symbol_value) and PAYLOAD_MASK
      let key_str = get_symbol(symbol_index.int)
      result &= "^" & key_str
      result &= " "
      result &= value_to_gene_str(v)
      first = false
    result &= "}"
  of VkGene:
    result = if gene_is_frozen(self): "#(" else: "("
    result &= value_to_gene_str(self.gene.type)
    # Add properties
    for k, v in self.gene.props:
      let symbol_value = cast[Value](k)
      let symbol_index = cast[uint64](symbol_value) and PAYLOAD_MASK
      result &= " ^" & get_symbol(symbol_index.int) & " " & value_to_gene_str(v)
    # Add children
    for child in self.gene.children:
      result &= " " & value_to_gene_str(child)
    result &= ")"
  else:
    result = $self  # Fallback to default string representation

#################### Deserialization #############

proc deserialize*(self: Serialization, value: Value): Value {.gcsafe.}

proc filesystem_context_description(context: FilesystemReadContext): string {.inline, gcsafe.} =
  if context == nil or context.containing_file.len == 0:
    "<direct>"
  else:
    context.containing_file

proc filesystem_stack_contains(stack: seq[string], path: string): bool {.inline, gcsafe.} =
  for item in stack:
    if item == path:
      return true
  false

proc copy_filesystem_read_stack(context: FilesystemReadContext): seq[string] {.gcsafe.} =
  result = @[]
  if context == nil:
    return
  for item in context.read_stack:
    result.add(item)

proc clone_filesystem_context(context: FilesystemReadContext): FilesystemReadContext {.gcsafe.} =
  if context == nil:
    return nil
  FilesystemReadContext(
    containing_file: context.containing_file,
    base_dir: context.base_dir,
    read_stack: copy_filesystem_read_stack(context),
  )

proc filesystem_stack_chain(stack: seq[string], next_path = ""): string {.gcsafe.} =
  var parts: seq[string] = @[]
  for item in stack:
    parts.add(item)
  if next_path.len > 0 and (parts.len == 0 or parts[^1] != next_path):
    parts.add(next_path)
  if parts.len == 0:
    return "<empty>"
  parts.join(" -> ")

proc filesystem_read_error(ref_kind: string, context: FilesystemReadContext,
                           target_path, resolved_path, reason, detail: string) {.noreturn, gcsafe.} =
  var message = "gene/serdes/" & ref_kind & " failed"
  message &= "; reason: " & reason
  message &= "; containing file: " & filesystem_context_description(context)
  message &= "; target: " & (if target_path.len > 0: target_path else: "<missing>")
  if resolved_path.len > 0:
    message &= "; resolved: " & resolved_path
  if context != nil:
    message &= "; stack chain: " & filesystem_stack_chain(context.read_stack, resolved_path)
  if detail.len > 0:
    message &= "; detail: " & detail
  not_allowed(message)

proc filesystem_is_subpath(base_path, candidate_path: string): bool {.inline, gcsafe.} =
  when defined(windows):
    let base_norm = normalizedPath(base_path).toLowerAscii()
    let candidate_norm = normalizedPath(candidate_path).toLowerAscii()
  else:
    let base_norm = normalizedPath(base_path)
    let candidate_norm = normalizedPath(candidate_path)

  if candidate_norm == base_norm:
    return true
  candidate_norm.startsWith(base_norm & DirSep)

proc resolve_filesystem_read_target(context: FilesystemReadContext, target_path, ref_kind: string): string {.gcsafe.} =
  if context == nil:
    return normalizedPath(absolutePath(target_path))

  if target_path.isAbsolute:
    filesystem_read_error(ref_kind, context, target_path, "", "absolute path", "nested filesystem refs must be relative")

  let base_dir = normalizedPath(absolutePath(context.base_dir))
  result = normalizedPath(absolutePath(target_path, base_dir))
  if not filesystem_is_subpath(base_dir, result):
    filesystem_read_error(ref_kind, context, target_path, result, "path escape", "nested filesystem ref leaves containing directory")

proc canonical_existing_filesystem_path(path: string): string {.gcsafe.} =
  try:
    {.cast(gcsafe).}:
      result = normalizedPath(expandSymlink(expandFilename(path)))
  except CatchableError:
    result = normalizedPath(absolutePath(path))

proc is_filesystem_read_error(message: string): bool {.inline, gcsafe.} =
  message.startsWith("gene/serdes/read_file failed") or
    message.startsWith("gene/serdes/read_dir failed")

proc child_filesystem_context(parent_context: FilesystemReadContext, containing_file: string): FilesystemReadContext {.gcsafe.} =
  let normalized_file = normalizedPath(absolutePath(containing_file))
  var stack = copy_filesystem_read_stack(parent_context)
  stack.add(normalized_file)
  FilesystemReadContext(
    containing_file: normalized_file,
    base_dir: parentDir(normalized_file),
    read_stack: stack,
  )

proc child_filesystem_directory_context(parent_context: FilesystemReadContext, containing_dir: string): FilesystemReadContext {.gcsafe.} =
  let normalized_dir = normalizedPath(absolutePath(containing_dir))
  var stack = copy_filesystem_read_stack(parent_context)
  stack.add(normalized_dir)
  FilesystemReadContext(
    containing_file: normalized_dir,
    base_dir: normalized_dir,
    read_stack: stack,
  )

proc default_read_dir_options(): ReadDirOptions {.inline, gcsafe.} =
  ReadDirOptions(shape: RdsArray, order: RdoName)

proc read_dir_option_atom(value: Value, option_name, ref_kind: string,
                          context: FilesystemReadContext, target_path: string): string {.gcsafe.} =
  case value.kind
  of VkString, VkSymbol:
    result = value.str
  of VkComplexSymbol:
    if value.ref.csymbol.len == 1:
      result = value.ref.csymbol[0]
    else:
      result = value.ref.csymbol.join("/")
  else:
    filesystem_read_error(ref_kind, context, target_path, "", "unsupported option",
                          "^" & option_name & " must be string or symbol, got " & $value.kind)

proc parse_read_dir_option(options: var ReadDirOptions, key_name: string, prop_value: Value,
                           ref_kind: string, context: FilesystemReadContext,
                           target_path: string) {.gcsafe.} =
  case key_name
  of "shape":
    let shape_name = read_dir_option_atom(prop_value, key_name, ref_kind, context, target_path)
    case shape_name
    of "array":
      options.shape = RdsArray
    of "map":
      options.shape = RdsMap
    else:
      filesystem_read_error(ref_kind, context, target_path, "", "unsupported option",
                            "^shape unsupported value: " & shape_name & " (supported: array, map)")
  of "order":
    let order_name = read_dir_option_atom(prop_value, key_name, ref_kind, context, target_path)
    case order_name
    of "name":
      options.order = RdoName
    else:
      filesystem_read_error(ref_kind, context, target_path, "", "unsupported option",
                            "^order unsupported value: " & order_name & " (supported: name)")
  of "lazy":
    if prop_value.kind != VkBool:
      filesystem_read_error(ref_kind, context, target_path, "", "unsupported option",
                            "^lazy must be boolean, got " & $prop_value.kind)
    if prop_value == TRUE:
      filesystem_read_error(ref_kind, context, target_path, "", "unsupported option",
                            "directory-lazy is unsupported in S03; gene/serdes/read_dir remains eager-only in this slice")
  else:
    filesystem_read_error(ref_kind, context, target_path, "", "unsupported option",
                          "unknown property ^" & key_name)

proc read_dir_options_from_props(props: Table[Key, Value], ref_kind: string,
                                 context: FilesystemReadContext, target_path: string): ReadDirOptions {.gcsafe.} =
  result = default_read_dir_options()
  for key, prop_value in props:
    parse_read_dir_option(result, key_to_string(key), prop_value, ref_kind, context, target_path)

proc read_dir_options_from_keyword_args(args: ptr UncheckedArray[Value], has_keyword_args: bool,
                                        ref_kind: string, context: FilesystemReadContext,
                                        target_path: string): ReadDirOptions {.gcsafe.} =
  result = default_read_dir_options()
  if not has_keyword_args:
    return

  if args == nil or args[0].kind != VkMap:
    filesystem_read_error(ref_kind, context, target_path, "", "unsupported option",
                          "keyword arguments must be provided as a map")

  for key, prop_value in map_data(args[0]):
    parse_read_dir_option(result, key_to_string(key), prop_value, ref_kind, context, target_path)

proc parse_read_file_option(lazy: var bool, key_name: string, prop_value: Value,
                            ref_kind: string, context: FilesystemReadContext,
                            target_path: string) {.gcsafe.} =
  case key_name
  of "lazy":
    if prop_value.kind != VkBool:
      filesystem_read_error(ref_kind, context, target_path, "", "unsupported option",
                            "^lazy must be boolean, got " & $prop_value.kind)
    lazy = prop_value == TRUE
  else:
    filesystem_read_error(ref_kind, context, target_path, "", "unsupported option",
                          "unknown property ^" & key_name)

proc read_file_lazy_from_props(props: Table[Key, Value], ref_kind: string,
                               context: FilesystemReadContext, target_path: string): bool {.gcsafe.} =
  result = false
  for key, prop_value in props:
    parse_read_file_option(result, key_to_string(key), prop_value, ref_kind, context, target_path)

proc read_file_lazy_from_keyword_args(args: ptr UncheckedArray[Value], has_keyword_args: bool,
                                      ref_kind: string, context: FilesystemReadContext,
                                      target_path: string): bool {.gcsafe.} =
  result = false
  if not has_keyword_args:
    return

  if args == nil or args[0].kind != VkMap:
    filesystem_read_error(ref_kind, context, target_path, "", "unsupported option",
                          "keyword arguments must be provided as a map")

  for key, prop_value in map_data(args[0]):
    parse_read_file_option(result, key_to_string(key), prop_value, ref_kind, context, target_path)

proc deserialize_with_filesystem_context(value: Value, context: FilesystemReadContext): Value {.gcsafe.} =
  var ser = Serialization(
    references: initTable[string, Value](),
    filesystem_context: context,
  )
  ser.deserialize(value)

proc read_file_value*(path: string, context: FilesystemReadContext = nil, ref_kind = "read_file"): Value {.gcsafe.} =
  when defined(gene_wasm):
    filesystem_read_error(ref_kind, context, path, "", "unsupported option", "filesystem reads are not supported in gene_wasm")
  else:
    var resolved_path = resolve_filesystem_read_target(context, path, ref_kind)
    if context != nil and filesystem_stack_contains(context.read_stack, resolved_path):
      filesystem_read_error(ref_kind, context, path, resolved_path, "cycle", "target is already in the filesystem read stack")

    if not fileExists(resolved_path):
      filesystem_read_error(ref_kind, context, path, resolved_path, "missing", "exact file does not exist")

    let canonical_path = canonical_existing_filesystem_path(resolved_path)
    if context != nil:
      let canonical_base = canonical_existing_filesystem_path(context.base_dir)
      if not filesystem_is_subpath(canonical_base, canonical_path):
        filesystem_read_error(ref_kind, context, path, canonical_path, "path escape", "nested filesystem ref leaves containing directory after canonicalization")
      if filesystem_stack_contains(context.read_stack, canonical_path):
        filesystem_read_error(ref_kind, context, path, canonical_path, "cycle", "target is already in the filesystem read stack")
    resolved_path = canonical_path

    var text: string
    try:
      text = readFile(resolved_path)
    except CatchableError as e:
      filesystem_read_error(ref_kind, context, path, resolved_path, "unreadable", e.msg)

    let child_context = child_filesystem_context(context, resolved_path)
    var forms: seq[Value]
    try:
      forms = read_all(text)
    except CatchableError as e:
      filesystem_read_error(ref_kind, child_context, path, resolved_path, "invalid payload", e.msg)

    if forms.len != 1:
      filesystem_read_error(ref_kind, child_context, path, resolved_path, "invalid payload",
                            "expected exactly one serialized form, got " & $forms.len)

    try:
      return deserialize_with_filesystem_context(forms[0], child_context)
    except CatchableError as e:
      if is_filesystem_read_error(e.msg):
        raise
      filesystem_read_error(ref_kind, child_context, path, resolved_path, "invalid payload", e.msg)

proc materialize_lazy_file_ref_data(data: CustomValue): Value {.gcsafe.} =
  let lazy_data = LazyFileRefValueData(data)
  if lazy_data.materialized_loaded:
    return lazy_data.materialized

  let materialized = read_file_value(lazy_data.target_path, lazy_data.filesystem_context, lazy_data.ref_kind)
  lazy_data.materialized = materialized
  lazy_data.materialized_loaded = true
  materialized

proc make_lazy_file_ref_value(target_path: string, context: FilesystemReadContext,
                              ref_kind: string): Value {.gcsafe.} =
  if lazy_file_ref_value_class.is_nil:
    not_allowed("Lazy file-ref class is not initialized")
  let data = LazyFileRefValueData(
    target_path: target_path,
    filesystem_context: clone_filesystem_context(context),
    ref_kind: ref_kind,
    materialized: NIL,
    materialized_loaded: false,
  )
  data.materialize_hook = materialize_lazy_file_ref_data
  new_custom_value(lazy_file_ref_value_class, data)

proc materialize_lazy_file_ref_value*(value: Value): Value {.gcsafe.} =
  if not is_lazy_file_ref_value(value):
    return value
  let data = LazyFileRefValueData(value.ref.custom_data)
  if data.materialized_loaded:
    return data.materialized
  data.materialize_hook(data)

proc list_read_dir_child_files(path, target_path, ref_kind: string,
                               context: FilesystemReadContext): seq[string] {.gcsafe.} =
  try:
    for kind, entry in walkDir(path, relative = true):
      case kind
      of pcFile:
        if not entry.endsWith(".gene"):
          filesystem_read_error(ref_kind, context, target_path, path, "invalid payload",
                                "unexpected non-.gene entry: " & entry)
        result.add(entry)
      of pcDir:
        filesystem_read_error(ref_kind, context, target_path, path, "invalid payload",
                              "unexpected subdirectory entry: " & entry)
      of pcLinkToFile, pcLinkToDir:
        filesystem_read_error(ref_kind, context, target_path, path, "invalid payload",
                              "unexpected symlink entry: " & entry)
  except CatchableError as e:
    if is_filesystem_read_error(e.msg):
      raise
    filesystem_read_error(ref_kind, context, target_path, path, "invalid payload", e.msg)

  result.sort()

proc read_dir_value(path: string, options: ReadDirOptions, context: FilesystemReadContext = nil,
                    ref_kind = "read_dir"): Value {.gcsafe.} =
  when defined(gene_wasm):
    filesystem_read_error(ref_kind, context, path, "", "unsupported option", "filesystem reads are not supported in gene_wasm")
  else:
    var resolved_path = resolve_filesystem_read_target(context, path, ref_kind)
    if context != nil and filesystem_stack_contains(context.read_stack, resolved_path):
      filesystem_read_error(ref_kind, context, path, resolved_path, "cycle", "target is already in the filesystem read stack")

    if fileExists(resolved_path):
      filesystem_read_error(ref_kind, context, path, resolved_path, "invalid payload", "target is a file, expected a directory")
    if not dirExists(resolved_path):
      filesystem_read_error(ref_kind, context, path, resolved_path, "missing", "directory does not exist")

    let canonical_path = canonical_existing_filesystem_path(resolved_path)
    if context != nil:
      let canonical_base = canonical_existing_filesystem_path(context.base_dir)
      if not filesystem_is_subpath(canonical_base, canonical_path):
        filesystem_read_error(ref_kind, context, path, canonical_path, "path escape", "nested filesystem ref leaves containing directory after canonicalization")
      if filesystem_stack_contains(context.read_stack, canonical_path):
        filesystem_read_error(ref_kind, context, path, canonical_path, "cycle", "target is already in the filesystem read stack")
    resolved_path = canonical_path

    let dir_context = child_filesystem_directory_context(context, resolved_path)
    let child_files = list_read_dir_child_files(resolved_path, path, ref_kind, dir_context)

    case options.order
    of RdoName:
      discard

    case options.shape
    of RdsArray:
      result = new_array_value()
      for child_file in child_files:
        array_data(result).add(read_file_value(child_file, dir_context, ref_kind))
    of RdsMap:
      result = new_map_value()
      map_data(result) = initTable[Key, Value]()
      for child_file in child_files:
        let encoded_name = splitFile(child_file).name
        var key_name: string
        try:
          key_name = decode_path_segment(encoded_name)
        except CatchableError as e:
          filesystem_read_error(ref_kind, dir_context, path, resolved_path, "invalid payload",
                                "could not decode map child name " & encoded_name & ": " & e.msg)
        let key = key_name.to_key()
        if map_data(result).hasKey(key):
          filesystem_read_error(ref_kind, dir_context, path, resolved_path, "invalid payload",
                                "duplicate decoded map child key: " & key_name)
        map_data(result)[key] = read_file_value(child_file, dir_context, ref_kind)

proc deserialize_read_file_ref(self: Serialization, gene: ptr Gene, ref_kind = "read_file"): Value {.gcsafe.} =
  let target_hint =
    if gene.children.len > 0:
      if gene.children[0].kind == VkString: gene.children[0].str else: $gene.children[0].kind
    else:
      ""

  if gene.children.len != 1:
    filesystem_read_error(ref_kind, self.filesystem_context, target_hint, "", "wrong arity",
                          "expected 1 path argument, got " & $gene.children.len)

  let path_value = gene.children[0]
  let target_path = target_hint
  if path_value.kind != VkString:
    filesystem_read_error(ref_kind, self.filesystem_context, target_path, "", "non-string path",
                          "path argument must be a string, got " & $path_value.kind)

  let lazy = read_file_lazy_from_props(gene.props, ref_kind, self.filesystem_context, target_path)

  if self.filesystem_context == nil:
    filesystem_read_error(ref_kind, nil, target_path, "", "no filesystem context",
                          "serialized " & ref_kind & " refs require a containing file")

  if lazy:
    make_lazy_file_ref_value(target_path, self.filesystem_context, ref_kind)
  else:
    read_file_value(target_path, self.filesystem_context, ref_kind)

proc deserialize_read_dir_ref(self: Serialization, gene: ptr Gene): Value {.gcsafe.} =
  const ref_kind = "read_dir"
  let target_hint =
    if gene.children.len > 0:
      if gene.children[0].kind == VkString: gene.children[0].str else: $gene.children[0].kind
    else:
      ""

  if gene.children.len != 1:
    filesystem_read_error(ref_kind, self.filesystem_context, target_hint, "", "wrong arity",
                          "expected 1 path argument, got " & $gene.children.len)

  let path_value = gene.children[0]
  let target_path = target_hint
  if path_value.kind != VkString:
    filesystem_read_error(ref_kind, self.filesystem_context, target_path, "", "non-string path",
                          "path argument must be a string, got " & $path_value.kind)

  let options = read_dir_options_from_props(gene.props, ref_kind, self.filesystem_context, target_path)

  if self.filesystem_context == nil:
    filesystem_read_error(ref_kind, nil, target_path, "", "no filesystem context",
                          "serialized read_dir refs require a containing file")

  read_dir_value(target_path, options, self.filesystem_context, ref_kind)

proc deref*(self: Serialization, s: string): Value =
  path_to_value(s)

proc deserialize_enum_value(self: Serialization, gene: ptr Gene): Value {.gcsafe.} =
  if gene.children.len != 2:
    not_allowed("EnumValue expects an EnumRef and payload array, got " & $gene.children.len & " child(ren)")

  let ref_form = gene.children[0]
  let ref_kind = serialized_gene_type_name(ref_form)
  if ref_kind != "EnumRef":
    let got = if ref_kind.len > 0: ref_kind else: $ref_form.kind
    not_allowed("EnumValue expects first child to be EnumRef, got " & got)

  var variant: Value
  try:
    variant = resolve_typed_ref(ref_form.gene)
  except CatchableError as e:
    not_allowed("EnumValue EnumRef resolution failed: " & e.msg)

  let member = require_enum_value_member(variant, "EnumValue")

  let payload_form = gene.children[1]
  if payload_form.kind != VkArray:
    not_allowed("EnumValue payload must be an array, got " & $payload_form.kind)

  validate_enum_payload_arity(member, array_data(payload_form).len, "EnumValue")

  var payload = newSeqOfCap[Value](array_data(payload_form).len)
  for item in array_data(payload_form):
    payload.add(self.deserialize(item))

  try:
    validate_enum_payload_types(member, payload, "EnumValue")
  except CatchableError as e:
    not_allowed("EnumValue payload validation failed: " & e.msg)

  if enum_payload_arity(member) == 0:
    return variant
  new_enum_value(variant, payload)

proc deserialize_tuple_value(self: Serialization, gene: ptr Gene): Value {.gcsafe.} =
  if gene.children.len != 2:
    not_allowed("TupleValue expects a TupleRef and payload array, got " & $gene.children.len & " child(ren)")

  let ref_form = gene.children[0]
  let ref_kind = serialized_gene_type_name(ref_form)
  if ref_kind != "TupleRef":
    let got = if ref_kind.len > 0: ref_kind else: $ref_form.kind
    not_allowed("TupleValue expects first child to be TupleRef, got " & got)

  let tuple_def_value = resolve_tuple_ref(ref_form.gene, "TupleValue")
  let tuple_def = require_tuple_def_value(tuple_def_value, "TupleValue")

  let payload_form = gene.children[1]
  if payload_form.kind != VkArray:
    not_allowed("TupleValue payload must be an array, got " & $payload_form.kind)

  validate_tuple_payload_arity_for_serdes(tuple_def, array_data(payload_form).len, "TupleValue")

  var payload = newSeqOfCap[Value](array_data(payload_form).len)
  for i, item in array_data(payload_form):
    try:
      payload.add(self.deserialize(item))
    except CatchableError as e:
      not_allowed("TupleValue payload deserialization failed at " &
                  tuple_payload_type_label(tuple_def, i) & ": " & e.msg)

  try:
    validate_tuple_payload_types(tuple_def, payload, "TupleValue")
  except CatchableError as e:
    not_allowed("TupleValue payload validation failed: " & e.msg)

  new_tuple_value(tuple_def_value, payload)

proc deserialize*(s: string): Value =
  var ser = Serialization(
    references: initTable[string, Value](),
  )
  ser.deserialize(read_all(s)[0])

proc deserialize*(self: Serialization, value: Value): Value =
  case value.kind:
  of VkArray:
    result = new_array_value(@[], frozen = array_is_frozen(value))
    for item in array_data(value):
      array_data(result).add(self.deserialize(item))
  of VkMap:
    result = new_map_value(map_is_frozen(value))
    map_data(result) = initTable[Key, Value]()
    for k, v in map_data(value):
      map_data(result)[k] = self.deserialize(v)
  of VkGene:
    var type_str: string
    if value.gene.type.kind == VkSymbol:
      type_str = value.gene.type.str
    elif value.gene.type.kind == VkComplexSymbol:
      type_str = value.gene.type.ref.csymbol.join("/")
    else:
      let gene = new_gene(self.deserialize(value.gene.type), frozen = gene_is_frozen(value))
      for k, v in value.gene.props:
        gene.props[k] = self.deserialize(v)
      for child in value.gene.children:
        gene.children.add(self.deserialize(child))
      return gene.to_gene_value()

    case type_str:
    of "gene/serialization":
      if value.gene.children.len > 0:
        return self.deserialize(value.gene.children[0])
      else:
        return NIL
    of "gene/serdes/read_file":
      return self.deserialize_read_file_ref(value.gene, "read_file")
    of "gene/serdes/read":
      return self.deserialize_read_file_ref(value.gene, "read")
    of "gene/serdes/read_dir":
      return self.deserialize_read_dir_ref(value.gene)
    of "NamespaceRef", "ClassRef", "FunctionRef", "EnumRef", "InstanceRef":
      return resolve_typed_ref(value.gene)
    of "TupleRef":
      return resolve_tuple_ref(value.gene, "TupleRef")
    of "EnumValue":
      return self.deserialize_enum_value(value.gene)
    of "TupleValue":
      return self.deserialize_tuple_value(value.gene)
    of "gene/ref":
      if value.gene.children.len > 0:
        return self.deref(value.gene.children[0].str)
      else:
        return NIL
    of "Instance":
      if value.gene.children.len < 2:
        not_allowed("Instance expects a class reference and payload")

      let class_ref = self.deserialize(value.gene.children[0])
      if class_ref.kind != VkClass:
        not_allowed("Instance expects a class reference")

      let cls = class_ref.ref.class
      let hooks = require_custom_serdes_hooks(cls)
      let state = self.deserialize(value.gene.children[1])
      let class_val = class_to_value(cls)
      var restored: Value
      case hooks.deserialize_hook.kind:
      of VkFunction, VkBlock:
        if VM == nil:
          not_allowed("Deserialization hook requires an active VM")
        {.cast(gcsafe).}:
          restored = vm_exec_callable(VM, hooks.deserialize_hook, @[class_val, state])
      of VkNativeFn:
        restored = call_native_fn(hooks.deserialize_hook.ref.native_fn, VM, [class_val, state])
      else:
        not_allowed("Deserialize hook must be a function or native function")

      if restored.kind != VkCustom:
        not_allowed("Instance deserialize hook must return a custom value")
      if restored.ref.custom_class != cls:
        not_allowed("Instance deserialize hook returned custom value of unexpected class")
      return restored
    of "gene/instance":
      not_allowed("Legacy anonymous instance serialization is not supported")
    else:
      let gene = new_gene(self.deserialize(value.gene.type), frozen = gene_is_frozen(value))
      for k, v in value.gene.props:
        gene.props[k] = self.deserialize(v)
      for child in value.gene.children:
        gene.children.add(self.deserialize(child))
      return gene.to_gene_value()
  else:
    return value

# VM integration functions
proc resolve_symbol_in_caller(caller_frame: Frame, name: string): Value =
  let key = name.to_key()

  if caller_frame != nil and caller_frame.scope != nil and caller_frame.scope.tracker != nil:
    let found = caller_frame.scope.tracker.locate(key)
    if found.local_index >= 0:
      var scope = caller_frame.scope
      var parent_index = found.parent_index
      while parent_index > 0:
        parent_index.dec()
        scope = scope.parent
      if scope != nil and found.local_index < scope.members.len:
        return scope.members[found.local_index]

  if caller_frame != nil and caller_frame.ns != nil:
    let ns_value = caller_frame.ns[key]
    if ns_value != NIL:
      return ns_value

  let global_value = App.app.global_ns.ref.ns.members.getOrDefault(key, NIL)
  if global_value != NIL:
    return global_value

  App.app.gene_ns.ref.ns.members.getOrDefault(key, NIL)

proc eval_in_caller_context(vm: ptr VirtualMachine, expr: Value, caller_frame: Frame): Value =
  discard vm
  case expr.kind
  of VkString, VkInt, VkFloat, VkBool, VkNil, VkChar, VkComplexSymbol:
    return expr
  of VkSymbol:
    let resolved = resolve_symbol_in_caller(caller_frame, expr.str)
    if resolved == NIL:
      not_allowed("Unknown symbol in caller context: " & expr.str)
    return resolved
  of VkArray:
    result = new_array_value(@[], frozen = array_is_frozen(expr))
    for item in array_data(expr):
      array_data(result).add(eval_in_caller_context(vm, item, caller_frame))
  of VkMap:
    result = new_map_value(map_is_frozen(expr))
    for k, v in map_data(expr):
      map_data(result)[k] = eval_in_caller_context(vm, v, caller_frame)
  of VkGene:
    let gene = new_gene(eval_in_caller_context(vm, expr.gene.type, caller_frame), frozen = gene_is_frozen(expr))
    for k, v in expr.gene.props:
      gene.props[k] = eval_in_caller_context(vm, v, caller_frame)
    for child in expr.gene.children:
      gene.children.add(eval_in_caller_context(vm, child, caller_frame))
    return gene.to_gene_value()
  of VkQuote:
    return expr.ref.quote
  else:
    not_allowed("write_tree macro arguments must be literals or symbols")

proc write_tree_root(path: string, value: Value, options: TreeWriteOptions) =
  let value = materialize_custom_deep(value)
  if path.endsWith(".gene"):
    if options.directory_nodes.len > 0:
      not_allowed("write_tree cannot use a .gene path when ^separate requires directories")
    write_serialized_file(path, value)
  else:
    remove_tree_base(path)
    if should_write_dir(options, @[]):
      if not is_tree_structural(value):
        not_allowed("write_tree ^separate targets a non-structural root value")
      write_tree_dir(path, value, @[], options, false)
    else:
      write_serialized_file(path & ".gene", value)

proc lazy_tree_class_ref(value: Value): Class {.gcsafe.} =
  proc class_value_ref(class_value: Value): Class =
    if class_value.kind == VkClass:
      class_value.ref.class
    else:
      nil

  case value.kind
  of VkNil:
    class_value_ref(App.app.nil_class)
  of VkBool:
    class_value_ref(App.app.bool_class)
  of VkInt:
    class_value_ref(App.app.int_class)
  of VkFloat:
    class_value_ref(App.app.float_class)
  of VkChar:
    class_value_ref(App.app.char_class)
  of VkString:
    class_value_ref(App.app.string_class)
  of VkSymbol:
    class_value_ref(App.app.symbol_class)
  of VkComplexSymbol:
    class_value_ref(App.app.complex_symbol_class)
  of VkArray:
    class_value_ref(App.app.array_class)
  of VkMap:
    class_value_ref(App.app.map_class)
  of VkGene:
    class_value_ref(App.app.gene_class)
  of VkRegex:
    class_value_ref(App.app.regex_class)
  of VkDate:
    class_value_ref(App.app.date_class)
  of VkDateTime:
    class_value_ref(App.app.datetime_class)
  of VkSet:
    class_value_ref(if App.app.hash_set_class.kind == VkClass: App.app.hash_set_class else: App.app.object_class)
  of VkFuture:
    class_value_ref(if App.app.future_class.kind == VkClass: App.app.future_class else: App.app.object_class)
  of VkGenerator:
    class_value_ref(if App.app.generator_class.kind == VkClass: App.app.generator_class else: App.app.object_class)
  of VkNamespace:
    class_value_ref(App.app.namespace_class)
  of VkClass:
    class_value_ref(App.app.class_class)
  of VkInstance:
    value.instance_class
  of VkCustom:
    value.ref.custom_class
  of VkSelector:
    class_value_ref(App.app.selector_class)
  else:
    class_value_ref(App.app.object_class)

proc delegate_lazy_tree_method(vm: ptr VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool, method_name: string): Value {.gcsafe.} =
  if get_positional_count(arg_count, has_keyword_args) < 1:
    not_allowed("Lazy tree method requires self")

  let self_value = get_positional_arg(args, 0, has_keyword_args)
  let actual = materialize_lazy_tree_value(self_value)
  let actual_class = lazy_tree_class_ref(actual)
  if actual_class == nil:
    not_allowed("Lazy tree method dispatch requires a concrete class")

  let meth = actual_class.get_method(method_name)
  if meth == nil or meth.callable.kind notin {VkNativeFn, VkNativeMethod}:
    not_allowed("Lazy tree method '" & method_name & "' is not available on " & $actual.kind)

  var call_args = newSeq[Value](arg_count)
  if has_keyword_args:
    call_args[0] = args[0]
    if arg_count > 1:
      call_args[1] = actual
    for i in 2..<arg_count:
      call_args[i] = args[i]
  else:
    if arg_count > 0:
      call_args[0] = actual
    for i in 1..<arg_count:
      call_args[i] = args[i]

  case meth.callable.kind
  of VkNativeFn:
    return call_native_fn(meth.callable.ref.native_fn, vm, call_args, has_keyword_args)
  of VkNativeMethod:
    return call_native_fn(meth.callable.ref.native_method, vm, call_args, has_keyword_args)
  else:
    not_allowed("Lazy tree method '" & method_name & "' must be native")

proc init_lazy_tree_value_class() =
  if not lazy_tree_value_class.is_nil:
    return

  lazy_tree_value_class = new_class("LazyTreeValue", App.app.object_class.ref.class)

  template def_lazy_delegate(method_name: string, proc_name: untyped) =
    proc proc_name(vm: ptr VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value {.gcsafe.} =
      delegate_lazy_tree_method(vm, args, arg_count, has_keyword_args, method_name)
    lazy_tree_value_class.def_native_method(method_name, proc_name)

  def_lazy_delegate("to_s", lazy_tree_to_s)
  def_lazy_delegate("class", lazy_tree_class)
  def_lazy_delegate("is", lazy_tree_is)
  def_lazy_delegate("iter", lazy_tree_iter)
  def_lazy_delegate("get", lazy_tree_get)
  def_lazy_delegate("set", lazy_tree_set)
  def_lazy_delegate("contains", lazy_tree_contains)
  def_lazy_delegate("has", lazy_tree_has)
  def_lazy_delegate("size", lazy_tree_size)
  def_lazy_delegate("length", lazy_tree_length)
  def_lazy_delegate("keys", lazy_tree_keys)
  def_lazy_delegate("values", lazy_tree_values)
  def_lazy_delegate("each", lazy_tree_each)
  def_lazy_delegate("map", lazy_tree_map)
  def_lazy_delegate("filter", lazy_tree_filter)
  def_lazy_delegate("reduce", lazy_tree_reduce)
  def_lazy_delegate("pairs", lazy_tree_pairs)
  def_lazy_delegate("empty", lazy_tree_empty)
  def_lazy_delegate("clear", lazy_tree_clear)
  def_lazy_delegate("del", lazy_tree_del)
  def_lazy_delegate("merge", lazy_tree_merge)
  def_lazy_delegate("add", lazy_tree_add)
  def_lazy_delegate("append", lazy_tree_append)
  def_lazy_delegate("push", lazy_tree_push)
  def_lazy_delegate("pop", lazy_tree_pop)
  def_lazy_delegate("first", lazy_tree_first)
  def_lazy_delegate("last", lazy_tree_last)
  def_lazy_delegate("slice", lazy_tree_slice)
  def_lazy_delegate("index_of", lazy_tree_index_of)
  def_lazy_delegate("join", lazy_tree_join)
  def_lazy_delegate("take", lazy_tree_take)
  def_lazy_delegate("skip", lazy_tree_skip)
  def_lazy_delegate("find", lazy_tree_find)
  def_lazy_delegate("any", lazy_tree_any)
  def_lazy_delegate("all", lazy_tree_all)
  def_lazy_delegate("zip", lazy_tree_zip)
  def_lazy_delegate("reverse", lazy_tree_reverse)
  def_lazy_delegate("sort", lazy_tree_sort)
  def_lazy_delegate("to_map", lazy_tree_to_map)
  def_lazy_delegate("to_json", lazy_tree_to_json)
  def_lazy_delegate("type", lazy_tree_type)
  def_lazy_delegate("props", lazy_tree_props)
  def_lazy_delegate("children", lazy_tree_children)
  def_lazy_delegate("genetype", lazy_tree_genetype)
  def_lazy_delegate("set_genetype", lazy_tree_set_genetype)

proc delegate_lazy_file_ref_method(vm: ptr VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool, method_name: string): Value {.gcsafe.} =
  if get_positional_count(arg_count, has_keyword_args) < 1:
    not_allowed("Lazy file-ref method requires self")

  let self_value = get_positional_arg(args, 0, has_keyword_args)
  let actual = materialize_lazy_file_ref_value(self_value)
  let actual_class = lazy_tree_class_ref(actual)
  if actual_class == nil:
    not_allowed("Lazy file-ref method dispatch requires a concrete class")

  let meth = actual_class.get_method(method_name)
  if meth == nil or meth.callable.kind notin {VkNativeFn, VkNativeMethod}:
    not_allowed("Lazy file-ref method '" & method_name & "' is not available on " & $actual.kind)

  var call_args = newSeq[Value](arg_count)
  if has_keyword_args:
    call_args[0] = args[0]
    if arg_count > 1:
      call_args[1] = actual
    for i in 2..<arg_count:
      call_args[i] = args[i]
  else:
    if arg_count > 0:
      call_args[0] = actual
    for i in 1..<arg_count:
      call_args[i] = args[i]

  case meth.callable.kind
  of VkNativeFn:
    return call_native_fn(meth.callable.ref.native_fn, vm, call_args, has_keyword_args)
  of VkNativeMethod:
    return call_native_fn(meth.callable.ref.native_method, vm, call_args, has_keyword_args)
  else:
    not_allowed("Lazy file-ref method '" & method_name & "' must be native")

proc init_lazy_file_ref_value_class() =
  if not lazy_file_ref_value_class.is_nil:
    return

  lazy_file_ref_value_class = new_class("LazyFileRefValue", App.app.object_class.ref.class)

  template def_lazy_file_delegate(method_name: string, proc_name: untyped) =
    proc proc_name(vm: ptr VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value {.gcsafe.} =
      delegate_lazy_file_ref_method(vm, args, arg_count, has_keyword_args, method_name)
    lazy_file_ref_value_class.def_native_method(method_name, proc_name)

  def_lazy_file_delegate("to_s", lazy_file_to_s)
  def_lazy_file_delegate("class", lazy_file_class)
  def_lazy_file_delegate("is", lazy_file_is)
  def_lazy_file_delegate("iter", lazy_file_iter)
  def_lazy_file_delegate("get", lazy_file_get)
  def_lazy_file_delegate("contains", lazy_file_contains)
  def_lazy_file_delegate("has", lazy_file_has)
  def_lazy_file_delegate("size", lazy_file_size)
  def_lazy_file_delegate("length", lazy_file_length)
  def_lazy_file_delegate("keys", lazy_file_keys)
  def_lazy_file_delegate("values", lazy_file_values)
  def_lazy_file_delegate("each", lazy_file_each)
  def_lazy_file_delegate("map", lazy_file_map)
  def_lazy_file_delegate("filter", lazy_file_filter)
  def_lazy_file_delegate("reduce", lazy_file_reduce)
  def_lazy_file_delegate("pairs", lazy_file_pairs)
  def_lazy_file_delegate("empty", lazy_file_empty)
  def_lazy_file_delegate("first", lazy_file_first)
  def_lazy_file_delegate("last", lazy_file_last)
  def_lazy_file_delegate("slice", lazy_file_slice)
  def_lazy_file_delegate("index_of", lazy_file_index_of)
  def_lazy_file_delegate("join", lazy_file_join)
  def_lazy_file_delegate("take", lazy_file_take)
  def_lazy_file_delegate("skip", lazy_file_skip)
  def_lazy_file_delegate("find", lazy_file_find)
  def_lazy_file_delegate("any", lazy_file_any)
  def_lazy_file_delegate("all", lazy_file_all)
  def_lazy_file_delegate("zip", lazy_file_zip)
  def_lazy_file_delegate("reverse", lazy_file_reverse)
  def_lazy_file_delegate("to_map", lazy_file_to_map)
  def_lazy_file_delegate("to_json", lazy_file_to_json)
  def_lazy_file_delegate("type", lazy_file_type)
  def_lazy_file_delegate("props", lazy_file_props)
  def_lazy_file_delegate("children", lazy_file_children)
  def_lazy_file_delegate("genetype", lazy_file_genetype)

proc vm_serialize(vm: ptr VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value {.gcsafe.} =
  {.cast(gcsafe).}:
    if arg_count != 1:
      not_allowed("serialize expects 1 argument")

    let value = materialize_custom_deep(get_positional_arg(args, 0, has_keyword_args))
    return value_to_serialized_text(value).to_value()

proc vm_deserialize(vm: ptr VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value {.gcsafe.} =
  {.cast(gcsafe).}:
    if arg_count != 1:
      not_allowed("deserialize expects 1 argument")

    let s = get_positional_arg(args, 0, has_keyword_args).str
    return deserialize(s)

proc vm_read_file_with_kind(vm: ptr VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int,
                            has_keyword_args: bool, ref_kind: string): Value {.gcsafe.} =
  discard vm
  {.cast(gcsafe).}:
    let positional_count = get_positional_count(arg_count, has_keyword_args)
    if positional_count != 1:
      filesystem_read_error(ref_kind, nil, "", "", "wrong arity",
                            "expected 1 path argument, got " & $positional_count)

    let path_arg = get_positional_arg(args, 0, has_keyword_args)
    let target_path = if path_arg.kind == VkString: path_arg.str else: $path_arg.kind

    if path_arg.kind != VkString:
      filesystem_read_error(ref_kind, nil, target_path, "", "non-string path",
                            "path argument must be a string, got " & $path_arg.kind)

    let lazy = read_file_lazy_from_keyword_args(args, has_keyword_args, ref_kind, nil, target_path)
    if lazy:
      let stable_target = resolve_filesystem_read_target(nil, path_arg.str, ref_kind)
      make_lazy_file_ref_value(stable_target, nil, ref_kind)
    else:
      read_file_value(path_arg.str, nil, ref_kind)

proc vm_read_file(vm: ptr VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int,
                  has_keyword_args: bool): Value {.gcsafe, nimcall.} =
  vm_read_file_with_kind(vm, args, arg_count, has_keyword_args, "read_file")

proc vm_read(vm: ptr VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int,
             has_keyword_args: bool): Value {.gcsafe, nimcall.} =
  vm_read_file_with_kind(vm, args, arg_count, has_keyword_args, "read")

proc vm_read_dir(vm: ptr VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int,
                 has_keyword_args: bool): Value {.gcsafe, nimcall.} =
  discard vm
  {.cast(gcsafe).}:
    let positional_count = get_positional_count(arg_count, has_keyword_args)
    if positional_count != 1:
      filesystem_read_error("read_dir", nil, "", "", "wrong arity",
                            "expected 1 path argument, got " & $positional_count)

    let path_arg = get_positional_arg(args, 0, has_keyword_args)
    let target_path = if path_arg.kind == VkString: path_arg.str else: $path_arg.kind
    if path_arg.kind != VkString:
      filesystem_read_error("read_dir", nil, target_path, "", "non-string path",
                            "path argument must be a string, got " & $path_arg.kind)

    let options = read_dir_options_from_keyword_args(args, has_keyword_args, "read_dir", nil, target_path)
    read_dir_value(path_arg.str, options, nil, "read_dir")

proc vm_write_macro(vm: ptr VirtualMachine, gene_value: Value, caller_frame: Frame): Value {.gcsafe.} =
  {.cast(gcsafe).}:
    if gene_value.kind != VkGene:
      filesystem_write_error("", "invalid invocation", "write must be called as a Gene form")

    let positional_count = gene_value.gene.children.len
    if positional_count != 2:
      filesystem_write_error("", "wrong arity", "expected 2 arguments, got " & $positional_count)

    let path_arg = eval_in_caller_context(vm, gene_value.gene.children[0], caller_frame)
    let target_path = if path_arg.kind == VkString: path_arg.str else: $path_arg.kind
    if path_arg.kind != VkString:
      filesystem_write_error(target_path, "non-string path",
                             "path argument must be a string, got " & $path_arg.kind)

    let options = build_write_options(gene_value.gene.props, target_path)
    let value = eval_in_caller_context(vm, gene_value.gene.children[1], caller_frame)
    if options.externalize_selectors.len > 0:
      write_externalized_value_file(path_arg.str, value, options)
    else:
      write_value_file(path_arg.str, value)
    NIL

proc vm_write_tree_macro(vm: ptr VirtualMachine, gene_value: Value, caller_frame: Frame): Value {.gcsafe.} =
  {.cast(gcsafe).}:
    when defined(gene_wasm):
      not_allowed("write_tree is not supported in gene_wasm")
    else:
      if gene_value.kind != VkGene or gene_value.gene.children.len != 2:
        not_allowed("write_tree expects 2 arguments")

      let path_arg = eval_in_caller_context(vm, gene_value.gene.children[0], caller_frame)
      if path_arg.kind != VkString:
        not_allowed("write_tree expects a string path")

      let value = eval_in_caller_context(vm, gene_value.gene.children[1], caller_frame)
      let separate_value = gene_value.gene.props.getOrDefault("separate".to_key(), NIL)
      let options = build_tree_write_options(separate_value)
      write_tree_root(path_arg.str, value, options)
      NIL

proc vm_read_tree_macro(vm: ptr VirtualMachine, gene_value: Value, caller_frame: Frame): Value {.gcsafe.} =
  {.cast(gcsafe).}:
    when defined(gene_wasm):
      not_allowed("read_tree is not supported in gene_wasm")
    else:
      if gene_value.kind != VkGene or gene_value.gene.children.len != 1:
        not_allowed("read_tree expects 1 argument")

      let path_arg = eval_in_caller_context(vm, gene_value.gene.children[0], caller_frame)
      if path_arg.kind != VkString:
        not_allowed("read_tree expects a string path")

      let lazy_value = gene_value.gene.props.getOrDefault("lazy".to_key(), NIL)
      let options = build_tree_read_options(lazy_value)
      read_tree_root_path(path_arg.str, options)

# Initialize the serdes namespace
proc init_serdes*() =
  init_lazy_tree_value_class()
  init_lazy_file_ref_value_class()
  tag_stdlib_serialization_origins()
  let serdes_ns = new_namespace("serdes")
  serdes_ns["serialize".to_key()] = NativeFn(vm_serialize).to_value()
  serdes_ns["deserialize".to_key()] = NativeFn(vm_deserialize).to_value()
  serdes_ns["read_file".to_key()] = NativeFn(vm_read_file).to_value()
  serdes_ns["read".to_key()] = NativeFn(vm_read).to_value()
  serdes_ns["read_dir".to_key()] = NativeFn(vm_read_dir).to_value()
  var write_ref = new_ref(VkNativeMacro)
  write_ref.native_macro = vm_write_macro
  serdes_ns["write".to_key()] = write_ref.to_ref_value()
  var write_tree_ref = new_ref(VkNativeMacro)
  write_tree_ref.native_macro = vm_write_tree_macro
  serdes_ns["write_tree".to_key()] = write_tree_ref.to_ref_value()
  var read_tree_ref = new_ref(VkNativeMacro)
  read_tree_ref.native_macro = vm_read_tree_macro
  serdes_ns["read_tree".to_key()] = read_tree_ref.to_ref_value()
  App.app.gene_ns.ref.ns["serdes".to_key()] = serdes_ns.to_value()
  # Retag gene after attaching gene/serdes so that the new namespace itself
  # also gets a canonical stdlib path.
  tag_namespace_serialization_origins(App.app.gene_ns.ref.ns, "", "gene")
