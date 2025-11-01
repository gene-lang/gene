import times, os, strutils, strformat, math, json, tables, osproc, posix, sequtils

import ../../src/gene/types
import ../../src/gene/parser

type
  BenchmarkResult = object
    file_path: string
    file_size_bytes: int64
    line_count: int
    parse_time_ms: float
    memory_peak_mb: float
    tokens_per_second: float
    lines_per_second: float
    mb_per_second: float
    success: bool
    error_message: string

  BenchmarkSuite = object
    results: seq[BenchmarkResult]
    iterations: int
    warmup_iterations: int

proc countLines(filePath: string): int =
  result = 0
  for line in filePath.lines:
    inc(result)

proc getMemoryUsage(): float =
  # Get current process memory usage in MB
  # This is a simplified version - in production you'd want more accurate measurement
  try:
    when defined(macosx):
      let output = execProcess(fmt"ps -o rss= -p {getpid()}")
      result = parseFloat(output.strip()) / 1024.0  # Convert KB to MB
    elif defined(linux):
      let output = execProcess(fmt"ps -o rss= -p {getpid()}")
      result = parseFloat(output.strip()) / 1024.0  # Convert KB to MB
    elif defined(windows):
      # Windows memory measurement would require different approach
      result = 0.0
    else:
      result = 0.0
  except:
    result = 0.0

proc runSingleParseBenchmark(filePath: string): BenchmarkResult =
  echo fmt"Parsing benchmark for: {filePath}"

  result.file_path = filePath
  result.success = false

  try:
    # Get file info
    result.file_size_bytes = getFileSize(filePath)
    result.line_count = countLines(filePath)

    echo fmt"  File size: {result.file_size_bytes} bytes"
    echo fmt"  Line count: {result.line_count}"

    # Warmup run (to account for JIT compilation, cache warmup, etc.)
    let warmup_start = cpuTime()
    discard read_all(filePath)
    let warmup_time = (cpuTime() - warmup_start) * 1000
    echo fmt"  Warmup time: {warmup_time:.2f} ms"

    # Multiple iterations for statistical accuracy
    var total_time = 0.0
    var min_time = float.high
    var max_time = 0.0
    let iterations = 5

    echo fmt"  Running {iterations} iterations..."

    # Measure memory before parsing
    let memory_before = getMemoryUsage()

    for i in 1..iterations:
      let start_time = cpuTime()

      # Parse the file
      let gene_value = read_all(filePath)

      let end_time = cpuTime()
      let iteration_time = (end_time - start_time) * 1000

      total_time += iteration_time
      min_time = min(min_time, iteration_time)
      max_time = max(max_time, iteration_time)

      echo fmt"    Iteration {i}: {iteration_time:.2f} ms"

      # Validate that we got a valid result
      if gene_value.len == 0:
        result.error_message = "Parser returned empty result"
        return result

    # Measure memory after parsing
    let memory_after = getMemoryUsage()
    result.memory_peak_mb = max(0.0, memory_after - memory_before)

    # Calculate average time (excluding outliers - use median approach)
    let avg_time = total_time / float(iterations)
    result.parse_time_ms = avg_time

    # Calculate performance metrics
    let parse_time_seconds = avg_time / 1000.0
    result.lines_per_second = float(result.line_count) / parse_time_seconds
    result.mb_per_second = (float(result.file_size_bytes) / (1024.0 * 1024.0)) / parse_time_seconds

    # Estimate tokens per second (rough approximation: ~2 tokens per line for Gene)
    let estimated_tokens = result.line_count * 2
    result.tokens_per_second = float(estimated_tokens) / parse_time_seconds

    result.success = true

    echo fmt"  Results:"
    echo fmt"    Average time: {avg_time:.2f} ms (min: {min_time:.2f}, max: {max_time:.2f})"
    echo fmt"    Memory: {result.memory_peak_mb:.2f} MB"
    echo fmt"    Speed: {result.lines_per_second:.0f} lines/sec"
    echo fmt"    Throughput: {result.mb_per_second:.2f} MB/sec"
    echo fmt"    Tokens: {result.tokens_per_second:.0f} tokens/sec"

  except system.Exception as e:
    result.error_message = e.msg
    echo fmt"  ERROR: {result.error_message}"

proc runBenchmarkSuite(files: seq[string]): BenchmarkSuite =
  echo "=== Gene Parsing Benchmark Suite ==="
  echo fmt"Testing {files.len} files"
  echo ""

  result.iterations = 5
  result.warmup_iterations = 1

  for file_path in files:
    if not fileExists(file_path):
      echo fmt"WARNING: File not found: {file_path}"
      continue

    let benchmark_result = runSingleParseBenchmark(file_path)
    result.results.add(benchmark_result)
    echo ""

