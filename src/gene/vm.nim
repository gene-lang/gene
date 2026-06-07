{.push warning[ResultShadowed]: off, warning[UnreachableCode]: off, warning[UnusedImport]: off.}

import tables, strutils, strformat, algorithm, options, streams, locks
import times, os
import asyncdispatch  # For event loop polling in async support

import ./types
import ./logging_core
from ./types/runtime_types import
  validate_type,
  validate_or_coerce_type,
  GuardContext,
  GuardPhase,
  GpArgument,
  GpReturn,
  GpLocal,
  GpEnumPayload,
  GpTuplePayload,
  BpPositive,
  BpNegative,
  emit_type_warning,
  is_compatible,
  runtime_type_name,
  new_runtime_type_object,
  new_runtime_type_value,
  is_runtime_type_value,
  runtime_type_payload,
  resolve_constructor,
  resolve_initializer,
  resolve_method
import ./compiler
from ./parser import read, read_all
import ./hash_map_support
import ./vm/args
import ./vm/module
import ./vm/utils
import ./vm/profile
export profile
import ./serdes
import ./wasm_host_abi
import ./native/runtime
import ./native/hir
import ./native/trampoline
const DEBUG_VM = false
const
  CATCH_PC_ASYNC_BLOCK = -2
  CATCH_PC_ASYNC_FUNCTION = -3
  EVENT_LOOP_POLL_INTERVAL = 100
  VmExecLogger = "gene/vm/exec"
  VmDispatchLogger = "gene/vm/dispatch"

template vm_log(level: LogLevel, logger_name: string, message: untyped) =
  if log_enabled(level, logger_name):
    log_message(level, logger_name, message)

template is_method_frame(f: Frame): bool =
  f.kind in {FkMethod, FkMacroMethod}

template is_function_like(kind: FrameKind): bool =
  kind in {FkFunction, FkMethod, FkMacroMethod}

template same_value_identity(a: Value, b: Value): bool =
  cast[uint64](a) == cast[uint64](b)

include ./vm/core_helpers
include ./vm/checks

proc native_guard_context(phase: GuardPhase, producer: string, consumer: string,
                          site: string): GuardContext {.inline.} =
  GuardContext(
    enabled: true,
    phase: phase,
    party: if phase == GpReturn: BpPositive else: BpNegative,
    producer: producer,
    consumer: consumer,
    site: site)

proc native_param_name(sig: NativeSignature, index: int): string {.inline.} =
  if sig != nil and index >= 0 and index < sig.param_names.len and sig.param_names[index].len > 0:
    return sig.param_names[index]
  "argument " & $(index + 1)

proc validate_native_value(vm: ptr VirtualMachine, value: Value, type_id: TypeId,
                           type_descs: seq[TypeDesc], param_name: string,
                           context: GuardContext) {.inline.} =
  if type_id == NO_TYPE_ID or type_id == BUILTIN_TYPE_ANY_ID:
    return
  if value == NIL and (vm == nil or not vm.strict_nil):
    return
  validate_type(value, type_id, type_descs, param_name,
    if vm == nil: "" else: vm.runtime_type_error_location(),
    strict_nil = vm != nil and vm.strict_nil,
    context = context)

