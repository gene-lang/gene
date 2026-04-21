when not defined(gene_wasm):
  import strutils, os, tables, times

import ../types
import ../logging_core
when defined(gene_wasm):
  import ../wasm_host_abi

when not defined(gene_wasm):
  import dynlib
  import ./extension_abi
  import ./actor

  const VmExtensionLogger = "gene/vm/extension"

  when defined(posix):
    # Use dlopen with RTLD_GLOBAL on POSIX systems
    # This makes symbols from the main executable available to the loaded library
    const RTLD_NOW = 2
    const RTLD_GLOBAL = 256  # 0x100

    when defined(macosx):
      # On macOS, dlopen is in libSystem
      proc dlopen(filename: cstring, flag: cint): pointer {.importc.}
      proc dlsym(handle: pointer, symbol: cstring): pointer {.importc.}
      proc dlclose(handle: pointer): cint {.importc.}
      proc dlerror(): cstring {.importc.}
    else:
      # On Linux, dlopen is in libdl
      proc dlopen(filename: cstring, flag: cint): pointer {.importc, dynlib: "libdl.so(|.2|.1)".}
      proc dlsym(handle: pointer, symbol: cstring): pointer {.importc, dynlib: "libdl.so(|.2|.1)".}
      proc dlclose(handle: pointer): cint {.importc, dynlib: "libdl.so(|.2|.1)".}
      proc dlerror(): cstring {.importc, dynlib: "libdl.so(|.2|.1)".}

    proc loadLibGlobal(path: cstring): LibHandle =
      ## Load library with RTLD_GLOBAL so it can see symbols from main executable
      let handle = dlopen(path, RTLD_NOW or RTLD_GLOBAL)
      if handle == nil:
        let err = dlerror()
        log_message(LlDebug, VmExtensionLogger, "dlopen error: " & (if err != nil: $err else: "unknown"))
        return nil
      return cast[LibHandle](handle)

proc infer_extension_name(path: string): string =
  var name = splitFile(path).name
  if name.startsWith("lib") and name.len > 3:
    name = name[3..^1]
  name

proc lookup_genex_namespace(name: string): Namespace =
  if name.len == 0:
    return nil
  if App == NIL or App.kind != VkApplication:
    return nil
  if App.app.genex_ns.kind != VkNamespace:
    return nil
  let existing = App.app.genex_ns.ref.ns.members.getOrDefault(name.to_key(), NIL)
  if existing.kind == VkNamespace:
    return existing.ref.ns
  nil

proc run_vm_created_callbacks(start_idx: int) =
  ## Run any VM-created callbacks added after `start_idx`.
  var i = start_idx
  while i < VmCreatedCallbacks.len:
    VmCreatedCallbacks[i]()
    inc i

proc host_log_message_bridge(level: int32, logger_name: cstring, message: cstring) {.cdecl, gcsafe.} =
  let log_level = case level
    of int32(LlError): LlError
    of int32(LlWarn): LlWarn
    of int32(LlInfo): LlInfo
    of int32(LlDebug): LlDebug
    of int32(LlTrace): LlTrace
    else: LlInfo
  let logger_name_str = if logger_name == nil: "" else: $logger_name
  let message_str = if message == nil: "" else: $message
  log_message(log_level, logger_name_str, message_str)

type
  HostSchedulerCallbackEntry = object
    callback: GeneHostSchedulerTickFn
    callback_user_data: pointer

  RegisteredExtensionPort* = ref object
    name*: string
    kind*: ExtensionPortKind
    handler*: Value
    init_state*: Value
    pool_size*: int
    handles*: seq[Value]

var host_scheduler_callback_entries: seq[HostSchedulerCallbackEntry] = @[]
var host_scheduler_dispatcher_registered = false
var registered_extension_ports*: Table[string, RegisteredExtensionPort] = initTable[string, RegisteredExtensionPort]()

