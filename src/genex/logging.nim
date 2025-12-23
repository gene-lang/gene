import tables, strutils, os, algorithm

import ../gene/types
import ../gene/logging_core

var logger_class_global: Class

proc value_to_log_part(value: Value): string =
  case value.kind
  of VkString:
    value.str
  else:
    value.str_no_quotes()

proc collect_message(args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool, start_idx: int): string =
  let pos_count = get_positional_count(arg_count, has_keyword_args)
  if pos_count <= start_idx:
    return ""
  result = ""
  for i in start_idx..<pos_count:
    if i > start_idx:
      result &= " "
    result &= value_to_log_part(get_positional_arg(args, i, has_keyword_args))

proc logger_log(level: LogLevel, vm: ptr VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value {.gcsafe.} =
  if get_positional_count(arg_count, has_keyword_args) < 1:
    raise new_exception(types.Exception, "Logger method requires self")
  let self_val = get_positional_arg(args, 0, has_keyword_args)
  if self_val.kind != VkInstance:
    raise new_exception(types.Exception, "Logger methods must be called on an instance")
  let name_key = "name".to_key()
  let name_val = instance_props(self_val).getOrDefault(name_key, NIL)
  let logger_name =
    if name_val.kind == VkString or name_val.kind == VkSymbol:
      name_val.str
    else:
      "unknown"
  let message = collect_message(args, arg_count, has_keyword_args, 1)
  log_message(level, logger_name, message)
  NIL

proc logger_info(vm: ptr VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value {.gcsafe.} =
  logger_log(LlInfo, vm, args, arg_count, has_keyword_args)

proc logger_warn(vm: ptr VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value {.gcsafe.} =
  logger_log(LlWarn, vm, args, arg_count, has_keyword_args)

proc logger_error(vm: ptr VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value {.gcsafe.} =
  logger_log(LlError, vm, args, arg_count, has_keyword_args)

proc logger_debug(vm: ptr VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value {.gcsafe.} =
  logger_log(LlDebug, vm, args, arg_count, has_keyword_args)

proc logger_trace(vm: ptr VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value {.gcsafe.} =
  logger_log(LlTrace, vm, args, arg_count, has_keyword_args)

proc namespace_segments(ns: Namespace): seq[string] =
  result = @[]
  var current = ns
  while current != nil:
    if current.name.len > 0 and current.name != "<root>":
      result.add(current.name)
    current = current.parent
  result.reverse()

proc looks_like_module_path(name: string): bool =
  if name.len == 0:
    return false
  if name.contains("/") or name.contains("\\"):
    return true
  let lower = name.toLowerAscii()
  lower.endsWith(".gene") or lower.endsWith(".gir")

proc normalize_module_path(path: string): string =
  if path.len == 0:
    return "unknown"
  var normalized = path
  if normalized.isAbsolute:
    try:
      normalized = relativePath(normalized, getCurrentDir())
    except OSError:
      discard
  normalized = normalized.replace('\\', '/')
  normalized

proc split_module_segments(segments: seq[string]): tuple[module_path: string, ns_parts: seq[string]] =
  for i, segment in segments:
    if looks_like_module_path(segment):
      let module_path = normalize_module_path(segment)
      let ns_parts = if i + 1 < segments.len: segments[i + 1 .. ^1] else: @[]
      return (module_path, ns_parts)
  ("unknown", segments)

proc join_logger_parts(parts: seq[string]): string =
  var trimmed: seq[string] = @[]
  for part in parts:
    if part.len > 0:
      trimmed.add(part)
  if trimmed.len == 0:
    return "unknown"
  trimmed.join("/")

proc module_path_from_namespace(ns: Namespace): string =
  var current = ns
  let key = "__module_name__".to_key()
  while current != nil:
    if current.members.hasKey(key):
      let value = current.members[key]
      if value.kind == VkString:
        return value.str
    if current.name.len > 0 and current.name != "<root>" and looks_like_module_path(current.name):
      return current.name
    current = current.parent
  ""

proc logger_name_from_namespace(ns: Namespace, fallback_module: string = ""): string =
  let segments = namespace_segments(ns)
  var (module_path, ns_parts) = split_module_segments(segments)
  if (module_path == "unknown" or module_path.len == 0) and fallback_module.len > 0:
    module_path = normalize_module_path(fallback_module)
  join_logger_parts(@[module_path] & ns_parts)

proc logger_name_from_class(cls: Class, fallback_module: string = ""): string =
  if cls.is_nil:
    return "unknown"
  var module_path = ""
  var ns_parts: seq[string] = @[]
  if cls.ns != nil and cls.ns.parent != nil:
    let segments = namespace_segments(cls.ns.parent)
    var (module_candidate, parts) = split_module_segments(segments)
    module_path = module_candidate
    ns_parts = parts
  if (module_path == "unknown" or module_path.len == 0) and fallback_module.len > 0:
    module_path = normalize_module_path(fallback_module)
  join_logger_parts(@[module_path] & ns_parts & @[cls.name])

proc fallback_module_path(vm: ptr VirtualMachine): string =
  if vm == nil or vm.frame == nil:
    return ""
  if vm.frame.caller_frame != nil and vm.frame.caller_frame.ns != nil:
    let name = module_path_from_namespace(vm.frame.caller_frame.ns)
    if name.len > 0:
      return name
  if vm.frame.ns != nil and vm.frame.ns.parent != nil:
    let name = module_path_from_namespace(vm.frame.ns.parent)
    if name.len > 0:
      return name
  if App != NIL and App.kind == VkApplication and App.app.gene_ns.kind == VkNamespace:
    let key = "main_module".to_key()
    if App.app.gene_ns.ref.ns.members.hasKey(key):
      let value = App.app.gene_ns.ref.ns.members[key]
      if value.kind == VkString:
        return value.str
  ""

proc logger_constructor(vm: ptr VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value {.gcsafe.} =
  if get_positional_count(arg_count, has_keyword_args) < 1:
    raise new_exception(types.Exception, "Logger requires a class or namespace")
  let target = get_positional_arg(args, 0, has_keyword_args)
  if target.kind == VkInstance:
    raise new_exception(types.Exception, "Logger requires a class or namespace, not an instance")
  let fallback_module = fallback_module_path(vm)
  var logger_name =
    case target.kind
    of VkClass:
      let cls = target.ref.class
      if not cls.is_nil and cls.ns != nil and cls.ns.parent.is_nil and vm != nil and vm.frame != nil:
        if vm.frame.caller_frame != nil and vm.frame.caller_frame.ns != nil:
          cls.ns.parent = vm.frame.caller_frame.ns
        elif vm.frame.ns != nil and vm.frame.ns.parent != nil:
          cls.ns.parent = vm.frame.ns.parent
      logger_name_from_class(cls, fallback_module)
    of VkNamespace:
      logger_name_from_namespace(target.ref.ns, fallback_module)
    else:
      raise new_exception(types.Exception, "Logger requires a class or namespace")
  if fallback_module.len > 0:
    let normalized_fallback = normalize_module_path(fallback_module)
    if not logger_name.startsWith(normalized_fallback & "/") and logger_name != normalized_fallback:
      logger_name = join_logger_parts(@[normalized_fallback, logger_name])
  var instance: Value
  {.cast(gcsafe).}:
    instance = new_instance_value(logger_class_global)
  let name_key = "name".to_key()
  instance_props(instance)[name_key] = logger_name.to_value()
  instance

proc init_logging_module*() =
  VmCreatedCallbacks.add proc() =
    if App == NIL or App.kind != VkApplication:
      return
    if App.app.genex_ns == NIL:
      return

    {.cast(gcsafe).}:
      logger_class_global = new_class("Logger")
      logger_class_global.def_native_constructor(logger_constructor)
      logger_class_global.def_native_method("info", logger_info)
      logger_class_global.def_native_method("warn", logger_warn)
      logger_class_global.def_native_method("error", logger_error)
      logger_class_global.def_native_method("debug", logger_debug)
      logger_class_global.def_native_method("trace", logger_trace)

    let logger_class_ref = new_ref(VkClass)
    {.cast(gcsafe).}:
      logger_class_ref.class = logger_class_global

    let logging_ns = new_namespace("logging")
    logging_ns["Logger".to_key()] = logger_class_ref.to_ref_value()
    App.app.genex_ns.ref.ns["logging".to_key()] = logging_ns.to_value()

init_logging_module()
