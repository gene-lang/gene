when isMainModule:
  import times, os, strformat, strutils

  import ../../src/gene/types
  import ../../src/gene/parser
  import ../../src/gene/compiler
  import ../../src/gene/vm

  var repeats = 1000
  var callsPerRepeat = 100
  let args = command_line_params()
  if args.len > 0:
    repeats = parseInt(args[0])
  if args.len > 1:
    callsPerRepeat = parseInt(args[1])

  init_app_and_vm()

  proc callBlock(callLine: string): string =
    var lines: seq[string] = @[]
    for _ in 0..<callsPerRepeat:
      lines.add("    " & callLine)
    lines.join("\n")

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

  let zeroArgCode = fmt"""
    (fn call_once [] nil)
    (repeat {repeats}
{callBlock("(call_once)")})
  """

  runBenchmark(zeroArgCode, "zero-arg function call")

  let oneArgCode = fmt"""
    (fn call_once [x] x)
    (repeat {repeats}
{callBlock("(call_once 1)")})
  """

  runBenchmark(oneArgCode, "one-arg function call")

  let fourArgCode = fmt"""
    (fn call_four [a b c d] nil)
    (repeat {repeats}
{callBlock("(call_four 1 2 3 4)")})
  """

  runBenchmark(fourArgCode, "four-arg function call")
