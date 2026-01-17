when isMainModule:
  import tables, os, times, strformat

  import ../../src/gene/types
  import ../../src/gene/parser
  import ../../src/gene/compiler
  import ../../src/gene/vm

  var n = "1000"
  var args = command_line_params()
  if args.len > 0:
    n = args[0]

  init_app_and_vm()

  let code = fmt"""
    (fn tco [n]
      (if (n == 0)
        (return 0)
      )
      (tco (n - 1))
    )
    (tco {n})
  """

  let compiled = compile(read_all(code))

  let ns = new_namespace("tco")
  VM.frame.update(new_frame(ns))
  VM.cu = compiled
  VM.trace = get_env("TRACE") == "1"

  let start = cpuTime()
  let result = VM.exec()
  echo "Time: " & $(cpuTime() - start)
  echo fmt"tco({n}) = {$result}"
