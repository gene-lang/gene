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
  result = joinPath(getTempDir(), "gene-filesystem-serdes-lazy-refs-" & name)
  remove_tree(result)
  createDir(result)

proc gene_string_literal(value: string): string =
  "\"" & value.replace("\\", "\\\\").replace("\"", "\\\"") & "\""

proc write_serialized_payload(path: string, payload: string) =
  writeFile(path, "(gene/serialization " & payload & ")")

proc expect_vm_error(source, name: string): string =
  var raised = false
  try:
    discard VM.exec(source, name)
  except CatchableError as e:
    raised = true
    result = e.msg

  checkpoint("VM error message: " & result)
  check raised

proc expect_vm_error_contains(source, name: string, expected_parts: openArray[string]) =
  let message = expect_vm_error(source, name)
  for part in expected_parts:
    checkpoint("expecting error part: " & part)
    check message.contains(part)

proc expect_vm_error_not_contains(source, name: string, forbidden_parts: openArray[string]) =
  let message = expect_vm_error(source, name)
  for part in forbidden_parts:
    checkpoint("forbidden error part: " & part)
    check not message.contains(part)

proc expect_materialize_error_contains(value: Value, expected_parts: openArray[string]) =
  var raised = false
  var message = ""
  try:
    discard materialize_custom(value)
  except CatchableError as e:
    raised = true
    message = e.msg

  checkpoint("materialization error message: " & message)
  check raised
  for part in expected_parts:
    checkpoint("expecting error part: " & part)
    check message.contains(part)

