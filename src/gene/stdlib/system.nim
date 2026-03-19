{.push warning[ResultShadowed]: off.}
import os
import ../types
when defined(gene_wasm):
  import ../wasm_host_abi

when not defined(gene_wasm):
  import tables, osproc, strtabs, strutils, locks
  when not defined(windows):
    import posix, times

# System functions for the Gene standard library

const
  PROCESS_ID_KEY = "__proc_id__"
  PROCESS_PID_KEY = "pid"
  PROCESS_EXIT_CODE_KEY = "exit_code"
  PROCESS_READ_CHUNK_SIZE = 4096

when not defined(gene_wasm):
  type
    ManagedProcess = ref object
      process: Process
      pid: int
      stderr_to_stdout: bool
      stdin_closed: bool
      stdout_eof: bool
      stderr_eof: bool
      exit_code_known: bool
      exit_code: int
      stdout_buffer: string
      stderr_buffer: string

  var process_class_global: Class
  var process_table: Table[int, ManagedProcess] = initTable[int, ManagedProcess]()
  var next_process_id = 1
  var process_table_lock: Lock
  initLock(process_table_lock)

template ensure_process_support(op_name: string) =
  when defined(gene_wasm):
    raise_wasm_unsupported(op_name)
  elif defined(windows):
    raise new_exception(types.Exception, "system/Process is only supported on Unix/macOS")

