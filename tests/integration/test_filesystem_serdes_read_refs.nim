import os, strutils, tables, unittest

import gene/serdes
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
  result = joinPath(getTempDir(), "gene-filesystem-serdes-read-refs-" & name)
  remove_tree(result)
  createDir(result)

proc gene_string_literal(value: string): string =
  "\"" & value.replace("\\", "\\\\").replace("\"", "\\\"") & "\""

proc write_serialized(path: string, source: string) =
  let value = VM.exec(cleanup(source), "filesystem_serdes_fixture")
  writeFile(path, serialize(value).to_s())

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

suite "filesystem serdes read refs":
  test "read_file and read load one exact serialized file":
    init_all()
    let root = fresh_dir("direct")
    defer: remove_tree(root)
    let file_path = joinPath(root, "state.gene")
    write_serialized(file_path, """
      {^name "alpha" ^items [1 2 3] ^nested {^ok true}}
    """)

    let read_file_value = VM.exec("(gene/serdes/read_file " & gene_string_literal(file_path) & ")", "filesystem_serdes_read_file_direct")
    let read_alias_value = VM.exec("(gene/serdes/read " & gene_string_literal(file_path) & ")", "filesystem_serdes_read_alias_direct")

    check read_file_value.kind == VkMap
    check read_alias_value == read_file_value
    check map_data(read_file_value)["name".to_key()] == "alpha".to_value()
    check array_data(map_data(read_file_value)["items".to_key()]) == @[1.to_value(), 2.to_value(), 3.to_value()]
    check map_data(map_data(read_file_value)["nested".to_key()])["ok".to_key()] == TRUE

  test "read_file rejects wrong arity and non-string paths with diagnostics":
    init_all()
    expect_vm_error_contains("(gene/serdes/read_file)", "filesystem_serdes_read_file_arity_zero", [
      "gene/serdes/read_file",
      "wrong arity",
      "expected 1 path argument",
    ])
    expect_vm_error_contains("(gene/serdes/read \"a.gene\" \"b.gene\")", "filesystem_serdes_read_alias_arity_two", [
      "gene/serdes/read",
      "wrong arity",
      "got 2",
    ])
    expect_vm_error_contains("(gene/serdes/read_file 123)", "filesystem_serdes_read_file_non_string", [
      "gene/serdes/read_file",
      "non-string path",
      "VkInt",
    ])

  test "read_file reports missing exact files without tree fallback":
    init_all()
    let root = fresh_dir("exact")
    defer: remove_tree(root)
    let exact_path = joinPath(root, "state")
    let fallback_path = exact_path & ".gene"
    write_serialized(fallback_path, """
      "fallback"
    """)

    expect_vm_error_contains("(gene/serdes/read_file " & gene_string_literal(exact_path) & ")", "filesystem_serdes_read_file_exact_missing", [
      "gene/serdes/read_file",
      "containing file",
      "target: " & exact_path,
      "resolved: ",
      "missing",
      "exact file",
    ])

  test "read_file reports invalid serialized payloads with path context":
    init_all()
    let root = fresh_dir("invalid")
    defer: remove_tree(root)
    let file_path = joinPath(root, "bad.gene")
    writeFile(file_path, "")

    expect_vm_error_contains("(gene/serdes/read_file " & gene_string_literal(file_path) & ")", "filesystem_serdes_read_file_invalid_payload", [
      "gene/serdes/read_file",
      "containing file",
      "target: " & file_path,
      "resolved: " & file_path,
      "invalid payload",
    ])
