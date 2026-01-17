when isMainModule:
  import times, os, strformat, tables, strutils, sequtils, algorithm
  
  import ../../src/gene/types
  import ../../src/gene/parser
  import ../../src/gene/compiler
  import ../../src/gene/vm

  # Instruction counters
  var instruction_counts = initCountTable[InstructionKind]()
  var total_instructions = 0
  
  # Time tracking
  var instruction_times = initTable[InstructionKind, system.float64]()
  
  # Original exec method
  # let original_exec = VM.exec_internal
  
  # Profiling wrapper
  proc profiling_exec(self: VirtualMachine): Value =
    var pc = 0
    if pc >= self.cu.instructions.len:
      raise new_exception(types.Exception, "Empty compilation unit")
    
    while pc < self.cu.instructions.len:
      let inst = self.cu.instructions[pc].addr
      let kind = inst.kind
      
      # Count instruction
      instruction_counts.inc(kind)
      total_instructions += 1
      
      # Execute instruction (simplified for profiling)
      pc += 1
    
    # Return last value on stack
    if self.frame.stack.len > 0:
      self.frame.pop()
    else:
      NIL
  
  # Test code
  var n = "20"
  var args = command_line_params()
  if args.len > 0:
    n = args[0]

  init_app_and_vm()

  let code = fmt"""
    (fn fib [n]
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
  
  # Count instruction types in compiled code
  var static_counts = initCountTable[InstructionKind]()
  for inst in compiled.instructions:
    static_counts.inc(inst.kind)
  
  echo "Static instruction mix:"
  for kind, count in static_counts:
    echo fmt"  {kind}: {count} ({100.0 * count.float / compiled.instructions.len.float:.1f}%)"
  
  # Run benchmark
  let ns = new_namespace("profile")
  VM.frame.update(new_frame(ns))
  VM.cu = compiled
  VM.trace = false
  
  echo fmt"=== Running fib({n}) ==="
  let start = cpuTime()
  let result = VM.exec()
  let duration = cpuTime() - start
  
  echo fmt"Result: {result.to_int()}"
  echo fmt"Time: {duration:.6f} seconds"
  
  # Estimate performance
  echo "=== Performance Estimates ==="
  # For fib(20), we have 21891 calls
  let fib_calls = case n
    of "10": 177
    of "15": 1973  
    of "20": 21891
    of "24": 75025
    else: 0
  
  if fib_calls > 0:
    echo fmt"Function calls: {fib_calls}"
    echo fmt"Calls/second: {fib_calls.float / duration:.0f}"
    
    # Rough instruction estimate (about 30 instructions per call)
    let est_instructions = fib_calls * 30
    echo fmt"Est. instructions: {est_instructions}"
    echo fmt"Instructions/second: {est_instructions.float / duration:.0f}"
  
  # Show hot spots in code
  echo "=== Code Hot Spots ==="
  echo "Most common instruction sequences:"
  
  # Analyze instruction pairs
  var pairs = initCountTable[(InstructionKind, InstructionKind)]()
  for i in 0..<compiled.instructions.len-1:
    let pair = (compiled.instructions[i].kind, compiled.instructions[i+1].kind)
    pairs.inc(pair)
  
  type PairCount = tuple[pair: (InstructionKind, InstructionKind), count: int]
  var sorted_pairs: seq[PairCount] = @[]
  for pair, count in pairs:
    sorted_pairs.add((pair, count))
  sorted_pairs.sort(proc(a, b: PairCount): int = b.count - a.count)
  
  for i, (pair, count) in sorted_pairs:
    if i >= 5: break
    echo fmt"  {pair[0]} -> {pair[1]}: {count} times"
