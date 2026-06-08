import tables

import ../gene/repl_input
import ../gene/types
import ../gene/vm/extension_abi

var reader_class_global: Class
var reader_table {.threadvar.}: Table[int, ReplInputReader]
var next_reader_id {.threadvar.}: int
var sigint_count {.threadvar.}: int
var sigint_hook_installed {.threadvar.}: bool

const ReaderIdKey = "__readline_reader_id__"

proc ensure_reader_table() =
  if next_reader_id == 0:
    next_reader_id = 1
    reader_table = initTable[int, ReplInputReader]()

proc readline_sigint_hook() {.noconv.} =
  sigint_count.inc()
  discard interrupt_active_readline()

proc reader_id(self: Value): int =
  if self.kind != VkInstance:
    raise new_exception(types.Exception, "Readline.Reader method requires self")
  let id_val = instance_props(self).getOrDefault(ReaderIdKey.to_key(), NIL)
  if id_val.kind != VkInt:
    raise new_exception(types.Exception, "Readline.Reader is closed")
  id_val.to_int().int

proc reader_for(self: Value): ReplInputReader =
  ensure_reader_table()
  let id = reader_id(self)
  if not reader_table.hasKey(id):
    raise new_exception(types.Exception, "Readline.Reader is closed")
  reader_table[id]

proc reader_constructor(vm: ptr VirtualMachine, args: ptr UncheckedArray[Value],
                        arg_count: int, has_keyword_args: bool): Value {.gcsafe.} =
  discard vm
  discard args
  discard arg_count
  discard has_keyword_args
  {.cast(gcsafe).}:
    ensure_reader_table()
    let id = next_reader_id
    next_reader_id.inc()
    reader_table[id] = new_repl_input_reader()
    let inst = new_instance_value(reader_class_global)
    instance_props(inst)[ReaderIdKey.to_key()] = id.to_value()
    return inst

proc reader_read_line(vm: ptr VirtualMachine, args: ptr UncheckedArray[Value],
                      arg_count: int, has_keyword_args: bool): Value {.gcsafe.} =
  discard vm
  {.cast(gcsafe).}:
    let self = get_self(args, has_keyword_args)
    let prompt =
      if get_method_arg_count(arg_count, has_keyword_args) > 0:
        get_method_arg(args, 0, has_keyword_args).str_no_quotes()
      else:
        ""
    var input = ""
    if reader_for(self).read_line(prompt, input):
      return input.to_value()
    return NIL

proc reader_read_event(vm: ptr VirtualMachine, args: ptr UncheckedArray[Value],
                       arg_count: int, has_keyword_args: bool): Value {.gcsafe.} =
  discard vm
  {.cast(gcsafe).}:
    let before = sigint_count
    let self = get_self(args, has_keyword_args)
    let prompt =
      if get_method_arg_count(arg_count, has_keyword_args) > 0:
        get_method_arg(args, 0, has_keyword_args).str_no_quotes()
      else:
        ""
    var input = ""
    let status = repl_input.read_event(reader_for(self), prompt, input,
      proc(): bool {.gcsafe.} = sigint_count > before)
    let event = new_map_value()
    if status == RirsInterrupt:
      map_data(event)["status".to_key()] = "interrupt".to_value()
      map_data(event)["line".to_key()] = input.to_value()
    elif status == RirsLine:
      map_data(event)["status".to_key()] = "line".to_value()
      map_data(event)["line".to_key()] = input.to_value()
    else:
      map_data(event)["status".to_key()] = "eof".to_value()
      map_data(event)["line".to_key()] = NIL
    return event

proc reader_backend(vm: ptr VirtualMachine, args: ptr UncheckedArray[Value],
                    arg_count: int, has_keyword_args: bool): Value {.gcsafe.} =
  discard vm
  discard arg_count
  {.cast(gcsafe).}:
    let backend =
      case reader_for(get_self(args, has_keyword_args)).backend
      of RibReadline: "readline"
      of RibPlain: "plain"
    return backend.to_value()

proc reader_close(vm: ptr VirtualMachine, args: ptr UncheckedArray[Value],
                  arg_count: int, has_keyword_args: bool): Value {.gcsafe.} =
  discard vm
  discard arg_count
  {.cast(gcsafe).}:
    ensure_reader_table()
    let self = get_self(args, has_keyword_args)
    let id = reader_id(self)
    if reader_table.hasKey(id):
      reader_table[id].close()
      reader_table.del(id)
    instance_props(self)[ReaderIdKey.to_key()] = NIL
    return NIL

