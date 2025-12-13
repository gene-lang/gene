when isMainModule:
  import times, os, strformat, strutils

  import ../../src/gene/types
  import ../../src/gene/parser
  import ../../src/gene/compiler
  import ../../src/gene/vm

  proc native_f0(vm: ptr VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value {.gcsafe, nimcall.} =
    # echo "native_f0"
    return NIL

  proc native_f1(vm: ptr VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value {.gcsafe, nimcall.} =
    # {.cast(gcsafe).}:
    #   echo fmt"native_f1 {args[0]}"
    return NIL

  var repeats = 1000
  var callsPerRepeat = 100
  let args = command_line_params()
  if args.len > 0:
    repeats = parseInt(args[0])
  if args.len > 1:
    callsPerRepeat = parseInt(args[1])

  init_app_and_vm()

  proc runBenchmark(code, label: string, ns: Namespace) =
    let compiled = compile(read_all(code))
    VM.frame.update(new_frame(ns))
    VM.cu = compiled
    VM.trace = get_env("TRACE") == "1"

    let start = cpuTime()
    discard VM.exec()
    let duration = cpuTime() - start

    let totalCalls = repeats * callsPerRepeat
    let callsPerSecond = if duration > 0: totalCalls.float / duration else: 0.0

    echo fmt"{label}:"
    echo fmt"  repeat count: {repeats}"
    echo fmt"  calls per repeat: {callsPerRepeat}"
    echo fmt"  total calls: {totalCalls}"
    echo fmt"  duration: {duration:.6f} seconds"
    echo fmt"  calls/sec: {callsPerSecond:.0f}"
    echo ""

  # Setup namespace
  let ns = new_namespace("native_calls")
  let native_f0_ref = new_ref(VkNativeFn)
  native_f0_ref.native_fn = native_f0
  ns["native_f0".to_key()] = native_f0_ref.to_ref_value()

  let native_f1_ref = new_ref(VkNativeFn)
  native_f1_ref.native_fn = native_f1
  ns["native_f1".to_key()] = native_f1_ref.to_ref_value()

  # Zero-arg benchmark
  var callList0: seq[string] = @[]
  for _ in 0..<callsPerRepeat:
    callList0.add("    (native_f0)")
  let callBlock0 = callList0.join("\n")

  let code0 = fmt"""
    (repeat {repeats}
{callBlock0})
  """

  runBenchmark(code0, "zero-arg native call", ns)

  # One-arg benchmark
  var callList1: seq[string] = @[]
  for _ in 0..<callsPerRepeat:
    callList1.add("    (native_f1 1)")
  let callBlock1 = callList1.join("\n")

  let code1 = fmt"""
    (repeat {repeats}
{callBlock1})
  """

  runBenchmark(code1, "one-arg native call", ns)
