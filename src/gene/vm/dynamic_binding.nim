## Dynamic library binding support.
## Included from vm.nim — shares its scope.

when not defined(gene_wasm):
  import dynlib

type
  DynLibraryValueData = ref object of CustomValue
    handle: LibHandle
    requested_path: string
    resolved_path: string

  DynSymbolValueData = ref object of CustomValue
    library_value: Value
    handle: LibHandle
    library_path: string
    symbol_name: string
    address: pointer

  DynPointerValueData = ref object of CustomValue
    address: pointer

proc dyn_pointer_materialize(data: CustomValue): Value {.gcsafe.} =
  let pointer_data = DynPointerValueData(data)
  pointer_data.address.to_value()

proc new_dyn_pointer_value(custom_class: Class, address: pointer): Value =
  let data = DynPointerValueData(address: address)
  data.materialize_hook = dyn_pointer_materialize
  new_custom_value(custom_class, data)

proc dyn_pointer_address(value: Value): tuple[valid: bool, address: pointer] =
  if value.kind == VkPointer:
    return (true, value.to_pointer())
  if value.kind == VkCustom and value.ref != nil and value.ref.custom_data != nil and
      (value.ref.custom_data of DynPointerValueData):
    return (true, DynPointerValueData(value.ref.custom_data).address)
  (false, nil)

when not defined(gene_wasm):
  proc dyn_library_finalize(data: CustomValue) {.gcsafe, raises: [].} =
    let lib = DynLibraryValueData(data)
    if lib.handle != nil:
      {.cast(gcsafe).}:
        unloadLib(lib.handle)
      lib.handle = nil

  type
    CdeclI64Fn0 = proc(): int64 {.cdecl, gcsafe.}
    CdeclI64Fn1 = proc(a0: int64): int64 {.cdecl, gcsafe.}
    CdeclI64Fn2 = proc(a0, a1: int64): int64 {.cdecl, gcsafe.}
    CdeclI64Fn3 = proc(a0, a1, a2: int64): int64 {.cdecl, gcsafe.}
    CdeclI64Fn4 = proc(a0, a1, a2, a3: int64): int64 {.cdecl, gcsafe.}
    CdeclI64Fn5 = proc(a0, a1, a2, a3, a4: int64): int64 {.cdecl, gcsafe.}
    CdeclI64Fn6 = proc(a0, a1, a2, a3, a4, a5: int64): int64 {.cdecl, gcsafe.}
    CdeclI64Fn7 = proc(a0, a1, a2, a3, a4, a5, a6: int64): int64 {.cdecl, gcsafe.}

    CdeclVoidFn0 = proc() {.cdecl, gcsafe.}
    CdeclVoidFn1 = proc(a0: int64) {.cdecl, gcsafe.}
    CdeclVoidFn2 = proc(a0, a1: int64) {.cdecl, gcsafe.}
    CdeclVoidFn3 = proc(a0, a1, a2: int64) {.cdecl, gcsafe.}
    CdeclVoidFn4 = proc(a0, a1, a2, a3: int64) {.cdecl, gcsafe.}
    CdeclVoidFn5 = proc(a0, a1, a2, a3, a4: int64) {.cdecl, gcsafe.}
    CdeclVoidFn6 = proc(a0, a1, a2, a3, a4, a5: int64) {.cdecl, gcsafe.}
    CdeclVoidFn7 = proc(a0, a1, a2, a3, a4, a5, a6: int64) {.cdecl, gcsafe.}

var dyn_library_class: Class = nil
var dyn_symbol_class: Class = nil

proc call_dynamic_native_binding*(binding: DynamicNativeBinding,
                                  vm: ptr VirtualMachine,
                                  args: ptr UncheckedArray[Value],
                                  arg_count: int,
                                  has_keyword_args: bool): Value {.gcsafe.}

proc dynamic_native_direct_call(vm: ptr VirtualMachine,
                                args: ptr UncheckedArray[Value],
                                arg_count: int,
                                has_keyword_args: bool): Value {.gcsafe.} =
  discard vm
  discard args
  discard arg_count
  discard has_keyword_args
  not_allowed("dynamic native bindings must be called through their VkNativeFn value")
  NIL

