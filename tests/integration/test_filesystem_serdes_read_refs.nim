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

proc write_serialized_payload(path: string, payload: string) =
  writeFile(path, "(gene/serialization " & payload & ")")

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

  test "nested read_file resolves relative to containing file not cwd":
    init_all()
    let root = fresh_dir("nested-relative")
    defer: remove_tree(root)
    let bundle = joinPath(root, "bundle")
    let cwd_shadow = joinPath(root, "cwd-shadow")
    createDir(bundle)
    createDir(cwd_shadow)

    let parent_path = joinPath(bundle, "parent.gene")
    let child_path = joinPath(bundle, "child.gene")
    write_serialized_payload(parent_path, "{^child (gene/serdes/read_file \"child.gene\")}")
    write_serialized_payload(child_path, "{^source \"from-containing-dir\"}")
    write_serialized_payload(joinPath(cwd_shadow, "child.gene"), "{^source \"from-cwd-shadow\"}")

    let old_cwd = getCurrentDir()
    setCurrentDir(cwd_shadow)
    defer: setCurrentDir(old_cwd)

    let value = VM.exec("(gene/serdes/read_file " & gene_string_literal(parent_path) & ")", "filesystem_serdes_nested_read_file_relative")

    check value.kind == VkMap
    let child = map_data(value)["child".to_key()]
    check child.kind == VkMap
    check map_data(child)["source".to_key()] == "from-containing-dir".to_value()

  test "nested read_file uses each child file as the next relative base":
    init_all()
    let root = fresh_dir("nested-child-base")
    defer: remove_tree(root)
    let bundle = joinPath(root, "bundle")
    let child_dir = joinPath(bundle, "child")
    createDir(bundle)
    createDir(child_dir)

    let parent_path = joinPath(bundle, "parent.gene")
    write_serialized_payload(parent_path, "{^child (gene/serdes/read_file \"child/child.gene\")}")
    write_serialized_payload(joinPath(child_dir, "child.gene"), "{^grand (gene/serdes/read_file \"grand.gene\")}")
    write_serialized_payload(joinPath(child_dir, "grand.gene"), "{^source \"from-child-dir\"}")
    write_serialized_payload(joinPath(bundle, "grand.gene"), "{^source \"from-parent-shadow\"}")

    let value = VM.exec("(gene/serdes/read_file " & gene_string_literal(parent_path) & ")", "filesystem_serdes_nested_read_file_child_base")

    let child = map_data(value)["child".to_key()]
    let grand = map_data(child)["grand".to_key()]
    check grand.kind == VkMap
    check map_data(grand)["source".to_key()] == "from-child-dir".to_value()

  test "nested read_file rejects malformed ref forms before generic gene reconstruction":
    init_all()
    let root = fresh_dir("nested-malformed")
    defer: remove_tree(root)
    let parent_path = joinPath(root, "parent.gene")

    write_serialized_payload(parent_path, "(gene/serdes/read_file \"child.gene\" \"extra.gene\")")
    expect_vm_error_contains("(gene/serdes/read_file " & gene_string_literal(parent_path) & ")", "filesystem_serdes_nested_read_file_wrong_arity", [
      "gene/serdes/read_file",
      "containing file: " & parent_path,
      "target: child.gene",
      "wrong arity",
      "expected 1 path argument, got 2",
    ])

    write_serialized_payload(parent_path, "(gene/serdes/read_file 123)")
    expect_vm_error_contains("(gene/serdes/read_file " & gene_string_literal(parent_path) & ")", "filesystem_serdes_nested_read_file_non_string", [
      "gene/serdes/read_file",
      "containing file: " & parent_path,
      "target: VkInt",
      "non-string path",
    ])

    write_serialized_payload(parent_path, "(gene/serdes/read_file \"child.gene\" ^unknown true)")
    expect_vm_error_contains("(gene/serdes/read_file " & gene_string_literal(parent_path) & ")", "filesystem_serdes_nested_read_file_unknown_prop", [
      "gene/serdes/read_file",
      "containing file: " & parent_path,
      "target: child.gene",
      "unsupported option",
      "^unknown",
    ])

    write_serialized_payload(parent_path, "(gene/serdes/read_file \"child.gene\" ^lazy \"later\")")
    expect_vm_error_contains("(gene/serdes/read_file " & gene_string_literal(parent_path) & ")", "filesystem_serdes_nested_read_file_lazy_non_bool", [
      "gene/serdes/read_file",
      "containing file: " & parent_path,
      "target: child.gene",
      "unsupported option",
      "^lazy must be boolean",
      "VkString",
    ])

    write_serialized_payload(parent_path, "(gene/serdes/read_file \"child.gene\" ^lazy true)")
    expect_vm_error_contains("(gene/serdes/read_file " & gene_string_literal(parent_path) & ")", "filesystem_serdes_nested_read_file_lazy_true", [
      "gene/serdes/read_file",
      "containing file: " & parent_path,
      "target: child.gene",
      "unsupported option",
      "^lazy true",
      "S03",
    ])

  test "text deserialize rejects read_file refs without filesystem context":
    init_all()
    let payload = "(gene/serialization (gene/serdes/read_file \"child.gene\"))"
    expect_vm_error_contains("(gene/serdes/deserialize " & gene_string_literal(payload) & ")", "filesystem_serdes_nested_read_file_no_context", [
      "gene/serdes/read_file",
      "containing file: <direct>",
      "target: child.gene",
      "no filesystem context",
    ])

  test "nested read_file rejects missing unsafe and invalid child files with context":
    init_all()
    let root = fresh_dir("nested-safety")
    defer: remove_tree(root)
    let bundle = joinPath(root, "bundle")
    createDir(bundle)
    let parent_path = joinPath(bundle, "parent.gene")

    write_serialized_payload(parent_path, "{^child (gene/serdes/read_file \"missing.gene\")}")
    expect_vm_error_contains("(gene/serdes/read_file " & gene_string_literal(parent_path) & ")", "filesystem_serdes_nested_read_file_missing", [
      "gene/serdes/read_file",
      "containing file: " & parent_path,
      "target: missing.gene",
      "resolved: " & joinPath(bundle, "missing.gene"),
      "missing",
    ])

    let absolute_child = joinPath(root, "absolute-child.gene")
    write_serialized_payload(absolute_child, "\"absolute\"")
    write_serialized_payload(parent_path, "{^child (gene/serdes/read_file " & gene_string_literal(absolute_child) & ")}")
    expect_vm_error_contains("(gene/serdes/read_file " & gene_string_literal(parent_path) & ")", "filesystem_serdes_nested_read_file_absolute", [
      "gene/serdes/read_file",
      "containing file: " & parent_path,
      "target: " & absolute_child,
      "absolute path",
    ])

    let escaped_child = joinPath(root, "secret.gene")
    write_serialized_payload(escaped_child, "\"secret\"")
    write_serialized_payload(parent_path, "{^child (gene/serdes/read_file \"../secret.gene\")}")
    expect_vm_error_contains("(gene/serdes/read_file " & gene_string_literal(parent_path) & ")", "filesystem_serdes_nested_read_file_escape", [
      "gene/serdes/read_file",
      "containing file: " & parent_path,
      "target: ../secret.gene",
      "resolved: " & escaped_child,
      "path escape",
    ])

    let invalid_child = joinPath(bundle, "invalid.gene")
    writeFile(invalid_child, "")
    write_serialized_payload(parent_path, "{^child (gene/serdes/read_file \"invalid.gene\")}")
    expect_vm_error_contains("(gene/serdes/read_file " & gene_string_literal(parent_path) & ")", "filesystem_serdes_nested_read_file_invalid_child", [
      "gene/serdes/read_file",
      "containing file: " & invalid_child,
      "target: invalid.gene",
      "resolved: " & invalid_child,
      "invalid payload",
    ])

  test "nested read_file rejects cycles with read stack diagnostics":
    init_all()
    let root = fresh_dir("nested-cycle")
    defer: remove_tree(root)
    let a_path = joinPath(root, "a.gene")
    let b_path = joinPath(root, "b.gene")
    write_serialized_payload(a_path, "{^b (gene/serdes/read_file \"b.gene\")}")
    write_serialized_payload(b_path, "{^a (gene/serdes/read_file \"a.gene\")}")

    expect_vm_error_contains("(gene/serdes/read_file " & gene_string_literal(a_path) & ")", "filesystem_serdes_nested_read_file_cycle", [
      "gene/serdes/read_file",
      "containing file: " & b_path,
      "target: a.gene",
      "resolved: " & a_path,
      "cycle",
      "stack chain",
      a_path,
      b_path,
    ])