when not defined(gene_wasm):
  proc key_to_string(key: types.Key): string =
    get_symbol(cast[int](key))

  proc parse_timeout_ms(value: Value, context: string): int =
    let timeout_seconds =
      case value.kind
      of VkInt:
        value.to_int().float64
      of VkFloat:
        value.to_float()
      else:
        raise new_exception(types.Exception, context & " requires ^timeout to be an int or float")

    if timeout_seconds < 0:
      raise new_exception(types.Exception, context & " requires a non-negative ^timeout")
    int(timeout_seconds * 1000.0)

  proc require_timeout_ms(args: ptr UncheckedArray[Value], has_keyword_args: bool, context: string): int =
    if not has_keyword_args or not has_keyword_arg(args, "timeout"):
      raise new_exception(types.Exception, context & " requires ^timeout")
    parse_timeout_ms(get_keyword_arg(args, "timeout"), context)

  proc get_process_wrapper(self: Value): ManagedProcess =
    if self.kind != VkInstance:
      raise new_exception(types.Exception, "Process method must be called on a Process instance")

    let process_id_val = instance_props(self).getOrDefault(PROCESS_ID_KEY.to_key(), NIL)
    if process_id_val.kind != VkInt:
      raise new_exception(types.Exception, "Invalid Process instance")

    let process_id = process_id_val.to_int()
    {.cast(gcsafe).}:
      withLock(process_table_lock):
        if not process_table.hasKey(process_id):
          raise new_exception(types.Exception, "Process not found")
        result = process_table[process_id]

  proc set_process_exit_code(self: Value, wrapper: ManagedProcess) =
    if wrapper.exit_code_known:
      instance_props(self)[PROCESS_EXIT_CODE_KEY.to_key()] = wrapper.exit_code.to_value()
    else:
      instance_props(self)[PROCESS_EXIT_CODE_KEY.to_key()] = NIL

  proc build_env_table(env_val: Value): StringTableRef =
    if env_val == NIL:
      return nil
    if env_val.kind != VkMap:
      raise new_exception(types.Exception, "^env must be a map")

    result = newStringTable()
    for pair in envPairs():
      result[pair.key] = pair.value
    for key, value in map_data(env_val):
      result[key_to_string(key)] = value.str_no_quotes()

  when not defined(windows):
    const INVALID_PROCESS_HANDLE = FileHandle(-1)

    proc remaining_timeout_ms(deadline: float): int =
      max(0, int((deadline - epochTime()) * 1000.0))

    proc wait_for_readable(handle: FileHandle, timeout_ms: int): bool =
      if handle == INVALID_PROCESS_HANDLE:
        return false

      while true:
        var read_fds: TFdSet = default(TFdSet)
        FD_ZERO(read_fds)
        FD_SET(cint(handle), read_fds)

        if timeout_ms >= 0:
          var tv = Timeval(
            tv_sec: posix.Time(timeout_ms div 1000),
            tv_usec: Suseconds((timeout_ms mod 1000) * 1000)
          )
          let rc = posix.select(cint(int(handle) + 1), addr(read_fds), nil, nil, addr(tv))
          if rc < 0:
            let err = osLastError()
            if err.cint == EINTR:
              continue
            raiseOSError(err)
          return rc > 0 and FD_ISSET(cint(handle), read_fds) != 0'i32
        else:
          let rc = posix.select(cint(int(handle) + 1), addr(read_fds), nil, nil, nil)
          if rc < 0:
            let err = osLastError()
            if err.cint == EINTR:
              continue
            raiseOSError(err)
          return rc > 0 and FD_ISSET(cint(handle), read_fds) != 0'i32

    proc read_chunk(handle: FileHandle, buffer: var string, eof_flag: var bool) =
      if eof_flag or handle == INVALID_PROCESS_HANDLE:
        return

      var chunk = newString(PROCESS_READ_CHUNK_SIZE)
      while true:
        let bytes_read = posix.read(handle, addr chunk[0], PROCESS_READ_CHUNK_SIZE)
        if bytes_read < 0:
          let err = osLastError()
          if err.cint == EINTR:
            continue
          raiseOSError(err)
        if bytes_read == 0:
          eof_flag = true
        else:
          buffer.add(chunk[0..<bytes_read])
        return

    proc drain_available_bytes(handle: FileHandle, buffer: var string, eof_flag: var bool) =
      while not eof_flag and wait_for_readable(handle, 0):
        read_chunk(handle, buffer, eof_flag)

    proc shell_exit_code(status: cint): int =
      if WIFEXITED(status):
        WEXITSTATUS(status).int
      elif WIFSIGNALED(status):
        128 + WTERMSIG(status).int
      else:
        0

    proc sync_process_exit(self: Value, wrapper: ManagedProcess): bool =
      if wrapper.exit_code_known:
        set_process_exit_code(self, wrapper)
        return true
      if wrapper.process.is_nil:
        return false

      while true:
        var status: cint = 0
        let pid = waitpid(Pid(wrapper.pid), status, WNOHANG)
        if pid == 0:
          return false
        if pid < 0:
          let err = osLastError()
          if err.cint == EINTR:
            continue
          if err.cint == ECHILD:
            return wrapper.exit_code_known
          raiseOSError(err)

        wrapper.exit_code = shell_exit_code(status)
        wrapper.exit_code_known = true
        set_process_exit_code(self, wrapper)
        return true

    proc close_process_resources(wrapper: ManagedProcess) =
      if wrapper.process.is_nil:
        return
      try:
        close(wrapper.process)
      except CatchableError:
        discard
      wrapper.process = nil
      wrapper.stdin_closed = true
      wrapper.stdout_eof = true
      wrapper.stderr_eof = true

    proc close_stdin_handle(wrapper: ManagedProcess) =
      if wrapper.stdin_closed or wrapper.process.is_nil:
        return

      while true:
        let rc = posix.close(inputHandle(wrapper.process))
        if rc == 0:
          break
        let err = osLastError()
        if err.cint == EINTR:
          continue
        if err.cint == EBADF:
          break
        raiseOSError(err)
      wrapper.stdin_closed = true

    proc write_all(wrapper: ManagedProcess, content: string) =
      if wrapper.process.is_nil or wrapper.exit_code_known:
        raise new_exception(types.Exception, "Process is no longer running")
      if wrapper.stdin_closed:
        raise new_exception(types.Exception, "Process stdin is closed")
      if content.len == 0:
        return

      var offset = 0
      while offset < content.len:
        let bytes_written = posix.write(
          inputHandle(wrapper.process),
          unsafeAddr(content[offset]),
          content.len - offset
        )
        if bytes_written < 0:
          let err = osLastError()
          if err.cint == EINTR:
            continue
          raiseOSError(err)
        offset += bytes_written.int

    proc wait_for_exit(self: Value, wrapper: ManagedProcess, timeout_ms: int): bool =
      if sync_process_exit(self, wrapper):
        close_process_resources(wrapper)
        return true

      let deadline = epochTime() + timeout_ms.float / 1000.0
      while true:
        if sync_process_exit(self, wrapper):
          close_process_resources(wrapper)
          return true
        let remaining = remaining_timeout_ms(deadline)
        if remaining <= 0:
          return false
        sleep(min(remaining, 10))

    proc consume_prefix(buffer: var string, count: int): string =
      if count <= 0:
        return ""
      let take = min(count, buffer.len)
      result = buffer[0..<take]
      if take >= buffer.len:
        buffer.setLen(0)
      else:
        buffer = buffer[take..^1]

    proc strip_line_break(line: string): string =
      result = line
      if result.len > 0 and result[^1] == '\n':
        result.setLen(result.len - 1)
      if result.len > 0 and result[^1] == '\r':
        result.setLen(result.len - 1)

    proc send_signal(wrapper: ManagedProcess, signal_name: string) =
      if wrapper.process.is_nil or wrapper.exit_code_known:
        return

      let signal_num =
        case signal_name.toUpperAscii()
        of "INT":
          SIGINT
        of "TERM":
          SIGTERM
        of "KILL":
          SIGKILL
        else:
          raise new_exception(types.Exception, "Unsupported signal: " & signal_name)

      if posix.kill(Pid(wrapper.pid), signal_num) != 0'i32:
        let err = osLastError()
        if err.cint == ESRCH:
          return
        raiseOSError(err)

