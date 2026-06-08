import std/[dynlib, os, strutils, terminal]

when not defined(windows):
  import std/posix

type
  ReplInputBackendKind* = enum
    RibPlain
    RibReadline

  ReplInputReadStatus* = enum
    RirsLine
    RirsEof
    RirsInterrupt

  ReadlineProc = proc(prompt: cstring): cstring {.cdecl.}
  AddHistoryProc = proc(line: cstring) {.cdecl.}
  HistoryInitProc = proc() {.cdecl.}
  ReadlineReplaceLineProc = proc(line: cstring, clear_undo: cint) {.cdecl.}
  ReadlineCrLfProc = proc(): cint {.cdecl.}
  ReadlineCallbackHandlerProc = proc(line: cstring) {.cdecl.}
  ReadlineCallbackInstallProc = proc(prompt: cstring, handler: ReadlineCallbackHandlerProc) {.cdecl.}
  ReadlineCallbackReadCharProc = proc() {.cdecl.}
  ReadlineCallbackRemoveProc = proc() {.cdecl.}
  ReplInputInterruptPredicate* = proc(): bool {.gcsafe.}

  ReplInputReader* = ref object
    backend*: ReplInputBackendKind
    input_file: File
    close_input: bool
    readline_lib: LibHandle
    history_lib: LibHandle
    readline_fn: ReadlineProc
    add_history_fn: AddHistoryProc
    using_history_fn: HistoryInitProc
    clear_history_fn: HistoryInitProc
    replace_line_fn: ReadlineReplaceLineProc
    crlf_fn: ReadlineCrLfProc
    callback_install_fn: ReadlineCallbackInstallProc
    callback_read_char_fn: ReadlineCallbackReadCharProc
    callback_remove_fn: ReadlineCallbackRemoveProc
    done_ptr: ptr cint
    last_history_entry: string

var active_readline_reader {.threadvar.}: ReplInputReader
var callback_reader {.threadvar.}: ReplInputReader
var callback_done {.threadvar.}: bool
var callback_eof {.threadvar.}: bool
var callback_input {.threadvar.}: string
var callback_removed {.threadvar.}: bool

proc c_free(mem: pointer) {.importc: "free", header: "<stdlib.h>".}

proc should_use_readline_backend*(stdin_is_tty: bool, backend_available: bool): bool =
  stdin_is_tty and backend_available

proc should_record_repl_history_entry*(entry: string, last_entry: string): bool =
  entry.len > 0 and entry != last_entry

proc readline_candidates(): seq[string] =
  when defined(macosx) or defined(macos):
    @[
      "/opt/homebrew/opt/readline/lib/libreadline.8.dylib",
      "/opt/homebrew/opt/readline/lib/libreadline.dylib",
      "/usr/local/opt/readline/lib/libreadline.8.dylib",
      "/usr/local/opt/readline/lib/libreadline.dylib",
      "libreadline.8.dylib",
      "libreadline.dylib",
    ]
  elif defined(linux):
    @["libreadline.so.8", "libreadline.so"]
  else:
    @[]

proc history_candidates(): seq[string] =
  when defined(macosx) or defined(macos):
    @[
      "/opt/homebrew/opt/readline/lib/libhistory.8.dylib",
      "/opt/homebrew/opt/readline/lib/libhistory.dylib",
      "/usr/local/opt/readline/lib/libhistory.8.dylib",
      "/usr/local/opt/readline/lib/libhistory.dylib",
      "libhistory.8.dylib",
      "libhistory.dylib",
    ]
  elif defined(linux):
    @["libhistory.so.8", "libhistory.so"]
  else:
    @[]

proc load_first_library(candidates: seq[string]): LibHandle =
  for candidate in candidates:
    result = loadLib(candidate)
    if not result.isNil:
      return result

proc unload_handle(handle: var LibHandle) =
  if not handle.isNil:
    unloadLib(handle)
    handle = nil

