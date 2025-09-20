when isMainModule:
  import times, os, strformat, tables
  
  import ../../src/gene/types
  import ../../src/gene/parser
  import ../../src/gene/compiler
  import ../../src/gene/vm

  # Simple trace capture
  var instruction_trace = newSeq[InstructionKind]()
  var max_trace = 10000
  
  proc trace_instruction(kind: InstructionKind) =
    if instruction_trace.len < max_trace:
      instruction_trace.add(kind)
  
  var n = "15"  # Smaller number for tracing
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
  
  # Setup VM
  let ns = new_namespace("trace")
  VM.frame.update(new_frame(ns))
  VM.cu = compiled
  
  # Run with minimal tracing
  echo fmt"=== Analyzing fib({n}) execution ==="
  
  # First run without modification to get baseline
  let start = cpuTime()
  let result = VM.exec()
  let duration = cpuTime() - start
  
  echo fmt"Result: {result.to_int()}"
  echo fmt"Time: {duration:.6f} seconds"
  
  # Analyze the compiled code structure
  echo "=== Compiled Code Structure ==="
  echo fmt"Total static instructions: {compiled.instructions.len}"
  
  # Look for key patterns in bytecode
  var has_recursive_call = false
  var call_count = 0
  
  for i, inst in compiled.instructions:
    case inst.kind
    of IkFunction:
      echo fmt"  Function definition at {i}"
    of IkCallInit, IkCallMethod, IkCallMethod0:
      call_count += 1
      has_recursive_call = true
      echo fmt"  Function call at {i}: {inst.kind}"
    of IkJump:
      echo fmt"  Branch at {i}: {inst.kind}"
    of IkReturn:
      echo fmt"  Return at {i}"
    else:
      discard
  
  echo fmt"Detected {call_count} static call sites"
  echo fmt"Recursive: {has_recursive_call}"
  
  # Estimate dynamic behavior
  echo "=== Performance Analysis ==="
  
  let fib_value = result.to_int()
  let fib_calls = case n
    of "10": 177
    of "15": 1973  
    of "20": 21891
    else: 0
    
  if fib_calls > 0:
    echo fmt"Fibonacci calls for fib({n}): {fib_calls}"
    echo fmt"Average time per call: {duration / fib_calls.float * 1000000:.2f} microseconds"
    
    # Estimate instructions per call (rough)
    let instructions_per_call = 30  # Typical for recursive fib
    echo fmt"Est. instructions per call: {instructions_per_call}"
    echo fmt"Est. total instructions: {fib_calls * instructions_per_call}"
    echo fmt"Est. MIPS: {(fib_calls * instructions_per_call).float / duration / 1_000_000:.1f}"
  
  # Key bottlenecks
  echo "=== Potential Bottlenecks ==="
  echo "1. Function call overhead (frame creation/destruction)"
  echo "2. Stack operations for each recursive call"
  echo "3. Symbol resolution for 'n' parameter"
  echo "4. Arithmetic operations (-, +, <)"
  echo "5. Conditional branching (if)"
  
  # Optimization suggestions
  echo "=== Optimization Opportunities ==="
  echo "1. Inline small functions to reduce call overhead"
  echo "2. Cache small integer values (0-255)"
  echo "3. Optimize frame allocation with object pools"
  echo "4. Implement tail call optimization"
  echo "5. Use specialized instructions for common patterns"