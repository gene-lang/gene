## Benchmark runner for Gene performance tests
import os, times, strformat, strutils, osproc
import ../src/gene/types
import ../src/gene/parser
import ../src/gene/compiler
import ../src/gene/vm

proc runBenchmark(name: string, code: string): float =
  ## Run a benchmark and return execution time in seconds
  let start = cpuTime()
  
  # Parse and compile
  let parsed = read_all(code)
  let compiled = compile(parsed)
  
  # Create VM and execute
  var vm = new_vm()
  vm.cu = compiled
  vm.frame = new_frame()
  discard vm.exec()
  
  let elapsed = cpuTime() - start
  return elapsed

proc formatTime(seconds: float): string =
  if seconds < 0.001:
    return fmt"{seconds * 1_000_000:.2f}μs"
  elif seconds < 1.0:
    return fmt"{seconds * 1000:.2f}ms"
  else:
    return fmt"{seconds:.2f}s"

proc main() =
  echo "=== Gene Performance Benchmarks ==="
  echo ""
  
  # Fibonacci benchmark
  let fibCode = """
(fn fib [n]
  (if (<= n 1)
    n
    (+ (fib (- n 1)) (fib (- n 2)))))

(fib 25)
"""
  
  echo "1. Fibonacci(25):"
  let fibTime = runBenchmark("fibonacci", fibCode)
  echo fmt"   Time: {formatTime(fibTime)}"
  echo ""
  
  # Loop benchmark
  let loopCode = """
(var total 0)
(for i 1 100000
  (= total (+ total i)))
total
"""
  
  echo "2. Loop sum (1 to 100,000):"
  let loopTime = runBenchmark("loop", loopCode)
  echo fmt"   Time: {formatTime(loopTime)}"
  echo ""
  
  # Variable access benchmark  
  let varCode = """
(var a 1)
(var b 2)
(var c 3)
(var sum 0)
(for i 1 10000
  (= sum (+ sum a))
  (= sum (+ sum b))
  (= sum (+ sum c)))
sum
"""
  
  echo "3. Variable access (30,000 ops):"
  let varTime = runBenchmark("variables", varCode)
  echo fmt"   Time: {formatTime(varTime)}"
  echo ""
  
  # Function call benchmark
  let callCode = """
(fn add [a b] (+ a b))
(var sum 0)
(for i 1 10000
  (= sum (add sum i)))
sum
"""
  
  echo "4. Function calls (10,000 calls):"
  let callTime = runBenchmark("calls", callCode)
  echo fmt"   Time: {formatTime(callTime)}"
  echo ""
  
  # Summary
  echo "=== Summary ==="
  echo fmt"Total time: {formatTime(fibTime + loopTime + varTime + callTime)}"
  
  # Compare with baseline if available
  if fileExists("bench/baseline.txt"):
    let baseline = readFile("bench/baseline.txt").strip().parseFloat()
    let current = fibTime + loopTime + varTime + callTime
    let improvement = (baseline - current) / baseline * 100
    if improvement > 0:
      echo fmt"Performance improvement: {improvement:.1f}%"
    else:
      echo fmt"Performance regression: {-improvement:.1f}%"

when isMainModule:
  main()
