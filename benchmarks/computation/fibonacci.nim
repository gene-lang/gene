when isMainModule:
  import times, os, strformat

  import ../../src/gene/types
  import ../../src/gene/parser
  import ../../src/gene/compiler
  import ../../src/gene/vm

  var n = "24"
  var args = command_line_params()
  if args.len > 0:
    n = args[0]

  init_app_and_vm()

  let code = fmt"""
    (fn fib n
      (if (< n 2)
        then n
        else (+ (fib (- n 1)) (fib (- n 2)))))
    (fib {n})
  """

  let compiled = compile(read_all(code))

  let ns = new_namespace("fibonacci")
  VM.frame.update(new_frame(ns))
  VM.cu = compiled
  VM.trace = get_env("TRACE") == "1"

  let start = cpuTime()
  let result = VM.exec()
  let duration = cpuTime() - start
  
  let int_result =
    case result.kind
    of VkInt:
      result.to_int()
    of VkFloat:
      result.to_float().int
    else:
      echo fmt"Unexpected result kind: {result.kind}; raw value: {result}"
      0
  
  echo fmt"Result: fib({n}) = {int_result}"
  echo fmt"Time: {duration:.6f} seconds"
  
  # Show memory statistics
  echo fmt"Frame allocations: {FRAME_ALLOCS}"
  echo fmt"Frame reuses: {FRAME_REUSES}"
  if FRAME_ALLOCS + FRAME_REUSES > 0:
    let reuse_rate = (FRAME_REUSES.float / (FRAME_ALLOCS + FRAME_REUSES).float) * 100
    echo fmt"Frame reuse rate: {reuse_rate:.1f}%"
  
  # Show operations per second for comparison
  if n == "24":
    # fib(24) requires 150049 recursive calls
    let ops = 150049.0 / duration
    echo fmt"Performance: {ops:.0f} function calls/second"

  echo fmt"JIT enabled: {VM.jit.enabled}"
  echo fmt"JIT compilations: {VM.jit.stats.compilations} executions: {VM.jit.stats.executions}"
  let fib_key = "fib".to_key()
  if ns.has_key(fib_key):
    let fib_val = ns[fib_key]
    if fib_val.kind == VkFunction:
      let f = fib_val.ref.fn
      let compiled = if f.jit_compiled != nil: f.jit_compiled.built_for_arch else: "nil"
      let uses_vm_stack = f.jit_compiled != nil and f.jit_compiled.uses_vm_stack
      echo fmt"fib jit_status: {f.jit_status} compiled_for: {compiled} uses_vm_stack: {uses_vm_stack}"
