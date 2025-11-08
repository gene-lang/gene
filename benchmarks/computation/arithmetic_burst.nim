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

  # Test different types of arithmetic operations
  echo "=== Arithmetic Operations Benchmark ==="

  # Test 1: Variable + Literal (should use VarAddValue)
  var varLitList: seq[string] = @[]
  for _ in 0..<opsPerRepeat:
    varLitList.add("    (+ n 123)")
  let varLitBlock = varLitList.join("\n")

  let varLitCode = fmt"""
    (var n 456)
    (repeat {repeats}
{varLitBlock})
  """

  let varLitCompiled = compile(read_all(varLitCode))
  echo "Variable + Literal instructions (first few):"
  for i in 0..<min(10, varLitCompiled.instructions.len):
    echo fmt"  {i:2}: {varLitCompiled.instructions[i]}"

  let ns1 = new_namespace("var_lit_burst")
  VM.frame.update(new_frame(ns1))
  VM.cu = varLitCompiled
  VM.trace = false

  let varLitStart = cpuTime()
  discard VM.exec()
  let varLitDuration = cpuTime() - varLitStart

  let totalVarLitOps = repeats * opsPerRepeat
  let varLitOpsPerSecond = if varLitDuration > 0: totalVarLitOps.float / varLitDuration else: 0.0

  echo fmt"Variable + Literal (+ n 123) - VarAddValue:"
  echo fmt"  total operations: {totalVarLitOps}"
  echo fmt"  duration: {varLitDuration:.6f} seconds"
  echo fmt"  ops/sec: {varLitOpsPerSecond:.0f}"

  # Test 2: Variable - Literal (should use VarSubValue)
  init_app_and_vm()

  var varSubList: seq[string] = @[]
  for _ in 0..<opsPerRepeat:
    varSubList.add("    (- n 10)")
  let varSubBlock = varSubList.join("\n")

  let varSubCode = fmt"""
    (var n 456)
    (repeat {repeats}
{varSubBlock})
  """

  let varSubCompiled = compile(read_all(varSubCode))
  echo "Variable - Literal instructions (first few):"
  for i in 0..<min(10, varSubCompiled.instructions.len):
    echo fmt"  {i:2}: {varSubCompiled.instructions[i]}"

  let ns2 = new_namespace("var_sub_burst")
  VM.frame.update(new_frame(ns2))
  VM.cu = varSubCompiled
  VM.trace = false

  let varSubStart = cpuTime()
  discard VM.exec()
  let varSubDuration = cpuTime() - varSubStart

  let totalVarSubOps = repeats * opsPerRepeat
  let varSubOpsPerSecond = if varSubDuration > 0: totalVarSubOps.float / varSubDuration else: 0.0

  echo fmt"Variable - Literal (- n 10) - VarSubValue:"
  echo fmt"  total operations: {totalVarSubOps}"
  echo fmt"  duration: {varSubDuration:.6f} seconds"
  echo fmt"  ops/sec: {varSubOpsPerSecond:.0f}"

  # Test 3: Variable * Literal (should use VarMulValue)
  init_app_and_vm()

  var varMulList: seq[string] = @[]
  for _ in 0..<opsPerRepeat:
    varMulList.add("    (* n 3)")
  let varMulBlock = varMulList.join("\n")

  let varMulCode = fmt"""
    (var n 42)
    (repeat {repeats}
{varMulBlock})
  """

  let varMulCompiled = compile(read_all(varMulCode))
  echo "Variable * Literal instructions (first few):"
  for i in 0..<min(10, varMulCompiled.instructions.len):
    echo fmt"  {i:2}: {varMulCompiled.instructions[i]}"

  let ns3 = new_namespace("var_mul_burst")
  VM.frame.update(new_frame(ns3))
  VM.cu = varMulCompiled
  VM.trace = false

  let varMulStart = cpuTime()
  discard VM.exec()
  let varMulDuration = cpuTime() - varMulStart

  let totalVarMulOps = repeats * opsPerRepeat
  let varMulOpsPerSecond = if varMulDuration > 0: totalVarMulOps.float / varMulDuration else: 0.0

  echo fmt"Variable * Literal (* n 3) - VarMulValue:"
  echo fmt"  total operations: {totalVarMulOps}"
  echo fmt"  duration: {varMulDuration:.6f} seconds"
  echo fmt"  ops/sec: {varMulOpsPerSecond:.0f}"

  echo "=== Summary ==="
  echo fmt"VarAddValue: {varLitOpsPerSecond:.0f} ops/sec"
  echo fmt"VarSubValue: {varSubOpsPerSecond:.0f} ops/sec"
  echo fmt"VarMulValue: {varMulOpsPerSecond:.0f} ops/sec"