proc resolve_symbol(handles: openArray[LibHandle], name: cstring): pointer =
  for handle in handles:
    if handle.isNil:
      continue
    result = handle.symAddr(name)
    if not result.isNil:
      return result

proc try_enable_readline(reader: ReplInputReader): bool =
  reader.readline_lib = load_first_library(readline_candidates())
  if reader.readline_lib.isNil:
    return false

  reader.history_lib = load_first_library(history_candidates())

  let handles =
    if reader.history_lib.isNil or reader.history_lib == reader.readline_lib:
      @[reader.readline_lib]
    else:
      @[reader.readline_lib, reader.history_lib]

  let readline_sym = resolve_symbol(handles, "readline")
  let add_history_sym = resolve_symbol(handles, "add_history")
  let using_history_sym = resolve_symbol(handles, "using_history")
  let clear_history_sym = resolve_symbol(handles, "clear_history")
  let replace_line_sym = resolve_symbol(handles, "rl_replace_line")
  let crlf_sym = resolve_symbol(handles, "rl_crlf")
  let callback_install_sym = resolve_symbol(handles, "rl_callback_handler_install")
  let callback_read_char_sym = resolve_symbol(handles, "rl_callback_read_char")
  let callback_remove_sym = resolve_symbol(handles, "rl_callback_handler_remove")
  let done_sym = resolve_symbol(handles, "rl_done")

  if readline_sym.isNil or add_history_sym.isNil or
      using_history_sym.isNil or clear_history_sym.isNil:
    unload_handle(reader.history_lib)
    unload_handle(reader.readline_lib)
    return false

  reader.readline_fn = cast[ReadlineProc](readline_sym)
  reader.add_history_fn = cast[AddHistoryProc](add_history_sym)
  reader.using_history_fn = cast[HistoryInitProc](using_history_sym)
  reader.clear_history_fn = cast[HistoryInitProc](clear_history_sym)
  if not replace_line_sym.isNil:
    reader.replace_line_fn = cast[ReadlineReplaceLineProc](replace_line_sym)
  if not crlf_sym.isNil:
    reader.crlf_fn = cast[ReadlineCrLfProc](crlf_sym)
  if not callback_install_sym.isNil:
    reader.callback_install_fn = cast[ReadlineCallbackInstallProc](callback_install_sym)
  if not callback_read_char_sym.isNil:
    reader.callback_read_char_fn = cast[ReadlineCallbackReadCharProc](callback_read_char_sym)
  if not callback_remove_sym.isNil:
    reader.callback_remove_fn = cast[ReadlineCallbackRemoveProc](callback_remove_sym)
  if not done_sym.isNil:
    reader.done_ptr = cast[ptr cint](done_sym)
  reader.using_history_fn()
  reader.clear_history_fn()
  reader.backend = RibReadline
  return true

proc interrupt_active_readline*(): bool =
  let reader = active_readline_reader
  if reader.isNil or reader.backend != RibReadline:
    return false

  if not reader.done_ptr.isNil:
    reader.done_ptr[] = 1
  if not reader.replace_line_fn.isNil:
    reader.replace_line_fn("".cstring, 0)
  if not reader.crlf_fn.isNil:
    discard reader.crlf_fn()
  true

proc readline_callback_handler(line: cstring) {.cdecl.} =
  let reader = callback_reader
  if not reader.isNil and not reader.callback_remove_fn.isNil:
    reader.callback_remove_fn()
    callback_removed = true

  callback_done = true
  if line.isNil:
    callback_eof = true
    callback_input = ""
    return

  callback_input = $line
  c_free(line)

  if not reader.isNil and not reader.add_history_fn.isNil:
    let trimmed = callback_input.strip()
    if should_record_repl_history_entry(trimmed, reader.last_history_entry):
      reader.add_history_fn(trimmed.cstring)
      reader.last_history_entry = trimmed