proc ensure_dyn_namespace(): Namespace =
  if App == NIL or App.kind != VkApplication:
    not_allowed("$dyn namespace requires an initialized app")
  let key = "$dyn".to_key()
  var ns_value =
    if App.app.global_ns.kind == VkNamespace:
      App.app.global_ns.ref.ns.members.getOrDefault(key, NIL)
    else:
      NIL
  if ns_value.kind != VkNamespace:
    let ns = new_namespace(App.app.global_ns.ref.ns, "$dyn")
    ns_value = ns.to_value()
    App.app.global_ns.ref.ns[key] = ns_value
  if App.app.gene_ns.kind == VkNamespace:
    App.app.gene_ns.ref.ns[key] = ns_value
  ns_value.ref.ns

proc dyn_class_value(cls: Class): Value {.gcsafe.} =
  {.cast(gcsafe).}:
    let r = new_ref(VkClass)
    r.class = cls
    r.to_ref_value()

proc ensure_dyn_classes(): Namespace =
  result = ensure_dyn_namespace()
  let object_class =
    if App != NIL and App.kind == VkApplication and App.app.object_class.kind == VkClass:
      App.app.object_class.ref.class
    else:
      nil
  if dyn_library_class == nil:
    dyn_library_class = new_class("DynLibrary")
    dyn_library_class.parent = object_class
    result["Library".to_key()] = dyn_class_value(dyn_library_class)
  if dyn_symbol_class == nil:
    dyn_symbol_class = new_class("DynSymbol")
    dyn_symbol_class.parent = object_class
    result["Symbol".to_key()] = dyn_class_value(dyn_symbol_class)

proc release_dyn_binding_scope(scope: Scope) {.gcsafe, raises: [].} =
  if scope == nil:
    return
  {.cast(gcsafe).}:
    try:
      scope.free()
    except CatchableError:
      discard

proc dyn_has_library_extension(path: string): bool =
  path.endsWith(".so") or path.endsWith(".dylib") or path.endsWith(".dll")

proc add_candidate(candidates: var seq[string], path: string) =
  if path.len == 0:
    return
  for candidate in candidates:
    if candidate == path:
      return
  candidates.add(path)

proc dyn_library_candidates(path: string): seq[string] =
  add_candidate(result, path)
  if dyn_has_library_extension(path):
    return
  let parts = splitFile(path)
  let dir = parts.dir
  let name = parts.name
  proc candidate(file_name: string): string =
    if dir.len > 0: dir / file_name else: file_name
  when defined(windows):
    add_candidate(result, candidate(name & ".dll"))
    if not name.startsWith("lib"):
      add_candidate(result, candidate("lib" & name & ".dll"))
  elif defined(macosx):
    add_candidate(result, candidate(name & ".dylib"))
    if not name.startsWith("lib"):
      add_candidate(result, candidate("lib" & name & ".dylib"))
  else:
    add_candidate(result, candidate(name & ".so"))
    if not name.startsWith("lib"):
      add_candidate(result, candidate("lib" & name & ".so"))

proc dyn_library_data(value: Value, context: string): DynLibraryValueData =
  if value.kind != VkCustom or value.ref == nil or value.ref.custom_data == nil or
      not (value.ref.custom_data of DynLibraryValueData):
    not_allowed(context & " expects a dynamic library handle, got " & $value.kind)
  DynLibraryValueData(value.ref.custom_data)

proc dyn_symbol_data(value: Value, context: string): DynSymbolValueData =
  if value.kind != VkCustom or value.ref == nil or value.ref.custom_data == nil or
      not (value.ref.custom_data of DynSymbolValueData):
    not_allowed(context & " expects a dynamic symbol")
  DynSymbolValueData(value.ref.custom_data)

proc is_dynamic_symbol_value*(value: Value): bool =
  value.kind == VkCustom and value.ref != nil and value.ref.custom_data != nil and
    (value.ref.custom_data of DynSymbolValueData)

proc dyn_resolve_scope_value(scope: Scope, key: Key,
                             tracker_override: ScopeTracker = nil): tuple[found: bool, value: Value] =
  let tracker =
    if tracker_override != nil: tracker_override
    elif scope != nil: scope.tracker
    else: nil
  if scope == nil or tracker == nil:
    return (false, NIL)
  let found = tracker.locate(key)
  if found.local_index < 0:
    return (false, NIL)
  var target_scope = scope
  var parent_index = found.parent_index
  while parent_index > 0 and target_scope != nil:
    parent_index.dec()
    target_scope = target_scope.parent
  if target_scope != nil and found.local_index < target_scope.members.len:
    return (true, target_scope.members[found.local_index])
  (false, NIL)

