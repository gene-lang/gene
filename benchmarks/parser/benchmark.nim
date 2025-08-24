import times, strformat, os, stats, algorithm
import ../../src/gene/parser
import ../../src/gene/types

# Benchmark data for different parsing scenarios
const SIMPLE_EXPRESSIONS = @[
  "42",
  "true", 
  "false",
  "nil",
  "hello",
  ":symbol",
  "\"string\"",
]

const MEDIUM_EXPRESSIONS = @[
  "(+ 1 2 3)",
  "(if true 1 2)",
  "[1 2 3 4 5]",
  "{^a 1 ^b 2 ^c 3}",
  "(var x 10)",
  "(fn add [a b] (+ a b))",
  "namespace/function",
]

const COMPLEX_EXPRESSIONS = @[
  """
  (do
    (var x 10)
    (var y 20)
    (if (> x y)
      (+ x y)
      (* x y)
    )
  )
  """,
  """
  {
    ^name "test"
    ^data [1 2 3 4 5 6 7 8 9 10]
    ^nested {^inner "value" ^count 42}
  }
  """,
  """
  (class Person
    (var name "")
    (var age 0)
    (fn init [n a]
      (self.name = n)
      (self.age = a)
    )
    (fn greet []
      (print "Hello, " self.name)
    )
  )
  """,
]

const WHITESPACE_HEAVY = @[
  "   (   +    1    2    )   ",
  "\n\n(\n  if\n  true\n  1\n  2\n)\n\n",
  "  # comment\n  42  # another comment\n  ",
  """
  
  # This is a comment
  (do
    # Another comment
    (var x 10)  # inline comment
    # More comments
    x
  )
  
  """,
]

const LARGE_DATA = """
(do
  (var data {
    ^users [
      {^name "Alice" ^age 30 ^email "alice@example.com"}
      {^name "Bob" ^age 25 ^email "bob@example.com"}
      {^name "Charlie" ^age 35 ^email "charlie@example.com"}
      {^name "Diana" ^age 28 ^email "diana@example.com"}
      {^name "Eve" ^age 32 ^email "eve@example.com"}
    ]
    ^settings {
      ^theme "dark"
      ^notifications true
      ^language "en"
      ^timezone "UTC"
    }
    ^permissions ["read" "write" "admin"]
  })
  
  (for user in data.users
    (if (> user.age 30)
      (print user.name " is over 30")
      (print user.name " is 30 or younger")
    )
  )
  
  (var result [])
  (for i in (range 1 100)
    (result.push (* i i))
  )
  result
)
"""

type BenchmarkResult = object
  name: string
  iterations: int
  total_time: float
  avg_time: float
  min_time: float
  max_time: float
  ops_per_sec: float

proc benchmark_parsing(name: string, expressions: seq[string], iterations: int = 1000): BenchmarkResult =
  var times: seq[float] = @[]
  var parser = new_parser()
  
  echo fmt"Running {name} benchmark ({iterations} iterations)..."
  
  let start_total = cpuTime()
  
  for i in 0..<iterations:
    let start = cpuTime()
    
    for expr in expressions:
      try:
        let parsed = parser.read_all(expr)
        # Force evaluation to ensure parsing completes
        discard parsed.len
      except:
        # Skip invalid expressions in benchmark
        discard
    
    let elapsed = cpuTime() - start
    times.add(elapsed)
  
  let total_time = cpuTime() - start_total
  
  times.sort()
  
  result = BenchmarkResult(
    name: name,
    iterations: iterations,
    total_time: total_time,
    avg_time: times.mean(),
    min_time: times[0],
    max_time: times[^1],
    ops_per_sec: float(iterations * expressions.len) / total_time
  )

proc benchmark_large_parsing(iterations: int = 100): BenchmarkResult =
  var times: seq[float] = @[]
  var parser = new_parser()
  
  echo fmt"Running large data parsing benchmark ({iterations} iterations)..."
  
  let start_total = cpuTime()
  
  for i in 0..<iterations:
    let start = cpuTime()
    
    try:
      let parsed = parser.read_all(LARGE_DATA)
      # Force evaluation
      discard parsed.len
    except:
      discard
    
    let elapsed = cpuTime() - start
    times.add(elapsed)
  
  let total_time = cpuTime() - start_total
  
  times.sort()
  
  result = BenchmarkResult(
    name: "Large Data Parsing",
    iterations: iterations,
    total_time: total_time,
    avg_time: times.mean(),
    min_time: times[0],
    max_time: times[^1],
    ops_per_sec: float(iterations) / total_time
  )

proc print_result(result: BenchmarkResult) =
  echo fmt"=== {result.name} ==="
  echo fmt"  Iterations: {result.iterations}"
  echo fmt"  Total time: {result.total_time:.3f}s"
  echo fmt"  Average time: {result.avg_time*1000:.3f}ms"
  echo fmt"  Min time: {result.min_time*1000:.3f}ms"
  echo fmt"  Max time: {result.max_time*1000:.3f}ms"
  echo fmt"  Operations/sec: {result.ops_per_sec:.0f}"
  echo ""

proc run_all_benchmarks*() =
  echo "Gene Parser Performance Benchmark"
  echo "================================="
  echo ""
  
  let results = @[
    benchmark_parsing("Simple Expressions", SIMPLE_EXPRESSIONS),
    benchmark_parsing("Medium Expressions", MEDIUM_EXPRESSIONS), 
    benchmark_parsing("Complex Expressions", COMPLEX_EXPRESSIONS),
    benchmark_parsing("Whitespace Heavy", WHITESPACE_HEAVY),
    benchmark_large_parsing()
  ]
  
  for result in results:
    print_result(result)
  
  echo "Benchmark complete!"

when isMainModule:
  run_all_benchmarks()