proc host_scheduler_dispatcher(vm: ptr VirtualMachine) {.gcsafe.} =
  {.cast(gcsafe).}:
    let vm_user_data = cast[pointer](vm)
    for entry in host_scheduler_callback_entries:
      if entry.callback != nil:
        entry.callback(vm_user_data, entry.callback_user_data)

proc host_register_scheduler_callback_bridge(callback: GeneHostSchedulerTickFn, callback_user_data: pointer): int32 {.cdecl, gcsafe.} =
  {.cast(gcsafe).}:
    if callback == nil:
      return int32(GeneExtErr)
    host_scheduler_callback_entries.add(
      HostSchedulerCallbackEntry(callback: callback, callback_user_data: callback_user_data)
    )
    if not host_scheduler_dispatcher_registered:
      host_scheduler_dispatcher_registered = true
      register_scheduler_callback(host_scheduler_dispatcher)
    int32(GeneExtOk)

proc clone_extension_port_state(init_state: Value): Value =
  if init_state == NIL:
    return NIL
  prepare_actor_payload_for_send(init_state).value

proc register_extension_port_runtime*(name: string, kind: ExtensionPortKind,
                                      handler: Value, init_state: Value = NIL,
                                      pool_size = 1): Value =
  if name.len == 0:
    raise new_exception(types.Exception, "extension port name cannot be empty")
  if handler.kind notin {VkFunction, VkNativeFn, VkBlock}:
    raise new_exception(types.Exception, "extension port handler must be callable")
  if kind != EpkFactory and not actor_runtime_active():
    raise new_exception(types.Exception, "extension ports require the actor runtime to be enabled")
  if registered_extension_ports.hasKey(name):
    raise new_exception(types.Exception, "extension port already registered: " & name)

  let reg = RegisteredExtensionPort(
    name: name,
    kind: kind,
    handler: handler,
    init_state: init_state,
    pool_size: max(1, pool_size),
    handles: @[]
  )
  registered_extension_ports[name] = reg

  case kind
  of EpkSingleton:
    let actor = actor_spawn_value(handler, init_state)
    reg.handles = @[actor]
    actor
  of EpkPool:
    let handles = new_array_value()
    for i in 0..<reg.pool_size:
      let state_val =
        if i == 0: init_state
        else: clone_extension_port_state(init_state)
      let actor = actor_spawn_value(handler, state_val)
      reg.handles.add(actor)
      array_data(handles).add(actor)
    handles
  of EpkFactory:
    NIL

proc spawn_registered_extension_factory_port*(name: string, init_state: Value = NIL): Value =
  if not registered_extension_ports.hasKey(name):
    raise new_exception(types.Exception, "extension port factory not found: " & name)
  let reg = registered_extension_ports[name]
  if reg.kind != EpkFactory:
    raise new_exception(types.Exception, "extension port is not a factory: " & name)
  if not actor_runtime_active():
    raise new_exception(types.Exception, "extension ports require the actor runtime to be enabled")
  let state_val =
    if init_state != NIL: init_state
    else: reg.init_state
  actor_spawn_value(reg.handler, state_val)

proc clear_registered_extension_ports_for_test*() =
  registered_extension_ports.clear()

proc host_register_port_bridge*(name: cstring, kind: int32, pool_size: int32,
                                handler: Value, init_state: Value,
                                out_handle: ptr Value): int32 {.cdecl, gcsafe.} =
  {.cast(gcsafe).}:
    if name == nil:
      return int32(GeneExtErr)
    try:
      let port_kind =
        case kind
        of int32(EpkSingleton.ord): EpkSingleton
        of int32(EpkPool.ord): EpkPool
        of int32(EpkFactory.ord): EpkFactory
        else: return int32(GeneExtErr)
      let handle = register_extension_port_runtime($name, port_kind, handler, init_state, max(1, int(pool_size)))
      if out_handle != nil:
        out_handle[] = handle
      int32(GeneExtOk)
    except CatchableError:
      int32(GeneExtErr)

