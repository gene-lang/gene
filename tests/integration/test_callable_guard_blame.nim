import unittest, os, osproc, strutils
import std/tempfiles

import gene/compiler
import gene/gir

const CallableGuardFixture = "testsuite/02-types/types/21_callable_guard_blame.gene"
const ExpectedFixtureLines = @[
  "default arg nil ok",
  "default return nil ok",
]

var cachedGeneBin = ""

proc ensure_gene_bin_for_test(): string =
  if cachedGeneBin.len > 0 and fileExists(cachedGeneBin):
    return cachedGeneBin

  let build = execCmdEx("nimble build")
  checkpoint build.output
  check build.exitCode == 0

  result = absolutePath("bin/gene")
  check fileExists(result)
  cachedGeneBin = result

proc run_gene(args: openArray[string]): tuple[output: string, exitCode: int] =
  let gene_bin = ensure_gene_bin_for_test()
  var command = gene_bin.quoteShell
  for arg in args:
    command.add(" " & arg.quoteShell)
  execCmdEx(command)

proc stable_output_lines(output: string): seq[string] =
  for raw_line in output.splitLines:
    let line = raw_line.strip()
    if line.len == 0:
      continue
    if line.startsWith("T") and line.contains(" WARN "):
      continue
    if line.startsWith("Compiling:") or line.startsWith("Written:"):
      continue
    result.add(line)

proc check_contains_all(label: string, output: string, parts: openArray[string]) =
  checkpoint label & " output:\n" & output
  for part in parts:
    check output.contains(part)

proc callable_argument_parts(got_text = "got String"): seq[string] = @[
  "GENE_TYPE_MISMATCH",
  "expected Int",
  got_text,
  "in x",
  "phase=argument",
  "producer=caller",
  "consumer=function",
  "site=",
]

proc callable_return_parts(got_text = "got String", fn_name = "f"): seq[string] = @[
  "GENE_TYPE_MISMATCH",
  "expected Int",
  got_text,
  "return value of " & fn_name,
  "phase=return",
  "producer=callee",
  "consumer=caller",
  "site=",
]

proc check_fixture_success(label: string, run_result: tuple[output: string, exitCode: int]) =
  checkpoint label & " output:\n" & run_result.output
  check run_result.exitCode == 0
  check stable_output_lines(run_result.output) == ExpectedFixtureLines

proc compile_fixture_to_gir(source_path, out_dir: string): string =
  result = get_gir_path(source_path, out_dir)
  createDir(parentDir(result))
  let compiled = compiler.parse_and_compile(readFile(source_path), source_path,
    module_mode = true, run_init = false)
  gir.save_gir(compiled, result, source_path)
  check fileExists(result)

suite "Callable guard blame CLI/GIR":
  test "source CLI diagnostics include callable argument and return blame fields":
    let argument_result = run_gene(@[
      "eval",
      "(fn produce_string [] \"oops\") (fn f [x: Int] x) (f (produce_string))",
    ])
    check argument_result.exitCode != 0
    check_contains_all("source argument diagnostic", argument_result.output, callable_argument_parts())

    let return_result = run_gene(@[
      "eval",
      "(fn produce_string [] \"oops\") (fn f [] -> Int (produce_string)) (f)",
    ])
    check return_result.exitCode != 0
    check_contains_all("source return diagnostic", return_result.output, callable_return_parts())

  test "tracked fixture proves source and loaded GIR callable guard parity":
    check fileExists(CallableGuardFixture)

    let source_default_result = run_gene(@["run", "--no-gir-cache", CallableGuardFixture])
    check_fixture_success("source default fixture", source_default_result)

    let source_argument_result = run_gene(@["run", "--no-gir-cache", CallableGuardFixture, "arg"])
    check source_argument_result.exitCode != 0
    check_contains_all("source fixture argument diagnostic", source_argument_result.output,
      callable_argument_parts())

    let source_return_result = run_gene(@["run", "--no-gir-cache", CallableGuardFixture, "return"])
    check source_return_result.exitCode != 0
    check_contains_all("source fixture return diagnostic", source_return_result.output,
      callable_return_parts(fn_name = "fixture_bad_return"))

    let out_dir = createTempDir("gene_callable_guard_gir_", "")
    defer:
      if dirExists(out_dir):
        removeDir(out_dir)

    let gir_path = compile_fixture_to_gir(CallableGuardFixture, out_dir)

    let gir_default_result = run_gene(@["run", gir_path])
    check_fixture_success("loaded GIR default fixture", gir_default_result)

    let gir_argument_result = run_gene(@["run", gir_path, "arg"])
    check gir_argument_result.exitCode != 0
    check_contains_all("loaded GIR fixture argument diagnostic", gir_argument_result.output,
      callable_argument_parts())

    let gir_return_result = run_gene(@["run", gir_path, "return"])
    check gir_return_result.exitCode != 0
    check_contains_all("loaded GIR fixture return diagnostic", gir_return_result.output,
      callable_return_parts(fn_name = "fixture_bad_return"))

  test "default nil acceptance remains compatible at callable boundaries":
    let argument_result = run_gene(@[
      "eval",
      "(fn f [x: Int] x) (println (f nil))",
    ])
    checkpoint argument_result.output
    check argument_result.exitCode == 0
    check stable_output_lines(argument_result.output) == @["nil"]

    let return_result = run_gene(@[
      "eval",
      "(fn f [] -> Int nil) (if ((f) == nil) (println \"nil\") else (println \"not-nil\"))",
    ])
    checkpoint return_result.output
    check return_result.exitCode == 0
    check stable_output_lines(return_result.output) == @["nil"]