proc dyn_resolve_complex(vm: ptr VirtualMachine, target: Value,
                         context: string, fallback_ns: Namespace): Value =
  if target.ref == nil or target.ref.csymbol.len == 0:
    not_allowed(context & " target path is empty")
  var ns =
    if vm != nil and vm.frame != nil and vm.frame.ns != nil: vm.frame.ns
    else: fallback_ns
  for i in 0..<target.ref.csymbol.len - 1:
    let part = target.ref.csymbol[i]
    if part == "":
      continue
    if part == "$ns" and i == 0:
      continue
    let resolved = resolve_namespace_value(ns, part.to_key())
    if not resolved.found or resolved.value.kind != VkNamespace:
      not_allowed(context & " target namespace '" & part & "' is not defined")
    ns = resolved.value.ref.ns
  let final_name = target.ref.csymbol[^1]
  let resolved = resolve_namespace_value(ns, final_name.to_key())
  if not resolved.found:
    not_allowed(context & " target '" & final_name & "' is not defined")
  resolved.value

proc dyn_resolve_name(vm: ptr VirtualMachine, name: string, context: string,
                      fallback_ns: Namespace, fallback_scope: Scope,
                      fallback_tracker: ScopeTracker = nil): Value =
  if vm != nil:
    let resolved = vm.resolve_local_or_namespace(name)
    if resolved.found:
      return resolved.value
  let scope_resolved = dyn_resolve_scope_value(fallback_scope, name.to_key(),
    fallback_tracker)
  if scope_resolved.found:
    return scope_resolved.value
  if fallback_ns != nil:
    let ns_resolved = resolve_namespace_value(fallback_ns, name.to_key())
    if ns_resolved.found:
      return ns_resolved.value
  if vm != nil and vm.thread_local_ns != nil:
    let thread_resolved = resolve_namespace_value(vm.thread_local_ns, name.to_key())
    if thread_resolved.found:
      return thread_resolved.value
  not_allowed(context & " target '" & name & "' is not defined")
  NIL

proc dyn_load_native(vm: ptr VirtualMachine, args: ptr UncheckedArray[Value],
                     arg_count: int, has_keyword_args: bool): Value {.gcsafe.}
proc dyn_find_native(vm: ptr VirtualMachine, args: ptr UncheckedArray[Value],
                     arg_count: int, has_keyword_args: bool): Value {.gcsafe.}

proc dyn_target_head_name(expr: Value): string =
  if expr.kind != VkGene:
    return ""
  let head =
    if not expr.gene.type.is_nil():
      expr.gene.type
    elif expr.gene.children.len > 0:
      expr.gene.children[0]
    else:
      NIL
  case head.kind
  of VkSymbol, VkString:
    head.str
  of VkComplexSymbol:
    if head.ref != nil: head.ref.csymbol.join("/") else: ""
  of VkNativeFn:
    if head.ref != nil and head.ref.native_fn == dyn_load_native:
      "$dyn/load"
    elif head.ref != nil and head.ref.native_fn == dyn_find_native:
      "$dyn/find"
    else:
      ""
  else:
    ""

proc dyn_is_supported_target_expr(expr: Value): bool =
  let head = dyn_target_head_name(expr)
  head == "$dyn/load" or head == "$dyn/find"

proc dyn_is_erased_load_expr(expr: Value): bool =
  expr.kind == VkGene and expr.gene.type.kind == VkVoid and
    expr.gene.children.len == 1 and
    expr.gene.children[0].kind in {VkString, VkSymbol}

proc dyn_load_path(vm: ptr VirtualMachine, path_arg: Value): Value =
  var call_args: array[1, Value]
  call_args[0] = path_arg
  dyn_load_native(vm, cast[ptr UncheckedArray[Value]](addr call_args[0]), 1, false)

proc dyn_eval_target_expr(vm: ptr VirtualMachine, expr: Value, context: string,
                          fallback_ns: Namespace, fallback_scope: Scope,
                          fallback_tracker: ScopeTracker = nil): Value

proc dyn_materialize_resolved_target(vm: ptr VirtualMachine, value: Value,
                                     context: string, fallback_ns: Namespace,
                                     fallback_scope: Scope,
                                     fallback_tracker: ScopeTracker = nil): Value =
  if dyn_is_supported_target_expr(value):
    return dyn_eval_target_expr(vm, value, context, fallback_ns, fallback_scope,
      fallback_tracker)
  if dyn_is_erased_load_expr(value):
    return dyn_load_path(vm, value.gene.children[0])
  value

