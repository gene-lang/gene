import unittest, os, osproc, strutils
import std/tempfiles

import gene/gir

const StrictNilFixture = "testsuite/02-types/types/20_strict_nil_policy.gene"
const StrictNilAllowedTargets = "Any, Nil, Option[T], or unions containing Nil"

proc expected_fixture_lines(): seq[string] = @[
  "arg-rejected",
  "return-rejected",
  "local-rejected",
  "property-rejected",
  "any-admitted",
  "nil-admitted",
  "option-admitted",
  "union-admitted",
]

proc ensure_gene_bin_for_test(): string =
  result = absolutePath("bin/gene")
  if fileExists(result):
    return

  let build = execCmdEx("nimble build")
  checkpoint build.output
  check build.exitCode == 0
  check fileExists(result)

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
    result.add(line)

proc check_successful_fixture_run(label: string, run_result: tuple[output: string, exitCode: int]) =
  checkpoint label & " output:\n" & run_result.output
  check run_result.exitCode == 0
  check stable_output_lines(run_result.output) == expected_fixture_lines()

suite "Strict nil CLI":
  test "eval --strict-nil rejects nil at a typed Int argument boundary with stable diagnostics":
    let result = run_gene(@["eval", "--strict-nil", "(fn f [x: Int] x) (f nil)"])
    checkpoint result.output
    check result.exitCode != 0
    check result.output.contains("GENE_TYPE_MISMATCH")
    check result.output.contains("strict nil mode")
    check result.output.contains(StrictNilAllowedTargets)
    check result.output.contains("got Nil")

  test "default eval and run remain nil-compatible for typed Int arguments":
    let eval_result = run_gene(@["eval", "(fn f [x: Int] x) (println (f nil))"])
    checkpoint eval_result.output
    check eval_result.exitCode == 0
    check stable_output_lines(eval_result.output) == @[
      "nil"
    ]

    let root = createTempDir("gene_strict_nil_default_run_", "")
    let source_path = root / "default_nil_run.gene"
    writeFile(source_path, "(fn f [x: Int] x) (println (f nil))\n")
    defer:
      if dirExists(root):
        removeDir(root)

    let run_result = run_gene(@["run", "--no-gir-cache", source_path])
    checkpoint run_result.output
    check run_result.exitCode == 0
    check stable_output_lines(run_result.output) == @[
      "nil"
    ]

  test "source fixture passes under --strict-nil without GIR cache":
    check fileExists(StrictNilFixture)
    let source_result = run_gene(@["run", "--strict-nil", "--no-gir-cache", StrictNilFixture])
    check_successful_fixture_run("source strict nil fixture", source_result)

  test "compiled GIR fixture preserves strict nil source behavior":
    check fileExists(StrictNilFixture)
    let out_dir = createTempDir("gene_strict_nil_gir_", "")
    defer:
      if dirExists(out_dir):
        removeDir(out_dir)

    let compile_result = run_gene(@[
      "compile",
      "--format:gir",
      "--out-dir:" & out_dir,
      StrictNilFixture,
    ])
    checkpoint compile_result.output
    check compile_result.exitCode == 0

    let gir_path = get_gir_path(StrictNilFixture, out_dir)
    check fileExists(gir_path)

    let gir_result = run_gene(@["run", "--strict-nil", gir_path])
    check_successful_fixture_run("loaded GIR strict nil fixture", gir_result)