proc generateResultsSummary(suite: BenchmarkSuite): JsonNode =
  var successful_results = suite.results.filter(proc(r: BenchmarkResult): bool = r.success)

  if successful_results.len == 0:
    return %*{"error": "No successful benchmarks"}

  # Calculate aggregates
  var total_lines = 0
  var total_bytes = 0
  var total_time = 0.0
  var total_memory = 0.0

  for result in successful_results:
    total_lines += result.line_count
    total_bytes += result.file_size_bytes
    total_time += result.parse_time_ms
    total_memory += result.memory_peak_mb

  let avg_lines_per_second = float(total_lines) / (total_time / 1000.0)
  let avg_mb_per_second = (float(total_bytes) / (1024.0 * 1024.0)) / (total_time / 1000.0)
  let avg_memory_mb = total_memory / float(successful_results.len)

  result = %*{
    "summary": {
      "total_files": successful_results.len,
      "total_lines": total_lines,
      "total_size_mb": float(total_bytes) / (1024.0 * 1024.0),
      "total_time_seconds": total_time / 1000.0,
      "avg_lines_per_second": avg_lines_per_second,
      "avg_mb_per_second": avg_mb_per_second,
      "avg_memory_mb": avg_memory_mb
    },
    "results": []
  }

  for result in successful_results:
    result["results"].add(%*{
      "file": extractFilename(result.file_path),
      "lines": result.line_count,
      "size_mb": float(result.file_size_bytes) / (1024.0 * 1024.0),
      "parse_time_ms": result.parse_time_ms,
      "lines_per_second": result.lines_per_second,
      "mb_per_second": result.mb_per_second,
      "memory_mb": result.memory_peak_mb
    })

proc saveResults(suite: BenchmarkSuite, outputPath: string) =
  let json_data = generateResultsSummary(suite)

  let output_file = open(outputPath, fmWrite)
  output_file.write(json_data.pretty(2))
  output_file.close()

  echo fmt"Results saved to: {outputPath}"

proc printComparisonTable(suite: BenchmarkSuite) =
  echo "\n=== Performance Comparison Table ==="
  echo fmt"{'File':<20} {'Lines':<8} {'Size(MB)':<10} {'Time(ms)':<10} {'Lines/s':<12} {'MB/s':<10} {'Mem(MB)':<10}"
  echo "-".repeat(80)

  for result in suite.results:
    if result.success:
      echo fmt"{extractFilename(result.file_path):<19} {result.line_count:<8} {float(result.file_size_bytes)/(1024*1024):<10.2f} {result.parse_time_ms:<10.2f} {result.lines_per_second:<12.0f} {result.mb_per_second:<10.2f} {result.memory_peak_mb:<10.2f}"
    else:
      echo fmt"{extractFilename(result.file_path):<19} {'ERROR':<8} {'-':<10} {'-':<10} {'-':<12} {'-':<10} {'-':<10}"

proc main() =
  let args = commandLineParams()

  if args.len == 0:
    echo "Usage: parsing_benchmark <file1> [file2] [file3] ..."
    echo "   Or: parsing_benchmark --generate-test-files"
    echo ""
    echo "Examples:"
    echo "  parsing_benchmark test_1k.gene test_10k.gene test_50k.gene"
    echo "  parsing_benchmark --generate-test-files"
    quit(1)

  if args[0] == "--generate-test-files":
    echo "Generating test files..."
    let tool_path = "tools/generate_large_file.nim"

    # Generate test files of different sizes
    let test_configs = [
      (1000, "data/test_1k.gene", 2, 42),
      (10000, "data/test_10k.gene", 3, 42),
      (50000, "data/test_50k.gene", 4, 42)
    ]

    for (lines, output, complexity, seed) in test_configs:
      let cmd = fmt"nim c -r {tool_path} {lines} {output} {complexity} {seed}"
      echo fmt"Running: {cmd}"
      let output_result = execProcess(cmd, workingDir = getCurrentDir())
      echo output_result

    echo "\nTest files generated. Now run:"
    echo "  parsing_benchmark data/test_1k.gene data/test_10k.gene data/test_50k.gene"
    return

  let files = args
  let suite = runBenchmarkSuite(files)

  # Print comparison table
  printComparisonTable(suite)

  # Save results
  let timestamp = now().format("yyyy-MM-dd_HH-mm-ss")
  let results_path = fmt"results/parsing_benchmark_{timestamp}.json"
  saveResults(suite, results_path)

when isMainModule:
  main()