proc dyn_eval_target_expr(vm: ptr VirtualMachine, expr: Value, context: string,
                          fallback_ns: Namespace, fallback_scope: Scope,
                          fallback_tracker: ScopeTracker = nil): Value =
  case expr.kind
  of VkGene:
    let has_gene_type = not expr.gene.type.is_nil()
    if not has_gene_type and expr.gene.children.len == 0:
      not_allowed(context & " target expression is empty")
    let op_expr =
      if has_gene_type: expr.gene.type
      else: expr.gene.children[0]
    let arg_start = if has_gene_type: 0 else: 1
    let callable =
      case op_expr.kind
      of VkSymbol, VkString:
        dyn_resolve_name(vm, op_expr.str, context, fallback_ns, fallback_scope,
          fallback_tracker)
      of VkComplexSymbol:
        dyn_resolve_complex(vm, op_expr, context, fallback_ns)
      else:
        dyn_eval_target_expr(vm, op_expr, context, fallback_ns, fallback_scope,
          fallback_tracker)
    if callable.kind != VkNativeFn:
      not_allowed(context & " target expression must call a native function, got " & $callable.kind)
    var call_args = newSeq[Value](expr.gene.children.len - arg_start)
    for i in arg_start..<expr.gene.children.len:
      call_args[i - arg_start] = dyn_eval_target_expr(vm, expr.gene.children[i],
        context, fallback_ns, fallback_scope, fallback_tracker)
    if expr.gene.props.len == 0:
      return call_native_value(callable, vm, call_args)
    var native_args = newSeq[Value](call_args.len + 1)
    let kw_map = new_map_value()
    for k, v in expr.gene.props:
      map_data(kw_map)[k] = dyn_eval_target_expr(vm, v, context, fallback_ns,
        fallback_scope, fallback_tracker)
    native_args[0] = kw_map
    for i, arg in call_args:
      native_args[i + 1] = arg
    call_native_value(callable, vm, native_args, true)
  of VkSymbol:
    if vm != nil:
      let resolved = vm.resolve_local_or_namespace(expr.str)
      if resolved.found:
        return dyn_materialize_resolved_target(vm, resolved.value, context,
          fallback_ns, fallback_scope, fallback_tracker)
    let scope_resolved = dyn_resolve_scope_value(fallback_scope, expr.str.to_key(),
      fallback_tracker)
    if scope_resolved.found:
      return dyn_materialize_resolved_target(vm, scope_resolved.value, context,
        fallback_ns, fallback_scope, fallback_tracker)
    if fallback_ns != nil:
      let ns_resolved = resolve_namespace_value(fallback_ns, expr.str.to_key())
      if ns_resolved.found:
        return dyn_materialize_resolved_target(vm, ns_resolved.value, context,
          fallback_ns, fallback_scope, fallback_tracker)
    if vm != nil and vm.thread_local_ns != nil:
      let thread_resolved = resolve_namespace_value(vm.thread_local_ns, expr.str.to_key())
      if thread_resolved.found:
        return dyn_materialize_resolved_target(vm, thread_resolved.value, context,
          fallback_ns, fallback_scope, fallback_tracker)
    expr
  of VkComplexSymbol:
    dyn_resolve_complex(vm, expr, context, fallback_ns)
  else:
    expr

proc dyn_load_native(vm: ptr VirtualMachine, args: ptr UncheckedArray[Value],
                     arg_count: int, has_keyword_args: bool): Value {.gcsafe.} =
  discard vm
  when defined(gene_wasm):
    discard args
    discard arg_count
    discard has_keyword_args
    raise_wasm_unsupported("dynamic_library_binding")
  else:
    if get_positional_count(arg_count, has_keyword_args) != 1:
      not_allowed("$dyn/load expects exactly one path")
    let path_arg = get_positional_arg(args, 0, has_keyword_args)
    if path_arg.kind notin {VkString, VkSymbol}:
      not_allowed("$dyn/load expects a string path")
    let candidates = dyn_library_candidates(path_arg.str)
    for candidate in candidates:
      let handle = loadLib(candidate)
      if not handle.isNil:
        {.cast(gcsafe).}:
          let ns = ensure_dyn_classes()
          discard ns
          let data = DynLibraryValueData(
            handle: handle,
            requested_path: path_arg.str,
            resolved_path: candidate
          )
          data.finalize_hook = dyn_library_finalize
          return new_custom_value(dyn_library_class, data)
    not_allowed("[GENE.DYN.LOAD_FAILED] Failed to load dynamic library '" &
      path_arg.str & "'; tried: " & candidates.join(", "))

