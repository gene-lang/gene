## Compare VM interpreter vs native compilation for a while-loop benchmark
## Usage: nim c -d:release --mm:orc --opt:speed -r benchmarks/computation/while_loop_compare.nim

when isMainModule:
  import times, strformat

  import ../../src/gene/types
  import ../../src/gene/parser
  import ../../src/gene/compiler
  import ../../src/gene/vm

  const CODE = """
    (fn loop_sum [n: Int] -> Int
      (var total 0)
      (var i 0)
      (while (i < n)
        (total = (total + i))
        (i = (i + 1))
      )
      total
    )
    (loop_sum 10000000)
  """

  let parsed = read_all(CODE)
  let compiled = compile(parsed)

  echo "=== While Loop (10M iterations) Comparison ==="
  echo ""

  # VM interpreter
  block:
    init_app_and_vm()
    init_stdlib()
    VM.frame.update(new_frame(new_namespace("vm")))
    VM.cu = compiled
    # Warmup
    discard VM.exec()

    var best = float.high
    for _ in 0..2:
      init_app_and_vm()
      init_stdlib()
      VM.frame.update(new_frame(new_namespace("vm")))
      VM.cu = compiled
      let t0 = cpuTime()
      let result = VM.exec()
      let elapsed = cpuTime() - t0
      if elapsed < best:
        best = elapsed
      echo fmt"  VM interpreter:      {elapsed:.6f}s  result={result}"

    echo fmt"  VM best:             {best:.6f}s"
    echo ""

  # Native compilation
  block:
    init_app_and_vm()
    init_stdlib()
    VM.native_code = true
    VM.frame.update(new_frame(new_namespace("nat")))
    VM.cu = compiled
    # Warmup
    discard VM.exec()

    var best = float.high
    for _ in 0..2:
      init_app_and_vm()
      init_stdlib()
      VM.native_code = true
      VM.frame.update(new_frame(new_namespace("nat")))
      VM.cu = compiled
      let t0 = cpuTime()
      let result = VM.exec()
      let elapsed = cpuTime() - t0
      if elapsed < best:
        best = elapsed
      echo fmt"  Native compilation:  {elapsed:.6f}s  result={result}"

    echo fmt"  Native best:         {best:.6f}s"
    echo ""
