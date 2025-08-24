when isMainModule:
  import times, os, strformat, tables, algorithm
  
  import ../../src/gene/types
  import ../../src/gene/parser
  import ../../src/gene/compiler
  import ../../src/gene/vm

  var n = "20"
  var args = command_line_params()
  if args.len > 0:
    n = args[0]

  init_app_and_vm()

  let code = fmt"""
    (fn fib n
      (if (n < 2)
        n
      else
        ((fib (n - 1)) + (fib (n - 2)))
      )
    )
    (fib {n})
  """

  let compiled = compile(read_all(code))
  
  # Show bytecode statistics
  echo fmt"=== Bytecode Analysis for fib({n}) ==="
  echo fmt"Total instructions: {compiled.instructions.len}"
  
  # Count instruction types
  var counts = initCountTable[InstructionKind]()
  for inst in compiled.instructions:
    counts.inc(inst.kind)
  
  echo "Instruction breakdown:"
  for kind, count in counts:
    echo fmt"  {kind}: {count}"
  
  # Setup VM
  let ns = new_namespace("profile")
  VM.frame.update(new_frame(ns))
  VM.cu = compiled
  
  # Enable tracing for analysis
  echo fmt"=== Running fib({n}) with tracing ==="
  VM.trace = true
  
  # Capture first 100 instructions
  var trace_count = 0
  let original_trace = VM.trace
  
  # Run without tracing first to get timing
  VM.trace = false
  let start = cpuTime()
  let result = VM.exec()
  let duration = cpuTime() - start
  
  echo fmt"Result: {result.to_int()}"
  echo fmt"Time: {duration:.6f} seconds"
  
  # Performance metrics
  let fib_calls = case n
    of "10": 177
    of "15": 1973  
    of "20": 21891
    of "24": 75025
    else: 0
  
  if fib_calls > 0:
    echo fmt"Performance metrics:"
    echo fmt"  Function calls: {fib_calls}"
    echo fmt"  Calls/second: {(fib_calls.float / duration).int}"
    echo fmt"  Est. instructions: {fib_calls * 30}"
    echo fmt"  Instructions/second: {(fib_calls.float * 30 / duration).int}"
  
  # Show most common instructions
  echo "Most frequent instructions:"
  var sorted = newSeq[(InstructionKind, int)]()
  for k, v in counts:
    sorted.add((k, v))
  sorted.sort(proc(a, b: (InstructionKind, int)): int = b[1] - a[1])
  
  for i in 0..<min(5, sorted.len):
    let (kind, count) = sorted[i]
    let pct = 100.0 * count.float / compiled.instructions.len.float
    echo fmt"  {kind}: {count} ({pct:.1f}%)"