proc dyn_find_native(vm: ptr VirtualMachine, args: ptr UncheckedArray[Value],
                     arg_count: int, has_keyword_args: bool): Value {.gcsafe.} =
  discard vm
  when defined(gene_wasm):
    discard args
    discard arg_count
    discard has_keyword_args
    raise_wasm_unsupported("dynamic_library_binding")
  else:
    if get_positional_count(arg_count, has_keyword_args) != 2:
      not_allowed("$dyn/find expects a library handle and symbol name")
    let lib_value = get_positional_arg(args, 0, has_keyword_args)
    let symbol_arg = get_positional_arg(args, 1, has_keyword_args)
    if symbol_arg.kind notin {VkString, VkSymbol}:
      not_allowed("$dyn/find expects a string symbol name")
    let lib = dyn_library_data(lib_value, "$dyn/find")
    let symbol_name = symbol_arg.str
    let address = lib.handle.symAddr(symbol_name.cstring)
    if address == nil:
      not_allowed("[GENE.DYN.SYMBOL_MISSING] Symbol '" & symbol_name &
        "' not found in dynamic library '" & lib.resolved_path & "'")
    {.cast(gcsafe).}:
      let ns = ensure_dyn_classes()
      discard ns
      new_custom_value(dyn_symbol_class, DynSymbolValueData(
        library_value: lib_value,
        handle: lib.handle,
        library_path: lib.resolved_path,
        symbol_name: symbol_name,
        address: address
      ))

proc init_dynamic_binding_namespace() =
  let ns = ensure_dyn_namespace()
  let load_ref = new_ref(VkNativeFn)
  load_ref.native_fn = dyn_load_native
  ns["load".to_key()] = load_ref.to_ref_value()
  let find_ref = new_ref(VkNativeFn)
  find_ref.native_fn = dyn_find_native
  ns["find".to_key()] = find_ref.to_ref_value()

proc dyn_builtin_id(sig: NativeSignature, type_id: TypeId): TypeId =
  if type_id in [
    BUILTIN_TYPE_INT_ID, BUILTIN_TYPE_BOOL_ID, BUILTIN_TYPE_STRING_ID,
    BUILTIN_TYPE_POINTER_ID, BUILTIN_TYPE_VOID_ID
  ]:
    return type_id
  if sig != nil and type_id >= 0 and type_id.int < sig.type_descriptors.len:
    let desc = sig.type_descriptors[type_id.int]
    if desc.kind == TdkNamed:
      return lookup_builtin_type(desc.name)
  NO_TYPE_ID

proc dyn_type_name(sig: NativeSignature, type_id: TypeId): string =
  if sig != nil and sig.type_descriptors.len > 0 and type_id >= 0 and
      type_id.int < sig.type_descriptors.len:
    return type_desc_to_string(type_id, sig.type_descriptors)
  $type_id

proc dyn_arg_error(binding: DynamicNativeBinding, index: int, expected: string,
                   actual: Value): string =
  "dynamic native " & binding.symbol_name & " argument " & $(index + 1) &
    " expected " & expected & ", got " & runtime_type_name(actual)

proc dyn_store_cstring(value: Value, slots: var array[7, int64],
                       string_allocs: var array[7, pointer], index: int,
                       binding: DynamicNativeBinding) =
  if value.kind != VkString:
    not_allowed(dyn_arg_error(binding, index, "String", value))
  let size = value.str.len + 1
  let mem = alloc0(size)
  if value.str.len > 0:
    copyMem(mem, value.str.cstring, value.str.len)
  string_allocs[index] = mem
  slots[index] = cast[int64](mem)