# Process execution
proc system_exec*(vm: ptr VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value =
  when defined(gene_wasm):
    raise_wasm_unsupported("process_exec")
  else:
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
  when defined(gene_wasm):
    raise_wasm_unsupported("process_shell")
  else:
    if arg_count < 1:
      raise new_exception(types.Exception, "shell requires 1 argument (command)")

    let cmd_arg = get_positional_arg(args, 0, has_keyword_args)
    if cmd_arg.kind != VkString:
      raise new_exception(types.Exception, "shell requires a string command")

    let cmd = cmd_arg.str
    try:
      let result = execCmdEx(cmd)
      # Return a map with output and exit_code
      var result_map = initTable[types.Key, Value]()
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

proc process_constructor(vm: ptr VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value {.gcsafe.} =
  raise new_exception(types.Exception, "Process cannot be constructed directly - use system/Process/start")

proc process_start(vm: ptr VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value {.gcsafe.} =
  ensure_process_support("process_start")

  when not defined(gene_wasm) and not defined(windows):
    let positional = get_positional_count(arg_count, has_keyword_args)
    if positional < 1:
      raise new_exception(types.Exception, "Process/start requires at least 1 argument (command)")

    let command_arg = get_positional_arg(args, 0, has_keyword_args)
    if command_arg.kind != VkString:
      raise new_exception(types.Exception, "Process/start requires a string command")

    var process_args: seq[string] = @[]
    for i in 1..<positional:
      process_args.add(get_positional_arg(args, i, has_keyword_args).str_no_quotes())

    let cwd_val = if has_keyword_args: get_keyword_arg(args, "cwd") else: NIL
    let cwd =
      if cwd_val == NIL:
        ""
      elif cwd_val.kind == VkString:
        cwd_val.str
      else:
        raise new_exception(types.Exception, "^cwd must be a string")

    let env_val = if has_keyword_args: get_keyword_arg(args, "env") else: NIL
    let stderr_to_stdout = if has_keyword_args: get_keyword_arg(args, "stderr_to_stdout").to_bool() else: false

    var options = {poUsePath}
    if stderr_to_stdout:
      options.incl(poStdErrToStdOut)

    var process_handle: Process = nil
    try:
      process_handle = startProcess(
        command = command_arg.str,
        workingDir = cwd,
        args = process_args,
        env = build_env_table(env_val),
        options = options
      )
    except OSError as e:
      raise new_exception(types.Exception, "Failed to start process: " & e.msg)
    except IOError as e:
      raise new_exception(types.Exception, "Failed to start process: " & e.msg)

    let wrapper = ManagedProcess(
      process: process_handle,
      pid: processID(process_handle),
      stderr_to_stdout: stderr_to_stdout,
      stdin_closed: false,
      stdout_eof: false,
      stderr_eof: stderr_to_stdout,
      exit_code_known: false,
      exit_code: 0,
      stdout_buffer: "",
      stderr_buffer: ""
    )

    var process_id: int
    {.cast(gcsafe).}:
      withLock(process_table_lock):
        process_id = next_process_id
        next_process_id.inc()
        process_table[process_id] = wrapper

    let instance = ({.cast(gcsafe).}:
      let process_class =
        if process_class_global != nil: process_class_global
        else: new_class("Process")
      new_instance_value(process_class)
    )
    instance_props(instance)[PROCESS_ID_KEY.to_key()] = process_id.to_value()
    instance_props(instance)[PROCESS_PID_KEY.to_key()] = wrapper.pid.to_value()
    instance_props(instance)[PROCESS_EXIT_CODE_KEY.to_key()] = NIL
    return instance

proc process_write(vm: ptr VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value {.gcsafe.} =
  ensure_process_support("process_write")

  when not defined(gene_wasm) and not defined(windows):
    if get_method_arg_count(arg_count, has_keyword_args) < 1:
      raise new_exception(types.Exception, "Process.write requires content")

    let self = get_self(args, has_keyword_args)
    let wrapper = get_process_wrapper(self)
    let content = get_method_arg(args, 0, has_keyword_args).str_no_quotes()
    try:
      write_all(wrapper, content)
      return NIL
    except OSError as e:
      raise new_exception(types.Exception, "Failed to write to process stdin: " & e.msg)
    except IOError as e:
      raise new_exception(types.Exception, "Failed to write to process stdin: " & e.msg)

proc process_write_line(vm: ptr VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value {.gcsafe.} =
  ensure_process_support("process_write_line")

  when not defined(gene_wasm) and not defined(windows):
    if get_method_arg_count(arg_count, has_keyword_args) < 1:
      raise new_exception(types.Exception, "Process.write_line requires content")

    let self = get_self(args, has_keyword_args)
    let wrapper = get_process_wrapper(self)
    let content = get_method_arg(args, 0, has_keyword_args).str_no_quotes() & "\n"
    try:
      write_all(wrapper, content)
      return NIL
    except OSError as e:
      raise new_exception(types.Exception, "Failed to write to process stdin: " & e.msg)
    except IOError as e:
      raise new_exception(types.Exception, "Failed to write to process stdin: " & e.msg)

proc process_close_stdin(vm: ptr VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value {.gcsafe.} =
  ensure_process_support("process_close_stdin")

  when not defined(gene_wasm) and not defined(windows):
    let self = get_self(args, has_keyword_args)
    let wrapper = get_process_wrapper(self)
    try:
      close_stdin_handle(wrapper)
      return NIL
    except OSError as e:
      raise new_exception(types.Exception, "Failed to close process stdin: " & e.msg)

proc process_read_line(vm: ptr VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value {.gcsafe.} =
  ensure_process_support("process_read_line")

  when not defined(gene_wasm) and not defined(windows):
    let self = get_self(args, has_keyword_args)
    let wrapper = get_process_wrapper(self)
    let timeout_ms = require_timeout_ms(args, has_keyword_args, "Process.read_line")
    let deadline = epochTime() + timeout_ms.float / 1000.0

    while true:
      let newline_idx = wrapper.stdout_buffer.find('\n')
      if newline_idx >= 0:
        let line = consume_prefix(wrapper.stdout_buffer, newline_idx + 1)
        return strip_line_break(line).to_value()

      if not wrapper.process.is_nil and not wrapper.stdout_eof:
        let remaining = remaining_timeout_ms(deadline)
        if remaining <= 0:
          return NIL
        try:
          if wait_for_readable(outputHandle(wrapper.process), remaining):
            read_chunk(outputHandle(wrapper.process), wrapper.stdout_buffer, wrapper.stdout_eof)
            discard sync_process_exit(self, wrapper)
            continue
          return NIL
        except OSError as e:
          raise new_exception(types.Exception, "Failed to read process stdout: " & e.msg)
      else:
        discard sync_process_exit(self, wrapper)
        if wrapper.stdout_buffer.len > 0:
          return strip_line_break(consume_prefix(wrapper.stdout_buffer, wrapper.stdout_buffer.len)).to_value()
        return NIL

proc process_read_until(vm: ptr VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value {.gcsafe.} =
  ensure_process_support("process_read_until")

  when not defined(gene_wasm) and not defined(windows):
    if get_method_arg_count(arg_count, has_keyword_args) < 1:
      raise new_exception(types.Exception, "Process.read_until requires a delimiter")

    let self = get_self(args, has_keyword_args)
    let wrapper = get_process_wrapper(self)
    let delimiter_arg = get_method_arg(args, 0, has_keyword_args)
    if delimiter_arg.kind != VkString:
      raise new_exception(types.Exception, "Process.read_until requires a string delimiter")
    let delimiter = delimiter_arg.str
    if delimiter.len == 0:
      raise new_exception(types.Exception, "Process.read_until requires a non-empty delimiter")

    let timeout_ms = require_timeout_ms(args, has_keyword_args, "Process.read_until")
    let deadline = epochTime() + timeout_ms.float / 1000.0

    while true:
      let delimiter_idx = wrapper.stdout_buffer.find(delimiter)
      if delimiter_idx >= 0:
        return consume_prefix(wrapper.stdout_buffer, delimiter_idx + delimiter.len).to_value()

      if not wrapper.process.is_nil and not wrapper.stdout_eof:
        let remaining = remaining_timeout_ms(deadline)
        if remaining <= 0:
          return NIL
        try:
          if wait_for_readable(outputHandle(wrapper.process), remaining):
            read_chunk(outputHandle(wrapper.process), wrapper.stdout_buffer, wrapper.stdout_eof)
            discard sync_process_exit(self, wrapper)
            continue
          return NIL
        except OSError as e:
          raise new_exception(types.Exception, "Failed to read process stdout: " & e.msg)
      else:
        discard sync_process_exit(self, wrapper)
        if wrapper.stdout_buffer.len > 0:
          return consume_prefix(wrapper.stdout_buffer, wrapper.stdout_buffer.len).to_value()
        return NIL

proc process_read_available(vm: ptr VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value {.gcsafe.} =
  ensure_process_support("process_read_available")

  when not defined(gene_wasm) and not defined(windows):
    let self = get_self(args, has_keyword_args)
    let wrapper = get_process_wrapper(self)
    try:
      if not wrapper.process.is_nil and not wrapper.stdout_eof:
        drain_available_bytes(outputHandle(wrapper.process), wrapper.stdout_buffer, wrapper.stdout_eof)
      discard sync_process_exit(self, wrapper)
      let data = consume_prefix(wrapper.stdout_buffer, wrapper.stdout_buffer.len)
      return data.to_value()
    except OSError as e:
      raise new_exception(types.Exception, "Failed to read process stdout: " & e.msg)

proc process_read_stderr(vm: ptr VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value {.gcsafe.} =
  ensure_process_support("process_read_stderr")

  when not defined(gene_wasm) and not defined(windows):
    let self = get_self(args, has_keyword_args)
    let wrapper = get_process_wrapper(self)
    if wrapper.stderr_to_stdout:
      raise new_exception(types.Exception, "stderr is merged into stdout for this Process")

    let timeout_ms = require_timeout_ms(args, has_keyword_args, "Process.read_stderr")
    let deadline = epochTime() + timeout_ms.float / 1000.0

    while true:
      if wrapper.stderr_buffer.len > 0:
        if not wrapper.process.is_nil and not wrapper.stderr_eof:
          drain_available_bytes(errorHandle(wrapper.process), wrapper.stderr_buffer, wrapper.stderr_eof)
        return consume_prefix(wrapper.stderr_buffer, wrapper.stderr_buffer.len).to_value()

      if not wrapper.process.is_nil and not wrapper.stderr_eof:
        let remaining = remaining_timeout_ms(deadline)
        if remaining <= 0:
          return NIL
        try:
          if wait_for_readable(errorHandle(wrapper.process), remaining):
            read_chunk(errorHandle(wrapper.process), wrapper.stderr_buffer, wrapper.stderr_eof)
            discard sync_process_exit(self, wrapper)
            continue
          return NIL
        except OSError as e:
          raise new_exception(types.Exception, "Failed to read process stderr: " & e.msg)
      else:
        discard sync_process_exit(self, wrapper)
        return "".to_value()

proc process_alive(vm: ptr VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value {.gcsafe.} =
  ensure_process_support("process_alive")

  when not defined(gene_wasm) and not defined(windows):
    let self = get_self(args, has_keyword_args)
    let wrapper = get_process_wrapper(self)
    discard sync_process_exit(self, wrapper)
    return (not wrapper.exit_code_known).to_value()

proc process_signal(vm: ptr VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value {.gcsafe.} =
  ensure_process_support("process_signal")

  when not defined(gene_wasm) and not defined(windows):
    if get_method_arg_count(arg_count, has_keyword_args) < 1:
      raise new_exception(types.Exception, "Process.signal requires a signal name")

    let self = get_self(args, has_keyword_args)
    let wrapper = get_process_wrapper(self)
    discard sync_process_exit(self, wrapper)
    let signal_arg = get_method_arg(args, 0, has_keyword_args)
    if signal_arg.kind notin {VkString, VkSymbol}:
      raise new_exception(types.Exception, "Process.signal requires a string signal name")

    try:
      send_signal(wrapper, signal_arg.str)
      return NIL
    except OSError as e:
      raise new_exception(types.Exception, "Failed to signal process: " & e.msg)

proc process_wait(vm: ptr VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value {.gcsafe.} =
  ensure_process_support("process_wait")

  when not defined(gene_wasm) and not defined(windows):
    let self = get_self(args, has_keyword_args)
    let wrapper = get_process_wrapper(self)
    let timeout_ms = require_timeout_ms(args, has_keyword_args, "Process.wait")

    try:
      if wait_for_exit(self, wrapper, timeout_ms):
        return wrapper.exit_code.to_value()
      return NIL
    except OSError as e:
      raise new_exception(types.Exception, "Failed while waiting for process: " & e.msg)

proc process_shutdown(vm: ptr VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value {.gcsafe.} =
  ensure_process_support("process_shutdown")

  when not defined(gene_wasm) and not defined(windows):
    let self = get_self(args, has_keyword_args)
    let wrapper = get_process_wrapper(self)
    let timeout_ms = require_timeout_ms(args, has_keyword_args, "Process.shutdown")
    let first_wait = timeout_ms div 2
    let second_wait = timeout_ms - first_wait

    try:
      close_stdin_handle(wrapper)
      if wait_for_exit(self, wrapper, first_wait):
        return wrapper.exit_code.to_value()

      send_signal(wrapper, "TERM")
      if wait_for_exit(self, wrapper, second_wait):
        return wrapper.exit_code.to_value()

      send_signal(wrapper, "KILL")
      if wait_for_exit(self, wrapper, 1000):
        return wrapper.exit_code.to_value()
      return NIL
    except OSError as e:
      raise new_exception(types.Exception, "Failed during process shutdown: " & e.msg)

# Process class (for spawning processes)
proc init_process_class*(): Class =
  result = new_class("Process")
  when not defined(gene_wasm):
    process_class_global = result

  result.def_native_constructor(process_constructor)
  result.def_static_method("start", process_start)
  result.def_native_method("write", process_write)
  result.def_native_method("write_line", process_write_line)
  result.def_native_method("read_line", process_read_line)
  result.def_native_method("read_until", process_read_until)
  result.def_native_method("read_available", process_read_available)
  result.def_native_method("read_stderr", process_read_stderr)
  result.def_native_method("signal", process_signal)
  result.def_native_method("close_stdin", process_close_stdin)
  result.def_native_method("wait", process_wait)
  result.def_native_method("shutdown", process_shutdown)
  result.def_native_method("alive?", process_alive)

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

{.pop.}
