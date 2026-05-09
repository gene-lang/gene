import unittest, os, osproc, strutils
import std/tempfiles

import gene/compiler
import gene/gir

const EnumPayloadGuardFixture = "testsuite/02-types/types/23_enum_payload_guard_blame.gene"
const StrictNilAllowedTargets = "Any, Nil, Option[T], or unions containing Nil"
const ExpectedFixtureLines = @[
  "typed positional enum payload ok",
  "typed keyword enum payload ok",
  "untyped enum payload ok",
  "generic enum payload ok",
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

proc enum_payload_guard_parts(got_text = "got String"): seq[string] = @[
  "GENE_TYPE_MISMATCH",
  "expected Int",
  got_text,
  "field Metric/Counter.value",
  "phase=enum-payload",
  "producer=enum-constructor",
  "consumer=enum-variant",
  "site=",
]

proc strict_enum_payload_guard_parts(): seq[string] =
  result = enum_payload_guard_parts("got Nil")
  result.add("strict nil mode")
  result.add(StrictNilAllowedTargets)

proc check_fixture_success(label: string, run_result: tuple[output: string, exitCode: int]) =
  checkpoint label & " output:\n" & run_result.output
  check run_result.exitCode == 0
  check stable_output_lines(run_result.output) == ExpectedFixtureLines

proc compile_fixture_to_gir(source_path, out_dir: string): string =
  checkpoint "compiling fixture " & source_path & " to GIR under " & out_dir
  result = get_gir_path(source_path, out_dir)
  createDir(parentDir(result))
  let compiled = compiler.parse_and_compile(readFile(source_path), source_path,
    module_mode = true, run_init = false)
  gir.save_gir(compiled, result, source_path)
  check fileExists(result)

suite "Enum payload guard blame CLI/GIR":
  test "tracked fixture proves source and loaded GIR enum payload guard parity":
    check fileExists(EnumPayloadGuardFixture)

    let source_default_result = run_gene(@["run", "--no-gir-cache", EnumPayloadGuardFixture])
    check_fixture_success("source default fixture", source_default_result)

    let source_positional_result = run_gene(@["run", "--no-gir-cache", EnumPayloadGuardFixture, "positional"])
    check source_positional_result.exitCode != 0
    check_contains_all("source fixture positional diagnostic", source_positional_result.output,
      enum_payload_guard_parts())

    let source_keyword_result = run_gene(@["run", "--no-gir-cache", EnumPayloadGuardFixture, "keyword"])
    check source_keyword_result.exitCode != 0
    check_contains_all("source fixture keyword diagnostic", source_keyword_result.output,
      enum_payload_guard_parts())

    let source_strict_nil_result = run_gene(@["run", "--strict-nil", "--no-gir-cache", EnumPayloadGuardFixture, "strict-nil"])
    check source_strict_nil_result.exitCode != 0
    check_contains_all("source fixture strict-nil diagnostic", source_strict_nil_result.output,
      strict_enum_payload_guard_parts())

    let out_dir = createTempDir("gene_enum_payload_guard_gir_", "")
    defer:
      if dirExists(out_dir):
        removeDir(out_dir)

    let gir_path = compile_fixture_to_gir(EnumPayloadGuardFixture, out_dir)

    let gir_default_result = run_gene(@["run", gir_path])
    check_fixture_success("loaded GIR default fixture", gir_default_result)

    let gir_positional_result = run_gene(@["run", gir_path, "positional"])
    check gir_positional_result.exitCode != 0
    check_contains_all("loaded GIR fixture positional diagnostic", gir_positional_result.output,
      enum_payload_guard_parts())

    let gir_keyword_result = run_gene(@["run", gir_path, "keyword"])
    check gir_keyword_result.exitCode != 0
    check_contains_all("loaded GIR fixture keyword diagnostic", gir_keyword_result.output,
      enum_payload_guard_parts())

    let gir_strict_nil_result = run_gene(@["run", "--strict-nil", gir_path, "strict-nil"])
    check gir_strict_nil_result.exitCode != 0
    check_contains_all("loaded GIR fixture strict-nil diagnostic", gir_strict_nil_result.output,
      strict_enum_payload_guard_parts())
