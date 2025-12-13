{.push warning[ResultShadowed]: off.}
import tables, os, osproc
import ../types

# System functions for the Gene standard library

# Process execution
proc system_exec*(vm: ptr VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value =
  if arg_count < 1:
    raise new_exception(types.Exception, "exec requires at least 1 argument (command)")

  let cmd_arg = get_positional_arg(args, 0, has_keyword_args)
  if cmd_arg.kind != VkString:
    raise new_exception(types.Exception, "exec requires a string command")

  var cmd = cmd_arg.str
  var cmd_args: seq[string] = @[]

  # Collect additional arguments
  for i in 1..<get_positional_count(arg_count, has_keyword_args):
    let arg = get_positional_arg(args, i, has_keyword_args)
    if arg.kind == VkString:
      cmd_args.add(arg.str)
    else:
      cmd_args.add(arg.str_no_quotes())

  try:
    let result = execProcess(cmd, args = cmd_args, options = {poUsePath})
    return result.to_value()
  except OSError as e:
    raise new_exception(types.Exception, "Failed to execute command: " & e.msg)

proc system_shell*(vm: ptr VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value =
  if arg_count < 1:
    raise new_exception(types.Exception, "shell requires 1 argument (command)")

  let cmd_arg = get_positional_arg(args, 0, has_keyword_args)
  if cmd_arg.kind != VkString:
    raise new_exception(types.Exception, "shell requires a string command")

  let cmd = cmd_arg.str
  try:
    let result = execCmdEx(cmd)
    # Return a map with output and exit_code
    var result_map = initTable[Key, Value]()
    result_map["output".to_key()] = result.output.to_value()
    result_map["exit_code".to_key()] = result.exitCode.int64.to_value()
    return new_map_value(result_map)
  except OSError as e:
    raise new_exception(types.Exception, "Failed to execute shell command: " & e.msg)

# Current working directory
proc system_cwd*(vm: ptr VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value =
  return getCurrentDir().to_value()

proc system_cd*(vm: ptr VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value =
  if arg_count < 1:
    raise new_exception(types.Exception, "cd requires 1 argument (path)")

  let path_arg = get_positional_arg(args, 0, has_keyword_args)
  if path_arg.kind != VkString:
    raise new_exception(types.Exception, "cd requires a string path")

  let path = path_arg.str
  try:
    setCurrentDir(path)
    return NIL
  except OSError as e:
    raise new_exception(types.Exception, "Failed to change directory: " & e.msg)

# Exit
proc system_exit*(vm: ptr VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value =
  var exit_code = 0
  if arg_count > 0:
    let code_arg = get_positional_arg(args, 0, has_keyword_args)
    if code_arg.kind == VkInt:
      exit_code = code_arg.int64.int

  quit(exit_code)

# Command line arguments
proc system_args*(vm: ptr VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value =
  var args_array: seq[Value] = @[]
  for i in 1..paramCount():
    args_array.add(paramStr(i).to_value())
  return new_array_value(args_array)

# Platform information
proc system_os*(vm: ptr VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value =
  when defined(windows):
    return "windows".to_value()
  elif defined(macosx):
    return "macos".to_value()
  elif defined(linux):
    return "linux".to_value()
  elif defined(freebsd):
    return "freebsd".to_value()
  elif defined(openbsd):
    return "openbsd".to_value()
  elif defined(netbsd):
    return "netbsd".to_value()
  else:
    return "unknown".to_value()

proc system_arch*(vm: ptr VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value =
  when defined(amd64):
    return "amd64".to_value()
  elif defined(i386):
    return "i386".to_value()
  elif defined(arm):
    return "arm".to_value()
  elif defined(arm64):
    return "arm64".to_value()
  else:
    return "unknown".to_value()

# Process class (for spawning processes)
proc init_process_class*(): Class =
  result = new_class("Process")

  # TODO: Add process methods like:
  # - start(command, args)
  # - wait()
  # - kill()
  # - is_running()
  # - get_output()
  # - get_error()
  # - get_exit_code()

# Register all system functions in a namespace
proc init_system_namespace*(global_ns: Namespace) =
  let system_ns = new_namespace("system")

  # Process execution
  system_ns["exec".to_key()] = system_exec.to_value()
  system_ns["shell".to_key()] = system_shell.to_value()

  # Directory operations
  system_ns["cwd".to_key()] = system_cwd.to_value()
  system_ns["cd".to_key()] = system_cd.to_value()

  # Exit
  system_ns["exit".to_key()] = system_exit.to_value()

  # Arguments
  system_ns["args".to_key()] = system_args.to_value()

  # Platform info
  system_ns["os".to_key()] = system_os.to_value()
  system_ns["arch".to_key()] = system_arch.to_value()

  # Process class
  let process_class = init_process_class()
  let process_class_ref = new_ref(VkClass)
  process_class_ref.class = process_class
  system_ns["Process".to_key()] = process_class_ref.to_ref_value()

  global_ns["system".to_key()] = system_ns.to_value()

  # Also add commonly used functions to global namespace
  global_ns["exit".to_key()] = system_exit.to_value()
  global_ns["cwd".to_key()] = system_cwd.to_value()
  global_ns["args".to_key()] = system_args.to_value()

{.pop.}
