when isMainModule:
  import times, os, strformat

  import ../../src/gene/types
  import ../../src/gene/parser
  import ../../src/gene/compiler
  import ../../src/gene/vm

  var n = "24"
  let args = command_line_params()
  if args.len > 0:
    n = args[0]

  init_app_and_vm()
  VM.native_code = true

  let code = fmt"""
    (fn fib [n: Int] -> Int
      (if (< n 2)
        n
      else
        (+ (fib (- n 1)) (fib (- n 2)))))
    (fib {n})
  """

  let compiled = compile(read_all(code))

  let ns = new_namespace("fibonacci_native")
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
  echo "Mode: native-code"

  echo fmt"Frame allocations: {FRAME_ALLOCS}"
  echo fmt"Frame reuses: {FRAME_REUSES}"
  if FRAME_ALLOCS + FRAME_REUSES > 0:
    let reuse_rate = (FRAME_REUSES.float / (FRAME_ALLOCS + FRAME_REUSES).float) * 100
    echo fmt"Frame reuse rate: {reuse_rate:.1f}%"

  if n == "24":
    let ops = 150049.0 / duration
    echo fmt"Performance: {ops:.0f} function calls/second"