suite "filesystem serdes lazy refs":
  test "serialized lazy read_file defers parent read and materializes on member access":
    init_all()
    let root = fresh_dir("serialized-member-access")
    defer: remove_tree(root)
    let parent_path = joinPath(root, "parent.gene")
    let child_path = joinPath(root, "child.gene")
    write_serialized_payload(parent_path, "{^child (gene/serdes/read_file \"child.gene\" ^lazy true)}")
    write_serialized_payload(child_path, "{^name \"lazy-child\" ^count 1}")

    let loaded = VM.exec("(gene/serdes/read_file " & gene_string_literal(parent_path) & ")", "filesystem_serdes_lazy_serialized_parent")
    check loaded.kind == VkMap
    let child_placeholder = map_data(loaded)["child".to_key()]
    check child_placeholder.kind == VkCustom
    check has_custom_materializer(child_placeholder)

    let accessed = VM.exec("""
      (var loaded (gene/serdes/read_file """ & gene_string_literal(parent_path) & """))
      loaded/child/name
    """, "filesystem_serdes_lazy_serialized_access")
    check accessed == "lazy-child".to_value()

  test "direct lazy read_file and read capture stable paths and cache successful materialization":
    init_all()
    let root = fresh_dir("direct-cache")
    defer: remove_tree(root)
    let bundle = joinPath(root, "bundle")
    let cwd_shadow = joinPath(root, "cwd-shadow")
    createDir(bundle)
    createDir(cwd_shadow)
    let child_path = joinPath(bundle, "child.gene")
    write_serialized_payload(child_path, "{^source \"from-bundle\"}")
    write_serialized_payload(joinPath(cwd_shadow, "child.gene"), "{^source \"from-shadow\"}")

    let old_cwd = getCurrentDir()
    setCurrentDir(bundle)
    let lazy_read_file = VM.exec("(gene/serdes/read_file \"child.gene\" ^lazy true)", "filesystem_serdes_lazy_direct_read_file_create")
    let lazy_read_alias = VM.exec("(gene/serdes/read \"child.gene\" ^lazy true)", "filesystem_serdes_lazy_direct_read_alias_create")
    setCurrentDir(cwd_shadow)
    defer: setCurrentDir(old_cwd)

    check lazy_read_file.kind == VkCustom
    check lazy_read_alias.kind == VkCustom
    check has_custom_materializer(lazy_read_file)
    check has_custom_materializer(lazy_read_alias)

    let first = materialize_custom(lazy_read_file)
    check first.kind == VkMap
    check map_data(first)["source".to_key()] == "from-bundle".to_value()

    write_serialized_payload(child_path, "{^source \"updated-after-first-access\"}")
    let second = materialize_custom(lazy_read_file)
    check map_data(second)["source".to_key()] == "from-bundle".to_value()

    let alias_value = materialize_custom(lazy_read_alias)
    check alias_value.kind == VkMap
    check map_data(alias_value)["source".to_key()] == "updated-after-first-access".to_value()

  test "lazy false keeps read_file and read eager":
    init_all()
    let root = fresh_dir("lazy-false")
    defer: remove_tree(root)
    let parent_path = joinPath(root, "parent.gene")
    let child_path = joinPath(root, "child.gene")
    write_serialized_payload(child_path, "{^mode \"eager\"}")

    let eager_direct = VM.exec("(gene/serdes/read_file " & gene_string_literal(child_path) & " ^lazy false)", "filesystem_serdes_lazy_false_direct")
    check eager_direct.kind == VkMap
    check not has_custom_materializer(eager_direct)
    check map_data(eager_direct)["mode".to_key()] == "eager".to_value()

    let eager_alias = VM.exec("(gene/serdes/read " & gene_string_literal(child_path) & " ^lazy false)", "filesystem_serdes_lazy_false_alias")
    check eager_alias == eager_direct

    write_serialized_payload(parent_path, "{^child (gene/serdes/read_file \"child.gene\" ^lazy false)}")
    let loaded = VM.exec("(gene/serdes/read_file " & gene_string_literal(parent_path) & ")", "filesystem_serdes_lazy_false_serialized")
    let child = map_data(loaded)["child".to_key()]
    check child.kind == VkMap
    check not has_custom_materializer(child)
    check map_data(child)["mode".to_key()] == "eager".to_value()

    expect_vm_error_contains("(gene/serdes/read_file " & gene_string_literal(joinPath(root, "missing.gene")) & " ^lazy false)", "filesystem_serdes_lazy_false_direct_missing", [
      "gene/serdes/read_file",
      "target: " & joinPath(root, "missing.gene"),
      "missing",
    ])

  test "serialized missing lazy target succeeds at parent read and fails on first access with original context":
    init_all()
    let root = fresh_dir("missing-deferred")
    defer: remove_tree(root)
    let parent_path = joinPath(root, "parent.gene")
    let missing_path = joinPath(root, "missing.gene")
    write_serialized_payload(parent_path, "{^child (gene/serdes/read_file \"missing.gene\" ^lazy true)}")

    let loaded = VM.exec("(gene/serdes/read_file " & gene_string_literal(parent_path) & ")", "filesystem_serdes_lazy_missing_parent")
    check loaded.kind == VkMap
    let child_placeholder = map_data(loaded)["child".to_key()]
    check child_placeholder.kind == VkCustom
    check has_custom_materializer(child_placeholder)

    expect_vm_error_contains("""
      (var loaded (gene/serdes/read_file """ & gene_string_literal(parent_path) & """))
      loaded/child/name
    """, "filesystem_serdes_lazy_missing_member_access", [
      "gene/serdes/read_file",
      "containing file: " & parent_path,
      "target: missing.gene",
      "resolved: " & missing_path,
      "missing",
      "stack chain",
      parent_path,
    ])

  test "direct read lazy failures preserve read alias diagnostics":
    init_all()
    let root = fresh_dir("direct-read-diagnostics")
    defer: remove_tree(root)
    let missing_path = joinPath(root, "missing.gene")

    let lazy_read = VM.exec("(gene/serdes/read " & gene_string_literal(missing_path) & " ^lazy true)", "filesystem_serdes_lazy_direct_read_missing_create")
    check lazy_read.kind == VkCustom
    expect_materialize_error_contains(lazy_read, [
      "gene/serdes/read failed",
      "containing file: <direct>",
      "target: " & missing_path,
      "missing",
    ])

    write_serialized_payload(missing_path, "{^status \"created-after-failure\"}")
    let recovered = materialize_custom(lazy_read)
    check recovered.kind == VkMap
    check map_data(recovered)["status".to_key()] == "created-after-failure".to_value()

  test "malformed lazy read_file and read options fail during parent read or direct call":
    init_all()
    let root = fresh_dir("malformed")
    defer: remove_tree(root)
    let parent_path = joinPath(root, "parent.gene")

    expect_vm_error_contains("(gene/serdes/read_file \"child.gene\" ^lazy \"later\")", "filesystem_serdes_lazy_direct_non_bool", [
      "gene/serdes/read_file",
      "unsupported option",
      "^lazy must be boolean",
      "VkString",
    ])

    expect_vm_error_contains("(gene/serdes/read \"child.gene\" ^unknown true)", "filesystem_serdes_lazy_direct_unknown", [
      "gene/serdes/read",
      "unsupported option",
      "^unknown",
    ])

    write_serialized_payload(parent_path, "(gene/serdes/read_file \"child.gene\" \"extra.gene\" ^lazy true)")
    expect_vm_error_contains("(gene/serdes/read_file " & gene_string_literal(parent_path) & ")", "filesystem_serdes_lazy_serialized_wrong_arity", [
      "gene/serdes/read_file",
      "containing file: " & parent_path,
      "target: child.gene",
      "wrong arity",
      "got 2",
    ])

    write_serialized_payload(parent_path, "(gene/serdes/read_file 123 ^lazy true)")
    expect_vm_error_contains("(gene/serdes/read_file " & gene_string_literal(parent_path) & ")", "filesystem_serdes_lazy_serialized_non_string", [
      "gene/serdes/read_file",
      "containing file: " & parent_path,
      "target: VkInt",
      "non-string path",
    ])

    write_serialized_payload(parent_path, "(gene/serdes/read \"child.gene\" ^lazy \"later\")")
    expect_vm_error_contains("(gene/serdes/read_file " & gene_string_literal(parent_path) & ")", "filesystem_serdes_lazy_serialized_read_non_bool", [
      "gene/serdes/read",
      "containing file: " & parent_path,
      "target: child.gene",
      "unsupported option",
      "^lazy must be boolean",
      "VkString",
    ])

    write_serialized_payload(parent_path, "(gene/serdes/read \"child.gene\" ^unknown true)")
    expect_vm_error_contains("(gene/serdes/read_file " & gene_string_literal(parent_path) & ")", "filesystem_serdes_lazy_serialized_read_unknown", [
      "gene/serdes/read",
      "containing file: " & parent_path,
      "target: child.gene",
      "unsupported option",
      "^unknown",
    ])

  test "serialized lazy read_file without filesystem context is rejected":
    init_all()
    let payload = "(gene/serialization (gene/serdes/read_file \"child.gene\" ^lazy true))"
    expect_vm_error_contains("(gene/serdes/deserialize " & gene_string_literal(payload) & ")", "filesystem_serdes_lazy_no_context", [
      "gene/serdes/read_file",
      "containing file: <direct>",
      "target: child.gene",
      "no filesystem context",
    ])

  test "read_dir lazy true fails closed without obsolete deferred-to-S03 diagnostic":
    init_all()
    let root = fresh_dir("read-dir-lazy")
    defer: remove_tree(root)
    let sessions = joinPath(root, "sessions")
    createDir(sessions)

    expect_vm_error_contains("(gene/serdes/read_dir " & gene_string_literal(sessions) & " ^lazy true)", "filesystem_serdes_lazy_read_dir_direct", [
      "gene/serdes/read_dir",
      "target: " & sessions,
      "unsupported option",
      "^lazy true is not supported",
    ])
    expect_vm_error_not_contains("(gene/serdes/read_dir " & gene_string_literal(sessions) & " ^lazy true)", "filesystem_serdes_lazy_read_dir_no_s03", [
      "deferred to S03",
    ])

  test "lazy refs are transparent for index access equality and serialization":
    init_all()
    let root = fresh_dir("transparent-access")
    defer: remove_tree(root)
    let array_path = joinPath(root, "array.gene")
    let gene_path = joinPath(root, "gene.gene")
    write_serialized_payload(array_path, "[\"first\" {^name \"nested-array\"}]")
    write_serialized_payload(gene_path, "(record {^name \"nested-gene\"})")

    let array_index = VM.exec("""
      (var lazy (gene/serdes/read_file """ & gene_string_literal(array_path) & """ ^lazy true))
      lazy/0
    """, "filesystem_serdes_lazy_array_index")
    check array_index == "first".to_value()

    let nested_array_selector = VM.exec("""
      (var lazy (gene/serdes/read_file """ & gene_string_literal(array_path) & """ ^lazy true))
      lazy/1/name
    """, "filesystem_serdes_lazy_array_nested_selector")
    check nested_array_selector == "nested-array".to_value()

    let nested_gene_selector = VM.exec("""
      (var lazy (gene/serdes/read_file """ & gene_string_literal(gene_path) & """ ^lazy true))
      lazy/0/name
    """, "filesystem_serdes_lazy_gene_nested_selector")
    check nested_gene_selector == "nested-gene".to_value()

    let equality = VM.exec("""
      (var lazy (gene/serdes/read_file """ & gene_string_literal(array_path) & """ ^lazy true))
      (var eager (gene/serdes/read_file """ & gene_string_literal(array_path) & """))
      (lazy == eager)
    """, "filesystem_serdes_lazy_equality")
    check equality == TRUE

    let lazy_array = VM.exec("(gene/serdes/read_file " & gene_string_literal(array_path) & " ^lazy true)", "filesystem_serdes_lazy_value_to_gene_str_lazy")
    let eager_array = VM.exec("(gene/serdes/read_file " & gene_string_literal(array_path) & ")", "filesystem_serdes_lazy_value_to_gene_str_eager")
    check value_to_gene_str(lazy_array) == value_to_gene_str(eager_array)

    let serialized = VM.exec("(gene/serdes/serialize (gene/serdes/read_file " & gene_string_literal(array_path) & " ^lazy true))", "filesystem_serdes_lazy_serialize")
    check serialized.kind == VkString
    check serialized.str.contains("gene/serialization")
    check serialized.str.contains("first")
    check serialized.str.contains("nested-array")
    check not serialized.str.contains("LazyFileRefValue")

  test "lazy ref failures from index equality and serialization preserve materialization diagnostics":
    init_all()
    let root = fresh_dir("transparent-failures")
    defer: remove_tree(root)
    let scalar_path = joinPath(root, "scalar.gene")
    let missing_path = joinPath(root, "missing.gene")
    write_serialized_payload(scalar_path, "7")

    let eager_index_error = expect_vm_error("""
      (var eager (gene/serdes/read_file """ & gene_string_literal(scalar_path) & """))
      eager/0/!
    """, "filesystem_serdes_lazy_scalar_eager_index_error")
    let lazy_index_error = expect_vm_error("""
      (var lazy (gene/serdes/read_file """ & gene_string_literal(scalar_path) & """ ^lazy true))
      lazy/0/!
    """, "filesystem_serdes_lazy_scalar_lazy_index_error")
    check lazy_index_error == eager_index_error

    expect_vm_error_contains("""
      (var lazy (gene/serdes/read_file """ & gene_string_literal(missing_path) & """ ^lazy true))
      (lazy == 1)
    """, "filesystem_serdes_lazy_missing_equality", [
      "gene/serdes/read_file",
      "target: " & missing_path,
      "missing",
    ])

    expect_vm_error_contains("""
      (gene/serdes/serialize (gene/serdes/read_file """ & gene_string_literal(missing_path) & """ ^lazy true))
    """, "filesystem_serdes_lazy_missing_serialize", [
      "gene/serdes/read_file",
      "target: " & missing_path,
      "missing",
    ])