proc readline_install_sigint_handler(vm: ptr VirtualMachine, args: ptr UncheckedArray[Value],
                                     arg_count: int, has_keyword_args: bool): Value {.gcsafe.} =
  discard vm
  discard args
  discard arg_count
  discard has_keyword_args
  if not sigint_hook_installed:
    setControlCHook(readline_sigint_hook)
    sigint_hook_installed = true
  TRUE

proc readline_sigint_count_native(vm: ptr VirtualMachine, args: ptr UncheckedArray[Value],
                                  arg_count: int, has_keyword_args: bool): Value {.gcsafe.} =
  discard vm
  discard args
  discard arg_count
  discard has_keyword_args
  sigint_count.to_value()

proc readline_clear_sigint_native(vm: ptr VirtualMachine, args: ptr UncheckedArray[Value],
                                  arg_count: int, has_keyword_args: bool): Value {.gcsafe.} =
  discard vm
  discard args
  discard arg_count
  discard has_keyword_args
  sigint_count = 0
  NIL

proc readline_backend_native(vm: ptr VirtualMachine, args: ptr UncheckedArray[Value],
                             arg_count: int, has_keyword_args: bool): Value {.gcsafe.} =
  discard vm
  discard args
  discard arg_count
  discard has_keyword_args
  {.cast(gcsafe).}:
    let reader = new_repl_input_reader()
    let backend =
      case reader.backend
      of RibReadline: "readline"
      of RibPlain: "plain"
    reader.close()
    return backend.to_value()

proc put_fn(ns: Namespace, name: string, fn: NativeFn) =
  let fn_ref = new_ref(VkNativeFn)
  fn_ref.native_fn = fn
  ns[name.to_key()] = fn_ref.to_ref_value()

proc init_readline_module*() =
  VmCreatedCallbacks.add proc() =
    if App == NIL or App.kind != VkApplication:
      return
    if App.app.genex_ns == NIL or App.app.genex_ns.kind != VkNamespace:
      return

    {.cast(gcsafe).}:
      reader_class_global = new_class("Reader")
      reader_class_global.def_native_constructor(reader_constructor)
      reader_class_global.def_native_method("read_line", reader_read_line)
      reader_class_global.def_native_method("read_event", reader_read_event)
      reader_class_global.def_native_method("backend", reader_backend)
      reader_class_global.def_native_method("close", reader_close)

    let reader_class_ref = new_ref(VkClass)
    {.cast(gcsafe).}:
      reader_class_ref.class = reader_class_global

    let readline_ns = new_namespace("readline")
    readline_ns["Reader".to_key()] = reader_class_ref.to_ref_value()
    put_fn(readline_ns, "install_sigint_handler", readline_install_sigint_handler)
    put_fn(readline_ns, "sigint_count", readline_sigint_count_native)
    put_fn(readline_ns, "clear_sigint", readline_clear_sigint_native)
    put_fn(readline_ns, "backend", readline_backend_native)
    App.app.genex_ns.ref.ns["readline".to_key()] = readline_ns.to_value()

init_readline_module()

proc init*(vm: ptr VirtualMachine): Namespace {.gcsafe.} =
  discard vm
  if App == NIL or App.kind != VkApplication:
    return nil
  if App.app.genex_ns.kind != VkNamespace:
    return nil
  let readline_val = App.app.genex_ns.ref.ns.members.getOrDefault("readline".to_key(), NIL)
  if readline_val.kind == VkNamespace:
    return readline_val.ref.ns
  nil

proc gene_init*(host: ptr GeneHostAbi): int32 {.cdecl, exportc, dynlib.} =
  if host == nil:
    return int32(GeneExtErr)
  if host.abi_version != GENE_EXT_ABI_VERSION:
    return int32(GeneExtAbiMismatch)
  let vm = apply_extension_host_context(host)
  run_extension_vm_created_callbacks()
  let ns = init(vm)
  if host.result_namespace != nil:
    host.result_namespace[] = ns
  if ns == nil:
    return int32(GeneExtErr)
  int32(GeneExtOk)