proc validate_native_call_args(vm: ptr VirtualMachine, sig: NativeSignature,
                               args: ptr UncheckedArray[Value], arg_count: int,
                               has_keyword_args: bool) =
  if sig == nil:
    return
  let keyword_offset = if has_keyword_args: 1 else: 0
  if has_keyword_args:
    if arg_count == 0 or args == nil or args[0].kind != VkMap:
      not_allowed("native call expected keyword argument map")
    var accepts_keywords = false
    for param in sig.params:
      if param.kind in {CpkKeyword, CpkKeywordRest}:
        accepts_keywords = true
        break
    if not accepts_keywords and map_data(args[0]).len > 0:
      not_allowed("native call does not accept keyword arguments")

  if sig.receives_self and arg_count < keyword_offset + 1:
    not_allowed("native method expects receiver")

  let start = keyword_offset + (if sig.receives_self: 1 else: 0)
  let positional_count = max(0, arg_count - start)
  if positional_count < sig.arity_min or (sig.arity_max >= 0 and positional_count > sig.arity_max):
    let expected =
      if sig.arity_max >= 0 and sig.arity_min == sig.arity_max: $sig.arity_min
      elif sig.arity_max >= 0: $sig.arity_min & ".." & $sig.arity_max
      else: $sig.arity_min & "+"
    not_allowed("native call expects " & expected & " positional argument(s), got " & $positional_count)

  let site = if vm == nil: "" else: vm.runtime_type_error_location()
  let context = native_guard_context(GpArgument, "caller", "native", site)
  var pos_index = 0
  for param_index, param in sig.params:
    case param.kind
    of CpkPositional:
      if pos_index < positional_count:
        validate_native_value(vm, args[start + pos_index], param.type_id,
          sig.type_descriptors, native_param_name(sig, param_index), context)
      pos_index.inc()
    of CpkPositionalRest:
      while pos_index < positional_count:
        validate_native_value(vm, args[start + pos_index], param.type_id,
          sig.type_descriptors, native_param_name(sig, param_index), context)
        pos_index.inc()
    of CpkKeyword:
      if has_keyword_args and map_data(args[0]).hasKey(param.keyword_name.to_key()):
        validate_native_value(vm, map_data(args[0])[param.keyword_name.to_key()], param.type_id,
          sig.type_descriptors, param.keyword_name, context)
    of CpkKeywordRest:
      if has_keyword_args:
        for _, kw_value in map_data(args[0]):
          validate_native_value(vm, kw_value, param.type_id,
            sig.type_descriptors, "keyword argument", context)

proc strict_native_types_enabled(vm: ptr VirtualMachine): bool {.inline.} =
  if vm != nil and vm.strict_native_types:
    return true
  App.kind == VkApplication and App.app.strict_native_types

proc enforce_native_signature_presence(fn: NativeFn, vm: ptr VirtualMachine,
                                       sig: NativeSignature) {.inline.} =
  if not strict_native_types_enabled(vm) or is_native_signature_strict_exempt(fn):
    return
  if sig != nil and sig.has_type_annotations:
    return
  not_allowed("strict native types require a non-Any NativeSignature before calling native callables; use a typed ^native declaration or $assign-type/$assign-method-type/$assign-ctor-type")

proc call_typed_native_fn(fn: NativeFn, vm: ptr VirtualMachine,
                          args: ptr UncheckedArray[Value], arg_count: int,
                          has_keyword_args: bool): Value {.gcsafe.} =
  var sig: NativeSignature = nil
  {.cast(gcsafe).}:
    sig = lookup_native_signature(fn)
    enforce_native_signature_presence(fn, vm, sig)
  let should_check = vm != nil and vm.type_check and sig != nil and sig.has_type_annotations
  if should_check:
    {.cast(gcsafe).}:
      validate_native_call_args(vm, sig, args, arg_count, has_keyword_args)

  result =
    if arg_count == 0:
      fn(vm, nil, 0, has_keyword_args)
    else:
      fn(vm, args, arg_count, has_keyword_args)

  if should_check:
    {.cast(gcsafe).}:
      let site = if vm == nil: "" else: vm.runtime_type_error_location()
      validate_native_value(vm, result, sig.return_type_id, sig.type_descriptors,
        "native return value", native_guard_context(GpReturn, "native", "caller", site))

import ./vm/arithmetic
import ./vm/generator
import ./vm/thread
import ./vm/actor
import ./vm/pubsub

# Forward declarations needed by vm/async and vm/native
proc exec*(self: ptr VirtualMachine): Value
proc exec_function*(self: ptr VirtualMachine, fn: Value, args: seq[Value]): Value
proc exec_function_kw*(self: ptr VirtualMachine, fn: Value, args: seq[Value], kw_pairs: seq[(Key, Value)]): Value
proc exec_method*(self: ptr VirtualMachine, fn: Value, instance: Value, args: seq[Value]): Value
proc exec_method_kw*(self: ptr VirtualMachine, fn: Value, instance: Value, args: seq[Value], kw_pairs: seq[(Key, Value)]): Value
proc exec_method_impl(self: ptr VirtualMachine, fn: Value, instance: Value, args: seq[Value], caller_context: Frame): Value
proc exec_method_kw_impl(self: ptr VirtualMachine, fn: Value, instance: Value, args: seq[Value], kw_pairs: seq[(Key, Value)], caller_context: Frame): Value
proc format_runtime_exception(self: ptr VirtualMachine, value: Value): string
proc spawn_thread(code: Value, return_value: bool): Value
proc poll_event_loop*(self: ptr VirtualMachine)
proc run_module_init*(self: ptr VirtualMachine, module_ns: Namespace): tuple[ran: bool, value: Value]
proc exec_callable*(self: ptr VirtualMachine, callable: Value, args: seq[Value]): Value
proc exec_callable_with_self*(self: ptr VirtualMachine, callable: Value, self_value: Value, args: seq[Value]): Value
proc exec_continue*(self: ptr VirtualMachine): Value

