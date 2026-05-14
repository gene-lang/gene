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

  test "read_dir loads gene children as deterministic name-ordered array":
    init_all()
    let root = fresh_dir("dir-array")
    defer: remove_tree(root)
    let sessions = joinPath(root, "sessions")
    createDir(sessions)
    write_serialized(joinPath(sessions, "b.gene"), "{^id \"b\"}")
    write_serialized(joinPath(sessions, "a.gene"), "{^id \"a\"}")

    let value = VM.exec("(gene/serdes/read_dir " & gene_string_literal(sessions) & " ^shape \"array\" ^order \"name\")", "filesystem_serdes_read_dir_array")

    check value.kind == VkArray
    if value.kind == VkArray:
      let items = array_data(value)
      check items.len == 2
      check map_data(items[0])["id".to_key()] == "a".to_value()
      check map_data(items[1])["id".to_key()] == "b".to_value()

  test "nested read_dir returns basename-keyed map and child refs use child directory":
    init_all()
    let root = fresh_dir("dir-map-child-base")
    defer: remove_tree(root)
    let bundle = joinPath(root, "bundle")
    let sessions = joinPath(bundle, "sessions")
    let cwd_shadow = joinPath(root, "cwd-shadow")
    createDir(bundle)
    createDir(sessions)
    createDir(cwd_shadow)

    let parent_path = joinPath(bundle, "parent.gene")
    write_serialized_payload(parent_path, "{^sessions (gene/serdes/read_dir \"sessions\" ^shape map ^order name)}")
    write_serialized_payload(joinPath(sessions, "a.gene"), "{^id \"a\" ^peer (gene/serdes/read_file \"b.gene\")}")
    write_serialized_payload(joinPath(sessions, "b.gene"), "{^id \"b-from-sessions\"}")
    write_serialized_payload(joinPath(cwd_shadow, "b.gene"), "{^id \"b-from-cwd\"}")

    let old_cwd = getCurrentDir()
    setCurrentDir(cwd_shadow)
    defer: setCurrentDir(old_cwd)

    let value = VM.exec("(gene/serdes/read_file " & gene_string_literal(parent_path) & ")", "filesystem_serdes_nested_read_dir_map_child_base")

    check value.kind == VkMap
    if value.kind == VkMap:
      let sessions_value = map_data(value)["sessions".to_key()]
      check sessions_value.kind == VkMap
      if sessions_value.kind == VkMap:
        let sessions_map = map_data(sessions_value)
        check sessions_map.hasKey("a".to_key())
        check sessions_map.hasKey("b".to_key())
        let a_value = sessions_map["a".to_key()]
        let b_value = sessions_map["b".to_key()]
        check map_data(a_value)["id".to_key()] == "a".to_value()
        check map_data(b_value)["id".to_key()] == "b-from-sessions".to_value()
        let peer = map_data(a_value)["peer".to_key()]
        check map_data(peer)["id".to_key()] == "b-from-sessions".to_value()

  test "read_dir rejects wrong arity non-string paths and no filesystem context":
    init_all()
    expect_vm_error_contains("(gene/serdes/read_dir)", "filesystem_serdes_read_dir_arity_zero", [
      "gene/serdes/read_dir",
      "wrong arity",
      "expected 1 path argument",
    ])
    expect_vm_error_contains("(gene/serdes/read_dir \"a\" \"b\")", "filesystem_serdes_read_dir_arity_two", [
      "gene/serdes/read_dir",
      "wrong arity",
      "got 2",
    ])
    expect_vm_error_contains("(gene/serdes/read_dir 123)", "filesystem_serdes_read_dir_non_string", [
      "gene/serdes/read_dir",
      "non-string path",
      "VkInt",
    ])

    let payload = "(gene/serialization (gene/serdes/read_dir \"sessions\" ^shape array ^order name))"
    expect_vm_error_contains("(gene/serdes/deserialize " & gene_string_literal(payload) & ")", "filesystem_serdes_nested_read_dir_no_context", [
      "gene/serdes/read_dir",
      "containing file: <direct>",
      "target: sessions",
      "no filesystem context",
    ])

  test "nested read_dir rejects missing unsafe and file targets with context":
    init_all()
    let root = fresh_dir("dir-safety")
    defer: remove_tree(root)
    let bundle = joinPath(root, "bundle")
    createDir(bundle)
    let parent_path = joinPath(bundle, "parent.gene")

    write_serialized_payload(parent_path, "{^items (gene/serdes/read_dir \"missing\")}")
    expect_vm_error_contains("(gene/serdes/read_file " & gene_string_literal(parent_path) & ")", "filesystem_serdes_nested_read_dir_missing", [
      "gene/serdes/read_dir",
      "containing file: " & parent_path,
      "target: missing",
      "resolved: " & joinPath(bundle, "missing"),
      "missing",
    ])

    let file_target = joinPath(bundle, "not-dir.gene")
    write_serialized_payload(file_target, "\"not a directory\"")
    write_serialized_payload(parent_path, "{^items (gene/serdes/read_dir \"not-dir.gene\")}")
    expect_vm_error_contains("(gene/serdes/read_file " & gene_string_literal(parent_path) & ")", "filesystem_serdes_nested_read_dir_file_target", [
      "gene/serdes/read_dir",
      "containing file: " & parent_path,
      "target: not-dir.gene",
      "resolved: " & file_target,
      "invalid payload",
      "target is a file",
    ])

    let absolute_dir = joinPath(root, "absolute-dir")
    createDir(absolute_dir)
    write_serialized_payload(parent_path, "{^items (gene/serdes/read_dir " & gene_string_literal(absolute_dir) & ")}")
    expect_vm_error_contains("(gene/serdes/read_file " & gene_string_literal(parent_path) & ")", "filesystem_serdes_nested_read_dir_absolute", [
      "gene/serdes/read_dir",
      "containing file: " & parent_path,
      "target: " & absolute_dir,
      "absolute path",
    ])

    let escaped_dir = joinPath(root, "outside")
    createDir(escaped_dir)
    write_serialized_payload(parent_path, "{^items (gene/serdes/read_dir \"../outside\")}")
    expect_vm_error_contains("(gene/serdes/read_file " & gene_string_literal(parent_path) & ")", "filesystem_serdes_nested_read_dir_escape", [
      "gene/serdes/read_dir",
      "containing file: " & parent_path,
      "target: ../outside",
      "resolved: " & escaped_dir,
      "path escape",
    ])

  test "read_dir rejects unsupported options invalid entries child payloads and cycles":
    init_all()
    let root = fresh_dir("dir-invalid")
    defer: remove_tree(root)
    let bundle = joinPath(root, "bundle")
    let sessions = joinPath(bundle, "sessions")
    createDir(bundle)
    createDir(sessions)
    let parent_path = joinPath(bundle, "parent.gene")

    write_serialized_payload(parent_path, "{^items (gene/serdes/read_dir \"sessions\" ^shape set ^order name)}")
    expect_vm_error_contains("(gene/serdes/read_file " & gene_string_literal(parent_path) & ")", "filesystem_serdes_nested_read_dir_bad_shape", [
      "gene/serdes/read_dir",
      "containing file: " & parent_path,
      "target: sessions",
      "unsupported option",
      "^shape",
      "set",
    ])

    write_serialized_payload(parent_path, "{^items (gene/serdes/read_dir \"sessions\" ^shape array ^order ctime)}")
    expect_vm_error_contains("(gene/serdes/read_file " & gene_string_literal(parent_path) & ")", "filesystem_serdes_nested_read_dir_bad_order", [
      "gene/serdes/read_dir",
      "containing file: " & parent_path,
      "target: sessions",
      "unsupported option",
      "^order",
      "ctime",
    ])

    write_serialized_payload(parent_path, "{^items (gene/serdes/read_dir \"sessions\" ^unknown true)}")
    expect_vm_error_contains("(gene/serdes/read_file " & gene_string_literal(parent_path) & ")", "filesystem_serdes_nested_read_dir_unknown_prop", [
      "gene/serdes/read_dir",
      "containing file: " & parent_path,
      "target: sessions",
      "unsupported option",
      "^unknown",
    ])

    write_serialized_payload(parent_path, "{^items (gene/serdes/read_dir \"sessions\" ^lazy true)}")
    expect_vm_error_contains("(gene/serdes/read_file " & gene_string_literal(parent_path) & ")", "filesystem_serdes_nested_read_dir_lazy_true", [
      "gene/serdes/read_dir",
      "containing file: " & parent_path,
      "target: sessions",
      "unsupported option",
      "^lazy true is not supported",
    ])

    remove_tree(sessions)
    createDir(sessions)
    writeFile(joinPath(sessions, "notes.txt"), "not serialized")
    write_serialized_payload(parent_path, "{^items (gene/serdes/read_dir \"sessions\")}")
    expect_vm_error_contains("(gene/serdes/read_file " & gene_string_literal(parent_path) & ")", "filesystem_serdes_nested_read_dir_unexpected_file", [
      "gene/serdes/read_dir",
      "containing file: " & sessions,
      "target: sessions",
      "resolved: " & sessions,
      "invalid payload",
      "notes.txt",
    ])

    remove_tree(sessions)
    createDir(sessions)
    createDir(joinPath(sessions, "nested"))
    write_serialized_payload(parent_path, "{^items (gene/serdes/read_dir \"sessions\")}")
    expect_vm_error_contains("(gene/serdes/read_file " & gene_string_literal(parent_path) & ")", "filesystem_serdes_nested_read_dir_unexpected_subdir", [
      "gene/serdes/read_dir",
      "containing file: " & sessions,
      "target: sessions",
      "resolved: " & sessions,
      "invalid payload",
      "nested",
    ])

    remove_tree(sessions)
    createDir(sessions)
    let invalid_child = joinPath(sessions, "a.gene")
    writeFile(invalid_child, "")
    write_serialized_payload(parent_path, "{^items (gene/serdes/read_dir \"sessions\")}")
    expect_vm_error_contains("(gene/serdes/read_file " & gene_string_literal(parent_path) & ")", "filesystem_serdes_nested_read_dir_invalid_child", [
      "gene/serdes/read_dir",
      "containing file: " & invalid_child,
      "target: a.gene",
      "resolved: " & invalid_child,
      "invalid payload",
    ])

    remove_tree(sessions)
    createDir(sessions)
    let cyclic_child = joinPath(sessions, "a.gene")
    write_serialized_payload(cyclic_child, "{^again (gene/serdes/read_dir \".\" ^shape array ^order name)}")
    write_serialized_payload(parent_path, "{^items (gene/serdes/read_dir \"sessions\")}")
    expect_vm_error_contains("(gene/serdes/read_file " & gene_string_literal(parent_path) & ")", "filesystem_serdes_nested_read_dir_cycle", [
      "gene/serdes/read_dir",
      "containing file: " & cyclic_child,
      "target: .",
      "resolved: " & sessions,
      "cycle",
      "stack chain",
      parent_path,
      sessions,
      cyclic_child,
    ])