proc dyn_store_arg(value: Value, type_id: TypeId, sig: NativeSignature,
                   slots: var array[7, int64],
                   string_allocs: var array[7, pointer], index: int,
                   binding: DynamicNativeBinding) =
  case dyn_builtin_id(sig, type_id)
  of BUILTIN_TYPE_INT_ID:
    if value.kind != VkInt:
      not_allowed(dyn_arg_error(binding, index, "Int", value))
    slots[index] = value.to_int()
  of BUILTIN_TYPE_BOOL_ID:
    if value.kind != VkBool:
      not_allowed(dyn_arg_error(binding, index, "Bool", value))
    slots[index] = if value == TRUE: 1'i64 else: 0'i64
  of BUILTIN_TYPE_STRING_ID:
    dyn_store_cstring(value, slots, string_allocs, index, binding)
  of BUILTIN_TYPE_POINTER_ID:
    let pointer_arg = dyn_pointer_address(value)
    if value == NIL:
      slots[index] = 0
    elif pointer_arg.valid:
      slots[index] = cast[int64](pointer_arg.address)
    else:
      not_allowed(dyn_arg_error(binding, index, "Pointer", value))
  else:
    not_allowed("dynamic native " & binding.symbol_name &
      " uses unsupported parameter type " & dyn_type_name(sig, type_id))

proc dyn_call_i64(binding: DynamicNativeBinding, slots: array[7, int64],
                  count: int): int64 {.gcsafe.} =
  let sym = binding.symbol
  case count
  of 0: cast[CdeclI64Fn0](sym)()
  of 1: cast[CdeclI64Fn1](sym)(slots[0])
  of 2: cast[CdeclI64Fn2](sym)(slots[0], slots[1])
  of 3: cast[CdeclI64Fn3](sym)(slots[0], slots[1], slots[2])
  of 4: cast[CdeclI64Fn4](sym)(slots[0], slots[1], slots[2], slots[3])
  of 5: cast[CdeclI64Fn5](sym)(slots[0], slots[1], slots[2], slots[3], slots[4])
  of 6: cast[CdeclI64Fn6](sym)(slots[0], slots[1], slots[2], slots[3], slots[4], slots[5])
  of 7: cast[CdeclI64Fn7](sym)(slots[0], slots[1], slots[2], slots[3], slots[4], slots[5], slots[6])
  else:
    not_allowed("dynamic native " & binding.symbol_name & " exceeds 7 arguments")
    0

proc dyn_call_void(binding: DynamicNativeBinding, slots: array[7, int64],
                   count: int) {.gcsafe.} =
  let sym = binding.symbol
  case count
  of 0: cast[CdeclVoidFn0](sym)()
  of 1: cast[CdeclVoidFn1](sym)(slots[0])
  of 2: cast[CdeclVoidFn2](sym)(slots[0], slots[1])
  of 3: cast[CdeclVoidFn3](sym)(slots[0], slots[1], slots[2])
  of 4: cast[CdeclVoidFn4](sym)(slots[0], slots[1], slots[2], slots[3])
  of 5: cast[CdeclVoidFn5](sym)(slots[0], slots[1], slots[2], slots[3], slots[4])
  of 6: cast[CdeclVoidFn6](sym)(slots[0], slots[1], slots[2], slots[3], slots[4], slots[5])
  of 7: cast[CdeclVoidFn7](sym)(slots[0], slots[1], slots[2], slots[3], slots[4], slots[5], slots[6])
  else:
    not_allowed("dynamic native " & binding.symbol_name & " exceeds 7 arguments")