proc supports_callback_input(reader: ReplInputReader): bool =
  not reader.isNil and reader.backend == RibReadline and
    not reader.callback_install_fn.isNil and
    not reader.callback_read_char_fn.isNil and
    not reader.callback_remove_fn.isNil

when not defined(windows):
  proc stdin_ready(timeout_ms: int): bool =
    while true:
      var read_fds: TFdSet = default(TFdSet)
      FD_ZERO(read_fds)
      FD_SET(0, read_fds)

      var tv = Timeval(
        tv_sec: posix.Time(timeout_ms div 1000),
        tv_usec: Suseconds((timeout_ms mod 1000) * 1000)
      )
      let rc = posix.select(1, addr(read_fds), nil, nil, addr(tv))
      if rc < 0:
        let err = osLastError()
        if err.cint == EINTR:
          return false
        raiseOSError(err)
      return rc > 0 and FD_ISSET(0, read_fds) != 0'i32

proc init_plain_input(reader: ReplInputReader) =
  reader.backend = RibPlain
  reader.input_file = stdin
  reader.close_input = false

  if isatty(stdin):
    var tty: File
    if open(tty, "/dev/tty", fmRead):
      reader.input_file = tty
      reader.close_input = true

proc new_repl_input_reader*(): ReplInputReader =
  new(result)
  if should_use_readline_backend(isatty(stdin), true) and result.try_enable_readline():
    return result
  result.init_plain_input()

proc close*(reader: ReplInputReader) =
  if reader.isNil:
    return

  if reader.backend == RibReadline and not reader.clear_history_fn.isNil:
    reader.clear_history_fn()

  if reader.close_input:
    reader.input_file.close()
    reader.close_input = false

  if not reader.history_lib.isNil and reader.history_lib != reader.readline_lib:
    unload_handle(reader.history_lib)
  unload_handle(reader.readline_lib)
  reader.history_lib = nil

proc read_line*(reader: ReplInputReader, prompt: string, input: var string): bool =
  if reader.isNil:
    return false

  case reader.backend
  of RibReadline:
    active_readline_reader = reader
    let raw_line = reader.readline_fn(prompt.cstring)
    active_readline_reader = nil
    if raw_line.isNil:
      if prompt.len > 0:
        echo ""
      return false

    input = $raw_line
    c_free(raw_line)

    let trimmed = input.strip()
    if should_record_repl_history_entry(trimmed, reader.last_history_entry):
      reader.add_history_fn(trimmed.cstring)
      reader.last_history_entry = trimmed
    return true
  of RibPlain:
    stdout.write(prompt)
    stdout.flushFile()
    if not reader.input_file.readLine(input):
      if prompt.len > 0:
        echo ""
      return false
    return true

proc read_event*(reader: ReplInputReader, prompt: string, input: var string,
                 interrupted: ReplInputInterruptPredicate): ReplInputReadStatus =
  if reader.isNil:
    return RirsEof

  if not reader.supports_callback_input():
    if reader.read_line(prompt, input):
      if interrupted != nil and interrupted():
        return RirsInterrupt
      return RirsLine
    if interrupted != nil and interrupted():
      return RirsInterrupt
    return RirsEof

  callback_reader = reader
  callback_done = false
  callback_eof = false
  callback_input = ""
  callback_removed = false
  active_readline_reader = reader
  reader.callback_install_fn(prompt.cstring, readline_callback_handler)
  defer:
    if not callback_removed:
      reader.callback_remove_fn()
    active_readline_reader = nil
    callback_reader = nil

  while not callback_done:
    if interrupted != nil and interrupted():
      discard interrupt_active_readline()
      input = ""
      return RirsInterrupt

    when defined(windows):
      reader.callback_read_char_fn()
    else:
      if stdin_ready(50):
        reader.callback_read_char_fn()

  if interrupted != nil and interrupted():
    input = ""
    return RirsInterrupt
  if callback_eof:
    input = ""
    return RirsEof

  input = callback_input
  RirsLine
