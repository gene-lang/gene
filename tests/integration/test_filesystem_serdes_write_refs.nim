import algorithm, os, strutils, tables, unittest

import gene/types except Exception
import gene/vm

import ../helpers

proc remove_tree(path: string) =
  if fileExists(path):
    removeFile(path)
    return
  if not dirExists(path):
    return

  for kind, child in walkDir(path):
    case kind
    of pcFile, pcLinkToFile:
      removeFile(child)
    of pcDir:
      remove_tree(child)
    of pcLinkToDir:
      removeDir(child)
    else:
      discard
  removeDir(path)

proc fresh_dir(name: string): string =
  result = joinPath(getTempDir(), "gene-filesystem-serdes-write-refs-" & name)
  remove_tree(result)
  createDir(result)

proc gene_string_literal(value: string): string =
  "\"" & value.replace("\\", "\\\\").replace("\"", "\\\"") & "\""

proc sorted_entries(path: string): seq[string] =
  for kind, entry in walkDir(path, relative = true):
    result.add($kind & ":" & entry)
  result.sort(system.cmp[string])

proc expect_vm_error_contains(source, name: string, expected_parts: openArray[string]) =
  var raised = false
  var message = ""
  try:
    discard VM.exec(source, name)
  except CatchableError as e:
    raised = true
    message = e.msg

  checkpoint("VM error message: " & message)
  check raised
  for part in expected_parts:
    checkpoint("expecting error part: " & part)
    check message.contains(part)

suite "filesystem serdes write refs":
  test "write stores one exact serialized file that read and read_file roundtrip":
    init_all()
    let root = fresh_dir("exact-roundtrip")
    defer: remove_tree(root)
    let file_path = joinPath(root, "state")
    let fallback_path = file_path & ".gene"

    let written = VM.exec("(gene/serdes/write " & gene_string_literal(file_path) & " {^name \"alpha\" ^items [1 2 3] ^nested {^ok true}})", "filesystem_serdes_write_exact_roundtrip")

    check written == NIL
    check fileExists(file_path)
    check not fileExists(fallback_path)
    check not dirExists(file_path)
    check sorted_entries(root) == @[$pcFile & ":state"]

    let serialized = readFile(file_path)
    checkpoint("serialized write payload: " & serialized)
    check serialized.startsWith("(gene/serialization ")
    check serialized.contains("^name \"alpha\"")
    check serialized.contains("^items [1 2 3]")

    let read_file_value = VM.exec("(gene/serdes/read_file " & gene_string_literal(file_path) & ")", "filesystem_serdes_write_read_file_roundtrip")
    let read_alias_value = VM.exec("(gene/serdes/read " & gene_string_literal(file_path) & ")", "filesystem_serdes_write_read_alias_roundtrip")

    check read_file_value.kind == VkMap
    check read_alias_value == read_file_value
    check map_data(read_file_value)["name".to_key()] == "alpha".to_value()
    check array_data(map_data(read_file_value)["items".to_key()]) == @[1.to_value(), 2.to_value(), 3.to_value()]
    check map_data(map_data(read_file_value)["nested".to_key()])["ok".to_key()] == TRUE

  test "write creates parent directories for exact target paths":
    init_all()
    let root = fresh_dir("parent-dirs")
    defer: remove_tree(root)
    let file_path = joinPath(root, "nested", "deeper", "state.gene")

    discard VM.exec("(gene/serdes/write " & gene_string_literal(file_path) & " 42)", "filesystem_serdes_write_parent_dirs")

    check fileExists(file_path)
    check not fileExists(file_path & ".gene")
    check VM.exec("(gene/serdes/read " & gene_string_literal(file_path) & ")", "filesystem_serdes_write_parent_dirs_read") == 42.to_value()

  test "write rejects wrong arity and non-string paths with diagnostics":
    init_all()
    expect_vm_error_contains("(gene/serdes/write)", "filesystem_serdes_write_arity_zero", [
      "gene/serdes/write",
      "wrong arity",
      "expected 2 arguments, got 0",
      "target: <missing>",
    ])
    expect_vm_error_contains("(gene/serdes/write \"only-path\")", "filesystem_serdes_write_arity_one", [
      "gene/serdes/write",
      "wrong arity",
      "expected 2 arguments, got 1",
    ])
    expect_vm_error_contains("(gene/serdes/write 123 \"value\")", "filesystem_serdes_write_non_string", [
      "gene/serdes/write",
      "non-string path",
      "target: VkInt",
      "path argument must be a string, got VkInt",
    ])

  test "write rejects unknown keyword options before writing":
    init_all()
    let root = fresh_dir("unknown-option")
    defer: remove_tree(root)
    let file_path = joinPath(root, "state")

    expect_vm_error_contains("(gene/serdes/write " & gene_string_literal(file_path) & " \"value\" ^unknown true)", "filesystem_serdes_write_unknown_option", [
      "gene/serdes/write",
      "unsupported option",
      "target: " & file_path,
      "option: ^unknown",
      "unknown property ^unknown",
    ])
    check not fileExists(file_path)
    check not fileExists(file_path & ".gene")

  test "write reports parent path and serialization failures without fallback files":
    init_all()
    let root = fresh_dir("failures")
    defer: remove_tree(root)

    let blocked_parent = joinPath(root, "blocked")
    writeFile(blocked_parent, "not a directory")
    let blocked_target = joinPath(blocked_parent, "state")
    expect_vm_error_contains("(gene/serdes/write " & gene_string_literal(blocked_target) & " \"value\")", "filesystem_serdes_write_parent_failure", [
      "gene/serdes/write",
      "filesystem write failed",
      "target: " & blocked_target,
    ])
    check not fileExists(blocked_target)
    check not fileExists(blocked_target & ".gene")

    let future_target = joinPath(root, "future-state")
    expect_vm_error_contains("(var pending (async 1))\n(gene/serdes/write " & gene_string_literal(future_target) & " pending)", "filesystem_serdes_write_serialization_failure", [
      "gene/serdes/write",
      "serialization failed",
      "target: " & future_target,
      "not serializable",
    ])
    check not fileExists(future_target)
    check not fileExists(future_target & ".gene")
    check not fileExists(future_target & ".tmp")