# Forward declarations for adapter functions
proc exec_interface(vm: ptr VirtualMachine, name: Value)
proc exec_interface_method(vm: ptr VirtualMachine, name: Value, flags: int32)
proc exec_interface_prop(vm: ptr VirtualMachine, name: Value, readonly: bool)
proc exec_implement(vm: ptr VirtualMachine, interface_name: Value, is_external: bool, has_body: bool)
proc exec_implement_method(vm: ptr VirtualMachine, method_name: Value)
proc exec_implement_ctor(vm: ptr VirtualMachine)
proc exec_implement_field(vm: ptr VirtualMachine, metadata: Value, flags: int32)
proc exec_implement_check(vm: ptr VirtualMachine)
proc exec_adapter(vm: ptr VirtualMachine, ctor_args: seq[Value] = @[], kw_pairs: seq[(Key, Value)] = @[])
proc adapter_get_member(vm: ptr VirtualMachine, adapter_val: Value, key: Key): Value
proc adapter_set_member(vm: ptr VirtualMachine, adapter_val: Value, key: Key, value: Value)
proc adapter_member_or_nil(vm: ptr VirtualMachine, adapter_val: Value, prop: Value): Value
proc dispatch_adapter_method(vm: ptr VirtualMachine, obj: Value, method_name: string, args: seq[Value]): Value
proc dispatch_adapter_method_kw(vm: ptr VirtualMachine, obj: Value, method_name: string, args: seq[Value], kw_pairs: seq[(Key, Value)]): Value
# Forward declarations for adapter internal functions
proc adapter_internal_get_member*(adapter_internal_val: Value, key: Key): Value
proc adapter_internal_set_member*(adapter_internal_val: Value, key: Key, value: Value)
proc adapter_internal_member_or_nil*(adapter_internal_val: Value, prop: Value): Value

include "./vm/native"

import ./vm/async
include ./vm/async_exec

when not defined(noExtensions):
  import ./vm/extension

include ./vm/exceptions
include ./vm/dispatch
include ./vm/vm_modules
include ./vm/exec
include ./vm/exec_support
include ./vm/adapter
include ./vm/entry
include ./vm/diagnostics
include ./vm/runtime_helpers

set_vm_exec_callable_hook(exec_callable)
set_vm_exec_callable_with_self_hook(exec_callable_with_self)
set_vm_poll_event_loop_hook(poll_event_loop)
set_vm_native_call_hook(call_typed_native_fn)
set_serdes_module_loader_hook(proc(module_path: string): Namespace {.nimcall.} =
  ensure_runtime_module_loaded(VM, module_path)
)

include "./stdlib"

# Register default on_member_missing handler on genex namespace
# This replaces the hard-coded ensure_genex_extension checks in exec.nim
proc genex_extension_loader(vm: ptr VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value {.gcsafe.} =
  {.cast(gcsafe).}:
    let name_val = get_positional_arg(args, 0, has_keyword_args)
    if name_val.kind != VkString and name_val.kind != VkSymbol:
      return NIL
    let part = name_val.str
    when not defined(noExtensions):
      return ensure_genex_extension(vm, part)
    else:
      return NIL

# Register via VmCreatedCallbacks so it runs after App is initialized
VmCreatedCallbacks.add proc() =
  if App != NIL and App.kind == VkApplication and App.app.genex_ns.kind == VkNamespace:
    let loader_ref = new_ref(VkNativeFn)
    loader_ref.native_fn = genex_extension_loader
    App.app.genex_ns.ref.ns.on_member_missing.add(loader_ref.to_ref_value())

{.pop.}