proc dynamic_return_value(binding: DynamicNativeBinding, sig: NativeSignature,
                          raw: int64): Value =
  case dyn_builtin_id(sig, sig.return_type_id)
  of BUILTIN_TYPE_INT_ID:
    raw.to_value()
  of BUILTIN_TYPE_BOOL_ID:
    ((raw and 0xFF'i64) != 0'i64).to_value()
  of BUILTIN_TYPE_STRING_ID:
    let p = cast[cstring](raw)
    if p == nil: NIL else: ($p).to_value()
  of BUILTIN_TYPE_POINTER_ID:
    let address = cast[pointer](raw)
    if binding.result_class != nil:
      new_dyn_pointer_value(binding.result_class, address)
    else:
      address.to_value()
  of BUILTIN_TYPE_VOID_ID:
    VOID
  else:
    not_allowed("dynamic native " & binding.symbol_name &
      " uses unsupported return type " & dyn_type_name(sig, sig.return_type_id))
    NIL

proc call_dynamic_native_binding*(binding: DynamicNativeBinding,
                                  vm: ptr VirtualMachine,
                                  args: ptr UncheckedArray[Value],
                                  arg_count: int,
                                  has_keyword_args: bool): Value {.gcsafe.} =
  if binding == nil:
    not_allowed("dynamic native binding is missing a symbol")
  if binding.symbol == nil and binding.target_expr != NIL:
    {.cast(gcsafe).}:
      let symbol_value = dyn_eval_target_expr(vm, binding.target_expr,
        binding.target_context, binding.target_ns, binding.target_scope,
        binding.target_tracker)
      let symbol = dyn_symbol_data(symbol_value, binding.target_context)
      binding.handle = symbol.handle
      binding.handle_value = symbol.library_value
      binding.library_path = symbol.library_path
      binding.symbol_name = symbol.symbol_name
      binding.symbol = symbol.address
  if binding.symbol == nil:
    not_allowed("dynamic native binding is missing a symbol")
  let sig = binding.sig
  if sig == nil:
    not_allowed("dynamic native " & binding.symbol_name & " is missing a signature")
  {.cast(gcsafe).}:
    ensure_dynamic_native_signature_supported(sig, "dynamic native " & binding.symbol_name)
    enforce_native_signature_presence(binding.fn, vm, sig)
    validate_native_call_args(vm, sig, args, arg_count, has_keyword_args)

  var slots: array[7, int64]
  var string_allocs: array[7, pointer]
  defer:
    for p in string_allocs:
      if p != nil:
        dealloc(p)

  let keyword_offset = if has_keyword_args: 1 else: 0
  var c_index = 0
  if sig.receives_self:
    if arg_count <= keyword_offset:
      not_allowed("dynamic native " & binding.symbol_name & " expects receiver")
    dyn_store_arg(args[keyword_offset], BUILTIN_TYPE_POINTER_ID, sig,
      slots, string_allocs, c_index, binding)
    c_index.inc()

  for i, param in sig.params:
    dyn_store_arg(args[keyword_offset + (if sig.receives_self: 1 else: 0) + i],
      param.type_id, sig, slots, string_allocs, c_index, binding)
    c_index.inc()

  if dyn_builtin_id(sig, sig.return_type_id) == BUILTIN_TYPE_VOID_ID:
    dyn_call_void(binding, slots, c_index)
    return VOID
  dynamic_return_value(binding, sig, dyn_call_i64(binding, slots, c_index))

proc make_dynamic_native_value*(symbol_value: Value, sig: NativeSignature,
                                abi: string, context: string): Value =
  let symbol = dyn_symbol_data(symbol_value, context)
  let normalized_abi = if abi.len == 0: "cdecl" else: abi.strip().toLowerAscii()
  if normalized_abi != "cdecl":
    not_allowed(context & " only supports ^abi \"cdecl\" in v1")
  if sig == nil:
    not_allowed(context & " requires a concrete signature")
  sig.abi = normalized_abi
  ensure_dynamic_native_signature_supported(sig, context)
  let binding = DynamicNativeBinding(
    handle: symbol.handle,
    handle_value: symbol.library_value,
    library_path: symbol.library_path,
    symbol_name: symbol.symbol_name,
    symbol: symbol.address,
    abi: normalized_abi,
    sig: sig
  )
  binding.fn = dynamic_native_direct_call
  let r = new_ref(VkNativeFn)
  r.native_fn = dynamic_native_direct_call
  r.native_binding = binding
  r.to_ref_value()

proc make_dynamic_native_value_from_target*(target_expr: Value, sig: NativeSignature,
                                            abi: string, context: string,
                                            target_ns: Namespace,
                                            target_scope: Scope,
                                            target_tracker: ScopeTracker = nil): Value =
  let normalized_abi = if abi.len == 0: "cdecl" else: abi.strip().toLowerAscii()
  if normalized_abi != "cdecl":
    not_allowed(context & " only supports ^abi \"cdecl\" in v1")
  if sig == nil:
    not_allowed(context & " requires a concrete signature")
  sig.abi = normalized_abi
  ensure_dynamic_native_signature_supported(sig, context)
  let binding = DynamicNativeBinding(
    abi: normalized_abi,
    sig: sig,
    lifetime: DynamicNativeBindingLifetime(
      target_scope: target_scope,
      release_scope: release_dyn_binding_scope
    ),
    target_expr: target_expr,
    target_ns: target_ns,
    target_scope: target_scope,
    target_tracker: target_tracker,
    target_context: context
  )
  binding.fn = dynamic_native_direct_call
  let r = new_ref(VkNativeFn)
  r.native_fn = dynamic_native_direct_call
  r.native_binding = binding
  r.to_ref_value()

VmCreatedCallbacks.add proc() =
  init_dynamic_binding_namespace()
