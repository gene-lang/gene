## Compare VM vs native for array iteration
## Usage: nim c -d:release --mm:orc --opt:speed -r benchmarks/computation/array_sum_compare.nim

when isMainModule:
  import times, strformat

  import ../../src/gene/types
  import ../../src/gene/parser
  import ../../src/gene/compiler
  import ../../src/gene/vm

  const CODE = """
    (fn make_array [n: Int] -> Array
      (var arr [])
      (var i 0)
      (while (i < n)
        (arr .push i)
        (i = (i + 1)))
      arr)
    (fn sum_array [arr: Array] -> Int
      (var total 0)
      (var i 0)
      (while (i < (arr .size))
        (total = (total + (arr .get i)))
        (i = (i + 1)))
      total)
    (sum_array (make_array 100000))
  """

  let parsed = read_all(CODE)
  let compiled = compile(parsed)

  echo "=== Array Sum (100K elements) Comparison ==="
  echo ""

  # VM interpreter
  block:
    var best = float.high
    for run in 0..2:
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
    var best = float.high
    for run in 0..2:
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
