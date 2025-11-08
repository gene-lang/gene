when isMainModule:
  import times, os, strformat, strutils

  import ../../src/gene/types
  import ../../src/gene/parser
  import ../../src/gene/compiler
  import ../../src/gene/vm

  proc native_method0(vm: VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value {.gcsafe, nimcall.} =
    # {.cast(gcsafe).}:
    #   echo fmt"native_method0 {args[0]}"
    discard

  proc native_method1(vm: VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value {.gcsafe, nimcall.} =
    # {.cast(gcsafe).}:
    #   echo fmt"native_method1 {args[0]} {args[1]}"
    discard

  var repeats = 1000
  var callsPerRepeat = 100
  let args = command_line_params()
  if args.len > 0:
    repeats = parseInt(args[0])
  if args.len > 1:
    callsPerRepeat = parseInt(args[1])

  init_app_and_vm()

  proc runBenchmark(code, label: string) =
    let compiled = compile(read_all(code))
    let ns = new_namespace(label)
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

  # Register native methods
  let native_method0_ref = new_ref(VkNativeFn)
  native_method0_ref.native_fn = native_method0
  let native_method0_val = native_method0_ref.to_ref_value()

  let native_method1_ref = new_ref(VkNativeFn)
  native_method1_ref.native_fn = native_method1
  let native_method1_val = native_method1_ref.to_ref_value()

  # Zero-arg benchmark - setup
  let setup0 = """
    (class TestClass)
  """
  let ns0 = new_namespace("native_method_0arg")
  let compiled_setup0 = compile(read_all(setup0))
  VM.frame.update(new_frame(ns0))
  VM.cu = compiled_setup0
  discard VM.exec()

  # Add native method to the class
  let test_class_val = ns0["TestClass".to_key()]
  if test_class_val.kind == VkClass:
    let test_class = test_class_val.ref.class
    test_class.def_native_method("ping0", native_method0)

  # Now compile and run the benchmark code
  var callList0: seq[string] = @[]
  for _ in 0..<callsPerRepeat:
    callList0.add("    (obj .ping0)")
  let callBlock0 = callList0.join("\n")

  let code0 = fmt"""
    (var obj (new TestClass))
    (repeat {repeats}
{callBlock0})
  """

  let compiled0 = compile(read_all(code0))
  VM.frame.update(new_frame(ns0))
  VM.cu = compiled0
  VM.trace = get_env("TRACE") == "1"

  let start0 = cpuTime()
  discard VM.exec()
  let duration0 = cpuTime() - start0

  let totalCalls0 = repeats * callsPerRepeat
  let callsPerSecond0 = if duration0 > 0: totalCalls0.float / duration0 else: 0.0

  echo "zero-arg native method call:"
  echo fmt"  repeat count: {repeats}"
  echo fmt"  calls per repeat: {callsPerRepeat}"
  echo fmt"  total calls: {totalCalls0}"
  echo fmt"  duration: {duration0:.6f} seconds"
  echo fmt"  calls/sec: {callsPerSecond0:.0f}"
  echo ""

  # One-arg benchmark - setup
  let setup1 = """
    (class TestClass)
  """
  let ns1 = new_namespace("native_method_1arg")
  let compiled_setup1 = compile(read_all(setup1))
  VM.frame.update(new_frame(ns1))
  VM.cu = compiled_setup1
  discard VM.exec()

  # Add native method to the class
  let test_class_val1 = ns1["TestClass".to_key()]
  if test_class_val1.kind == VkClass:
    let test_class1 = test_class_val1.ref.class
    test_class1.def_native_method("ping1", native_method1)

  # Now compile and run the benchmark code
  var callList1: seq[string] = @[]
  for _ in 0..<callsPerRepeat:
    callList1.add("    (obj .ping1 1)")
  let callBlock1 = callList1.join("\n")

  let code1 = fmt"""
    (var obj (new TestClass))
    (repeat {repeats}
{callBlock1})
  """

  let compiled1 = compile(read_all(code1))
  VM.frame.update(new_frame(ns1))
  VM.cu = compiled1
  VM.trace = get_env("TRACE") == "1"

  let start1 = cpuTime()
  discard VM.exec()
  let duration1 = cpuTime() - start1

  let totalCalls1 = repeats * callsPerRepeat
  let callsPerSecond1 = if duration1 > 0: totalCalls1.float / duration1 else: 0.0

  echo "one-arg native method call:"
  echo fmt"  repeat count: {repeats}"
  echo fmt"  calls per repeat: {callsPerRepeat}"
  echo fmt"  total calls: {totalCalls1}"
  echo fmt"  duration: {duration1:.6f} seconds"
  echo fmt"  calls/sec: {callsPerSecond1:.0f}"
  echo ""
