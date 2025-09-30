import ../types
import ../vm/args
import std/os
import std/base64
import std/asyncdispatch

# Core functions for the Gene standard library

# Print without newline
proc core_print*(vm: VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value =
  var s = ""
  for i in 0..<get_positional_count(arg_count, has_keyword_args):
    let k = get_positional_arg(args, i, has_keyword_args)
    s &= k.str_no_quotes()
    if i < get_positional_count(arg_count, has_keyword_args) - 1:
      s &= " "
  stdout.write(s)
  return NIL

# Print with newline
proc core_println*(vm: VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value =
  var s = ""
  for i in 0..<get_positional_count(arg_count, has_keyword_args):
    let k = get_positional_arg(args, i, has_keyword_args)
    s &= k.str_no_quotes()
    if i < get_positional_count(arg_count, has_keyword_args) - 1:
      s &= " "
  echo s
  return NIL

# Assert condition
proc core_assert*(vm: VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value =
  if arg_count > 0:
    let condition = get_positional_arg(args, 0, has_keyword_args)
    if not condition.to_bool():
      var msg = "Assertion failed"
      if arg_count > 1:
        msg = get_positional_arg(args, 1, has_keyword_args).str
      raise new_exception(types.Exception, msg)
  return NIL

# Debug value (write to stderr)
proc core_debug*(vm: VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value =
  for i in 0..<get_positional_count(arg_count, has_keyword_args):
    let val = get_positional_arg(args, i, has_keyword_args)
    stderr.writeLine("<debug>: " & $val)
  return NIL

# Trace control
proc core_trace_start*(vm: VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value =
  vm.trace = true
  return NIL

proc core_trace_end*(vm: VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value =
  vm.trace = false
  return NIL

# Sleep (synchronous)
proc core_sleep*(vm: VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value =
  if arg_count < 1:
    raise new_exception(types.Exception, "sleep requires 1 argument (duration in milliseconds)")

  let duration_arg = get_positional_arg(args, 0, has_keyword_args)
  var duration_ms: int

  case duration_arg.kind:
    of VkInt:
      duration_ms = duration_arg.int64.int
    of VkFloat:
      duration_ms = (duration_arg.float64 * 1000).int
    else:
      raise new_exception(types.Exception, "sleep requires a number (milliseconds)")

  sleep(duration_ms)
  return NIL

# Run event loop forever
proc core_run_forever*(vm: VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value =
  # Run the async event loop indefinitely
  while hasPendingOperations():
    poll(0)
  return NIL

# Environment variable functions
proc core_get_env*(vm: VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value =
  if arg_count < 1:
    raise new_exception(types.Exception, "get_env requires at least 1 argument (variable name)")

  let name_arg = get_positional_arg(args, 0, has_keyword_args)
  if name_arg.kind != VkString:
    raise new_exception(types.Exception, "get_env requires a string variable name")

  let name = name_arg.str
  let value = getEnv(name, "")

  if value == "":
    # Check if default provided
    if arg_count > 1:
      return get_positional_arg(args, 1, has_keyword_args)
    else:
      return NIL
  else:
    return value.to_value()

proc core_set_env*(vm: VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value =
  if arg_count < 2:
    raise new_exception(types.Exception, "set_env requires 2 arguments (name, value)")

  let name_arg = get_positional_arg(args, 0, has_keyword_args)
  let value_arg = get_positional_arg(args, 1, has_keyword_args)

  if name_arg.kind != VkString:
    raise new_exception(types.Exception, "set_env requires a string variable name")

  let name = name_arg.str
  let value = value_arg.str_no_quotes()

  putEnv(name, value)
  return NIL

proc core_has_env*(vm: VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value =
  if arg_count < 1:
    raise new_exception(types.Exception, "has_env requires 1 argument (variable name)")

  let name_arg = get_positional_arg(args, 0, has_keyword_args)
  if name_arg.kind != VkString:
    raise new_exception(types.Exception, "has_env requires a string variable name")

  let name = name_arg.str
  return existsEnv(name).to_value()

# Base64 encoding/decoding
proc core_base64*(vm: VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value =
  if arg_count < 1:
    raise new_exception(types.Exception, "base64 requires a string argument")

  let input = get_positional_arg(args, 0, has_keyword_args)
  if input.kind != VkString:
    raise new_exception(types.Exception, "base64 requires a string argument")

  let encoded = base64.encode(input.str)
  return encoded.to_value()

proc core_base64_decode*(vm: VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value =
  if arg_count < 1:
    raise new_exception(types.Exception, "base64_decode requires a string argument")

  let input = get_positional_arg(args, 0, has_keyword_args)
  if input.kind != VkString:
    raise new_exception(types.Exception, "base64_decode requires a string argument")

  try:
    let decoded = base64.decode(input.str)
    return decoded.to_value()
  except ValueError as e:
    raise new_exception(types.Exception, "Invalid base64 string: " & e.msg)

# VM debugging functions
proc core_vm_print_stack*(vm: VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value =
  var s = "Stack: "
  for i, reg in vm.frame.stack:
    if i > 0:
      s &= ", "
    if i == vm.frame.stack_index.int:
      s &= "=> "
    s &= $vm.frame.stack[i]
  echo s
  return NIL

proc core_vm_print_instructions*(vm: VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value =
  echo vm.cu
  return NIL

# Register all core functions in a namespace
proc init_core_namespace*(global_ns: Namespace) =
  # Core I/O
  global_ns["print".to_key()] = core_print.to_value()
  global_ns["println".to_key()] = core_println.to_value()

  # Assertions and debugging
  global_ns["assert".to_key()] = core_assert.to_value()
  global_ns["debug".to_key()] = core_debug.to_value()
  global_ns["trace_start".to_key()] = core_trace_start.to_value()
  global_ns["trace_end".to_key()] = core_trace_end.to_value()

  # Timing
  global_ns["sleep".to_key()] = core_sleep.to_value()
  global_ns["run_forever".to_key()] = core_run_forever.to_value()

  # Environment
  global_ns["get_env".to_key()] = core_get_env.to_value()
  global_ns["set_env".to_key()] = core_set_env.to_value()
  global_ns["has_env".to_key()] = core_has_env.to_value()

  # Encoding
  global_ns["base64".to_key()] = core_base64.to_value()
  global_ns["base64_decode".to_key()] = core_base64_decode.to_value()

  # VM debugging (in vm/ subnamespace)
  let vm_ns = new_namespace("vm")
  vm_ns["print_stack".to_key()] = core_vm_print_stack.to_value()
  vm_ns["print_instructions".to_key()] = core_vm_print_instructions.to_value()
  global_ns["vm".to_key()] = vm_ns.to_value()