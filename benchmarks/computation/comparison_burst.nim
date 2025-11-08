when isMainModule:
  import times, os, strformat, strutils

  import ../../src/gene/types
  import ../../src/gene/parser
  import ../../src/gene/compiler
  import ../../src/gene/vm

  var repeats = 1000
  var opsPerRepeat = 100
  let args = command_line_params()
  if args.len > 0:
    repeats = parseInt(args[0])
  if args.len > 1:
    opsPerRepeat = parseInt(args[1])

  init_app_and_vm()

  # Test different types of comparison operations
  echo "=== Comparison Operations Benchmark ==="

  # Test 1: Variable < Literal (should use VarLtValue)
  var varLtList: seq[string] = @[]
  for _ in 0..<opsPerRepeat:
    varLtList.add("    (< n 100)")
  let varLtBlock = varLtList.join("\n")

  let varLtCode = fmt"""
    (var n 42)
    (repeat {repeats}
{varLtBlock})
  """

  let varLtCompiled = compile(read_all(varLtCode))
  echo "Variable < Literal instructions (first few):"
  for i in 0..<min(10, varLtCompiled.instructions.len):
    echo fmt"  {i:2}: {varLtCompiled.instructions[i]}"

  let ns1 = new_namespace("var_lt_burst")
  VM.frame.update(new_frame(ns1))
  VM.cu = varLtCompiled
  VM.trace = false

  let varLtStart = cpuTime()
  discard VM.exec()
  let varLtDuration = cpuTime() - varLtStart

  let totalVarLtOps = repeats * opsPerRepeat
  let varLtOpsPerSecond = if varLtDuration > 0: totalVarLtOps.float / varLtDuration else: 0.0

  echo fmt"Variable < Literal (< n 100) - VarLtValue:"
  echo fmt"  total operations: {totalVarLtOps}"
  echo fmt"  duration: {varLtDuration:.6f} seconds"
  echo fmt"  ops/sec: {varLtOpsPerSecond:.0f}"

  # Test 2: Variable <= Literal (should use VarLeValue)
  init_app_and_vm()

  var varLeList: seq[string] = @[]
  for _ in 0..<opsPerRepeat:
    varLeList.add("    (<= n 100)")
  let varLeBlock = varLeList.join("\n")

  let varLeCode = fmt"""
    (var n 42)
    (repeat {repeats}
{varLeBlock})
  """

  let varLeCompiled = compile(read_all(varLeCode))
  echo "Variable <= Literal instructions (first few):"
  for i in 0..<min(10, varLeCompiled.instructions.len):
    echo fmt"  {i:2}: {varLeCompiled.instructions[i]}"

  let ns2 = new_namespace("var_le_burst")
  VM.frame.update(new_frame(ns2))
  VM.cu = varLeCompiled
  VM.trace = false

  let varLeStart = cpuTime()
  discard VM.exec()
  let varLeDuration = cpuTime() - varLeStart

  let totalVarLeOps = repeats * opsPerRepeat
  let varLeOpsPerSecond = if varLeDuration > 0: totalVarLeOps.float / varLeDuration else: 0.0

  echo fmt"Variable <= Literal (<= n 100) - VarLeValue:"
  echo fmt"  total operations: {totalVarLeOps}"
  echo fmt"  duration: {varLeDuration:.6f} seconds"
  echo fmt"  ops/sec: {varLeOpsPerSecond:.0f}"

  # Test 3: Variable == Literal (should use VarEqValue)
  init_app_and_vm()

  var varEqList: seq[string] = @[]
  for _ in 0..<opsPerRepeat:
    varEqList.add("    (== n 42)")
  let varEqBlock = varEqList.join("\n")

  let varEqCode = fmt"""
    (var n 42)
    (repeat {repeats}
{varEqBlock})
  """

  let varEqCompiled = compile(read_all(varEqCode))
  echo "Variable == Literal instructions (first few):"
  for i in 0..<min(10, varEqCompiled.instructions.len):
    echo fmt"  {i:2}: {varEqCompiled.instructions[i]}"

  let ns3 = new_namespace("var_eq_burst")
  VM.frame.update(new_frame(ns3))
  VM.cu = varEqCompiled
  VM.trace = false

  let varEqStart = cpuTime()
  discard VM.exec()
  let varEqDuration = cpuTime() - varEqStart

  let totalVarEqOps = repeats * opsPerRepeat
  let varEqOpsPerSecond = if varEqDuration > 0: totalVarEqOps.float / varEqDuration else: 0.0

  echo fmt"Variable == Literal (== n 42) - VarEqValue:"
  echo fmt"  total operations: {totalVarEqOps}"
  echo fmt"  duration: {varEqDuration:.6f} seconds"
  echo fmt"  ops/sec: {varEqOpsPerSecond:.0f}"

  # Test 4: Variable > Literal (should use VarGtValue)
  init_app_and_vm()

  var varGtList: seq[string] = @[]
  for _ in 0..<opsPerRepeat:
    varGtList.add("    (> n 10)")
  let varGtBlock = varGtList.join("\n")

  let varGtCode = fmt"""
    (var n 42)
    (repeat {repeats}
{varGtBlock})
  """

  let varGtCompiled = compile(read_all(varGtCode))
  echo "Variable > Literal instructions (first few):"
  for i in 0..<min(10, varGtCompiled.instructions.len):
    echo fmt"  {i:2}: {varGtCompiled.instructions[i]}"

  let ns4 = new_namespace("var_gt_burst")
  VM.frame.update(new_frame(ns4))
  VM.cu = varGtCompiled
  VM.trace = false

  let varGtStart = cpuTime()
  discard VM.exec()
  let varGtDuration = cpuTime() - varGtStart

  let totalVarGtOps = repeats * opsPerRepeat
  let varGtOpsPerSecond = if varGtDuration > 0: totalVarGtOps.float / varGtDuration else: 0.0

  echo fmt"Variable > Literal (> n 10) - VarGtValue:"
  echo fmt"  total operations: {totalVarGtOps}"
  echo fmt"  duration: {varGtDuration:.6f} seconds"
  echo fmt"  ops/sec: {varGtOpsPerSecond:.0f}"

  echo "=== Summary ==="
  echo fmt"VarLtValue: {varLtOpsPerSecond:.0f} ops/sec"
  echo fmt"VarLeValue: {varLeOpsPerSecond:.0f} ops/sec"
  echo fmt"VarEqValue: {varEqOpsPerSecond:.0f} ops/sec"
  echo fmt"VarGtValue: {varGtOpsPerSecond:.0f} ops/sec"