proc host_call_port_bridge*(port_handle: Value, msg: Value, timeout_ms: int32,
                            out_value: ptr Value): int32 {.cdecl, gcsafe.} =
  {.cast(gcsafe).}:
    if VM == nil:
      return int32(GeneExtErr)
    try:
      let future = actor_send_value(VM, port_handle, msg, true)
      let deadline = epochTime() + (float(timeout_ms) / 1000.0)
      let future_obj = future.ref.future
      while future_obj.state == FsPending and epochTime() < deadline:
        VM.event_loop_counter = 100
        vm_poll_event_loop(VM)
        sleep(10)

      if future_obj.state != FsSuccess:
        return int32(GeneExtErr)
      if out_value != nil:
        out_value[] = future_obj.value
      int32(GeneExtOk)
    except CatchableError:
      int32(GeneExtErr)

proc load_extension*(vm: ptr VirtualMachine, path: string): Namespace =
  ## Load a dynamic library extension and return its namespace
  when defined(gene_wasm):
    discard vm
    discard path
    raise_wasm_unsupported("dynamic_extension_loading")
  else:
    var lib_path = path

    # Try adding extension suffix if not present
    if not (path.endsWith(".so") or path.endsWith(".dll") or path.endsWith(".dylib")):
      when defined(windows):
        lib_path = path & ".dll"
      elif defined(macosx):
        lib_path = path & ".dylib"
      else:
        lib_path = path & ".so"

    let callback_base = VmCreatedCallbacks.len

    when defined(posix):
      # Use RTLD_GLOBAL on POSIX to make main executable symbols available
      let handle = loadLibGlobal(lib_path.cstring)
    else:
      let handle = loadLib(lib_path.cstring)

    if handle.isNil:
      raise new_exception(types.Exception, "[GENE.EXT.LOAD_FAILED] Failed to load extension: " & lib_path)

    # Some extension modules register with VmCreatedCallbacks at module load.
    # Run newly-added callbacks immediately when loading dynamically.
    run_vm_created_callbacks(callback_base)
    let post_load_callback_base = VmCreatedCallbacks.len

    let init_fn = cast[GeneExtensionInitFn](handle.symAddr("gene_init"))
    if init_fn == nil:
      raise new_exception(
        types.Exception,
        "[GENE.EXT.SYMBOL_MISSING] Required symbol 'gene_init' not found in extension: " & lib_path
      )

    var ext_ns: Namespace = nil
    var host = GeneHostAbi(
      abi_version: GENE_EXT_ABI_VERSION,
      user_data: cast[pointer](vm),
      app_value: App,
      symbols_data: if vm != nil and vm.symbols != nil: cast[pointer](vm.symbols) else: nil,
      log_message_fn: host_log_message_bridge,
      register_scheduler_callback_fn: host_register_scheduler_callback_bridge,
      register_port_fn: host_register_port_bridge,
      call_port_fn: host_call_port_bridge,
      result_namespace: addr ext_ns
    )

    let init_status = init_fn(addr host)

    # gene_init may also append VM-created callbacks (e.g. class registration hooks).
    run_vm_created_callbacks(post_load_callback_base)

    if init_status == int32(GeneExtAbiMismatch):
      raise new_exception(
        types.Exception,
        "[GENE.EXT.ABI_MISMATCH] Extension ABI mismatch for: " & lib_path
      )
    if init_status != int32(GeneExtOk):
      raise new_exception(
        types.Exception,
        "[GENE.EXT.INIT_FAILED] gene_init failed for extension: " & lib_path
      )

    if ext_ns == nil:
      ext_ns = lookup_genex_namespace(infer_extension_name(lib_path))
    if ext_ns == nil:
      raise new_exception(
        types.Exception,
        "[GENE.EXT.INIT_FAILED] Extension did not publish a namespace: " & lib_path
      )

    result = ext_ns


# No longer needed since we use deterministic hashing
