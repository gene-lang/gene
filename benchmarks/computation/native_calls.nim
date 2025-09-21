when isMainModule:
  import times, os, strformat, strutils

  import ../../src/gene/types
  import ../../src/gene/parser
  import ../../src/gene/compiler
  import ../../src/gene/vm

  proc native_f(vm: VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value {.gcsafe, nimcall.} =
    discard

  var repeats = 1000
  var callsPerRepeat = 100
  let args = command_line_params()
  if args.len > 0:
    repeats = parseInt(args[0])
  if args.len > 1:
    callsPerRepeat = parseInt(args[1])

  init_app_and_vm()

  var callList: seq[string] = @[]
  for _ in 0..<callsPerRepeat:
    callList.add("    (native_f)")
  let callBlock = callList.join("\n")

  let code = fmt"""
    (fn call_once [] nil)
    (repeat {repeats}
{callBlock})
  """

  let compiled = compile(read_all(code))

  let ns = new_namespace("call_burst")
  let native_f_ref = new_ref(VkNativeFn)
  native_f_ref.native_fn = native_f
  ns["native_f".to_key()] = native_f_ref.to_ref_value()
  VM.frame.update(new_frame(ns))
  VM.cu = compiled
  VM.trace = get_env("TRACE") == "1"

  let start = cpuTime()
  discard VM.exec()
  let duration = cpuTime() - start

  let totalCalls = repeats * callsPerRepeat
  let callsPerSecond = if duration > 0: totalCalls.float / duration else: 0.0

  echo fmt"repeat count: {repeats}"
  echo fmt"calls per repeat: {callsPerRepeat}"
  echo fmt"total calls: {totalCalls}"
  echo fmt"duration: {duration:.6f} seconds"
  echo fmt"Native calls/sec: {callsPerSecond:.0f}"
