import unittest, os, osproc, strutils
import std/tempfiles

import gene/compiler
import gene/gir

const LocalPropertyGuardFixture = "testsuite/02-types/types/22_local_property_guard_blame.gene"
const StrictNilAllowedTargets = "Any, Nil, Option[T], or unions containing Nil"
const ExpectedFixtureLines = @[
  "default local nil ok",
  "default property nil ok",
  "direct property coercion ok",
  "dynamic property coercion ok",
  "property param coercion ok",
  "non-instance member write ok",
  "untyped property ok",
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

proc local_guard_parts(got_text = "got String"): seq[string] = @[
  "GENE_TYPE_MISMATCH",
  "expected Int",
  got_text,
  "in variable",
  "phase=local",
  "blame=negative",
  "producer=assignment",
  "consumer=local",
  "site=",
]

proc property_guard_parts(prop_name = "x", expected_type = "Int", got_text = "got String"): seq[string] = @[
  "GENE_TYPE_MISMATCH",
  "expected " & expected_type,
  got_text,
  "property " & prop_name,
  "phase=property",
  "blame=negative",
  "producer=assignment",
  "consumer=property",
  "site=",
]

proc strict_property_guard_parts(): seq[string] =
  result = property_guard_parts("x", "Int", "got Nil")
  result.add("strict nil mode")
  result.add(StrictNilAllowedTargets)

proc strict_local_guard_parts(): seq[string] =
  result = local_guard_parts("got Nil")
  result.add("strict nil mode")
  result.add(StrictNilAllowedTargets)

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

suite "Local and property guard blame CLI/GIR":
  test "source CLI diagnostics include local declaration and assignment blame fields":
    let declaration_result = run_gene(@[
      "eval",
      "(fn produce_string [] \"oops\") (var local_value: Int (produce_string))",
    ])
    check declaration_result.exitCode != 0
    check_contains_all("source local declaration diagnostic", declaration_result.output,
      local_guard_parts())

    let assignment_result = run_gene(@[
      "eval",
      "(fn produce_string [] \"oops\") (fn assign_bad [] (var local_value: Int 1) (local_value = (produce_string))) (assign_bad)",
    ])
    check assignment_result.exitCode != 0
    check_contains_all("source local assignment diagnostic", assignment_result.output,
      local_guard_parts())

  test "tracked fixture proves source and loaded GIR local/property guard parity":
    check fileExists(LocalPropertyGuardFixture)

    let source_default_result = run_gene(@["run", "--no-gir-cache", LocalPropertyGuardFixture])
    check_fixture_success("source default fixture", source_default_result)

    let source_declaration_result = run_gene(@["run", "--no-gir-cache", LocalPropertyGuardFixture, "declare"])
    check source_declaration_result.exitCode != 0
    check_contains_all("source fixture local declaration diagnostic", source_declaration_result.output,
      local_guard_parts())

    let source_assignment_result = run_gene(@["run", "--no-gir-cache", LocalPropertyGuardFixture, "assign"])
    check source_assignment_result.exitCode != 0
    check_contains_all("source fixture local assignment diagnostic", source_assignment_result.output,
      local_guard_parts())

    let source_inherited_local_result = run_gene(@["run", "--no-gir-cache", LocalPropertyGuardFixture, "inherited-local"])
    check source_inherited_local_result.exitCode != 0
    check_contains_all("source fixture inherited local assignment diagnostic", source_inherited_local_result.output,
      local_guard_parts())

    let source_update_local_result = run_gene(@["run", "--no-gir-cache", LocalPropertyGuardFixture, "update-local"])
    check source_update_local_result.exitCode != 0
    check_contains_all("source fixture optimized local update diagnostic", source_update_local_result.output,
      local_guard_parts("got Float"))

    let source_strict_local_result = run_gene(@["run", "--strict-nil", "--no-gir-cache", LocalPropertyGuardFixture, "strict-local"])
    check source_strict_local_result.exitCode != 0
    check_contains_all("source fixture strict local diagnostic", source_strict_local_result.output,
      strict_local_guard_parts())

    let source_property_direct_result = run_gene(@["run", "--no-gir-cache", LocalPropertyGuardFixture, "prop-direct"])
    check source_property_direct_result.exitCode != 0
    check_contains_all("source fixture direct property diagnostic", source_property_direct_result.output,
      property_guard_parts())

    let source_property_dynamic_result = run_gene(@["run", "--no-gir-cache", LocalPropertyGuardFixture, "prop-dynamic"])
    check source_property_dynamic_result.exitCode != 0
    check_contains_all("source fixture dynamic property diagnostic", source_property_dynamic_result.output,
      property_guard_parts())

    let source_property_param_result = run_gene(@["run", "--no-gir-cache", LocalPropertyGuardFixture, "prop-param"])
    check source_property_param_result.exitCode != 0
    check_contains_all("source fixture property parameter diagnostic", source_property_param_result.output,
      property_guard_parts("score", "Float"))

    let source_inherited_property_result = run_gene(@["run", "--no-gir-cache", LocalPropertyGuardFixture, "inherited-prop"])
    check source_inherited_property_result.exitCode != 0
    check_contains_all("source fixture inherited property diagnostic", source_inherited_property_result.output,
      property_guard_parts())

    let source_method_property_result = run_gene(@["run", "--no-gir-cache", LocalPropertyGuardFixture, "method-prop"])
    check source_method_property_result.exitCode != 0
    check_contains_all("source fixture optimized method property-param diagnostic", source_method_property_result.output,
      property_guard_parts())

    let source_strict_property_result = run_gene(@["run", "--strict-nil", "--no-gir-cache", LocalPropertyGuardFixture, "strict-prop"])
    check source_strict_property_result.exitCode != 0
    check_contains_all("source fixture strict property diagnostic", source_strict_property_result.output,
      strict_property_guard_parts())

    let out_dir = createTempDir("gene_local_property_guard_gir_", "")
    defer:
      if dirExists(out_dir):
        removeDir(out_dir)

    let gir_path = compile_fixture_to_gir(LocalPropertyGuardFixture, out_dir)

    let gir_default_result = run_gene(@["run", gir_path])
    check_fixture_success("loaded GIR default fixture", gir_default_result)

    let gir_declaration_result = run_gene(@["run", gir_path, "declare"])
    check gir_declaration_result.exitCode != 0
    check_contains_all("loaded GIR fixture local declaration diagnostic", gir_declaration_result.output,
      local_guard_parts())

    let gir_assignment_result = run_gene(@["run", gir_path, "assign"])
    check gir_assignment_result.exitCode != 0
    check_contains_all("loaded GIR fixture local assignment diagnostic", gir_assignment_result.output,
      local_guard_parts())

    let gir_inherited_local_result = run_gene(@["run", gir_path, "inherited-local"])
    check gir_inherited_local_result.exitCode != 0
    check_contains_all("loaded GIR fixture inherited local assignment diagnostic", gir_inherited_local_result.output,
      local_guard_parts())

    let gir_update_local_result = run_gene(@["run", gir_path, "update-local"])
    check gir_update_local_result.exitCode != 0
    check_contains_all("loaded GIR fixture optimized local update diagnostic", gir_update_local_result.output,
      local_guard_parts("got Float"))

    let gir_strict_local_result = run_gene(@["run", "--strict-nil", gir_path, "strict-local"])
    check gir_strict_local_result.exitCode != 0
    check_contains_all("loaded GIR fixture strict local diagnostic", gir_strict_local_result.output,
      strict_local_guard_parts())

    let gir_property_direct_result = run_gene(@["run", gir_path, "prop-direct"])
    check gir_property_direct_result.exitCode != 0
    check_contains_all("loaded GIR fixture direct property diagnostic", gir_property_direct_result.output,
      property_guard_parts())

    let gir_property_dynamic_result = run_gene(@["run", gir_path, "prop-dynamic"])
    check gir_property_dynamic_result.exitCode != 0
    check_contains_all("loaded GIR fixture dynamic property diagnostic", gir_property_dynamic_result.output,
      property_guard_parts())

    let gir_property_param_result = run_gene(@["run", gir_path, "prop-param"])
    check gir_property_param_result.exitCode != 0
    check_contains_all("loaded GIR fixture property parameter diagnostic", gir_property_param_result.output,
      property_guard_parts("score", "Float"))

    let gir_inherited_property_result = run_gene(@["run", gir_path, "inherited-prop"])
    check gir_inherited_property_result.exitCode != 0
    check_contains_all("loaded GIR fixture inherited property diagnostic", gir_inherited_property_result.output,
      property_guard_parts())

    let gir_method_property_result = run_gene(@["run", gir_path, "method-prop"])
    check gir_method_property_result.exitCode != 0
    check_contains_all("loaded GIR fixture optimized method property-param diagnostic", gir_method_property_result.output,
      property_guard_parts())

    let gir_strict_property_result = run_gene(@["run", "--strict-nil", gir_path, "strict-prop"])
    check gir_strict_property_result.exitCode != 0
    check_contains_all("loaded GIR fixture strict property diagnostic", gir_strict_property_result.output,
      strict_property_guard_parts())

  test "default nil acceptance remains compatible at local boundary":
    let eval_result = run_gene(@[
      "eval",
      "(var local_value: Int nil) (println local_value)",
    ])
    checkpoint eval_result.output
    check eval_result.exitCode == 0
    check stable_output_lines(eval_result.output) == @["nil"]
