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

  test "write externalizes selected scalar child with read_file ref":
    init_all()
    let root = fresh_dir("externalize-scalar")
    defer: remove_tree(root)
    let file_path = joinPath(root, "state.gene")
    let external_dir = joinPath(root, "state.files")
    let child_path = joinPath(external_dir, "count.gene")
    let ref_path = joinPath("state.files", "count.gene")

    discard VM.exec("(gene/serdes/write " & gene_string_literal(file_path) & " {^name \"alpha\" ^count 7} ^externalize [/count])", "filesystem_serdes_write_externalize_scalar")

    check fileExists(file_path)
    check dirExists(external_dir)
    check fileExists(child_path)
    check sorted_entries(root) == @[
      $pcDir & ":state.files",
      $pcFile & ":state.gene",
    ]
    check sorted_entries(external_dir) == @[$pcFile & ":count.gene"]

    let parent_serialized = readFile(file_path)
    let child_serialized = readFile(child_path)
    checkpoint("externalized parent payload: " & parent_serialized)
    checkpoint("externalized child payload: " & child_serialized)
    check parent_serialized.contains("^name \"alpha\"")
    check parent_serialized.contains("^count (gene/serdes/read_file " & gene_string_literal(ref_path) & ")")
    check child_serialized == "(gene/serialization 7)"

    let read_back = VM.exec("(gene/serdes/read " & gene_string_literal(file_path) & ")", "filesystem_serdes_write_externalize_scalar_read")
    check read_back.kind == VkMap
    check map_data(read_back)["name".to_key()] == "alpha".to_value()
    check map_data(read_back)["count".to_key()] == 7.to_value()

  test "write externalizes multiple file children with custom external_dir and stable refs":
    init_all()
    let root = fresh_dir("externalize-multiple")
    defer: remove_tree(root)
    let file_path = joinPath(root, "state.gene")
    let external_dir = joinPath(root, "children")
    let profile_child_path = joinPath(external_dir, "profile.gene")
    let event_child_path = joinPath(external_dir, "event.gene")
    let profile_ref = joinPath("children", "profile.gene")
    let event_ref = joinPath("children", "event.gene")
    let source = "(var Event `Event)\n(gene/serdes/write " & gene_string_literal(file_path) &
      " {^profile \"Ada\" ^event (Event ^kind \"login\" \"payload\")} ^externalize [/profile /event] ^external_dir \"children\")"

    discard VM.exec(source, "filesystem_serdes_write_externalize_multiple")
    let first_parent = readFile(file_path)
    let first_profile = readFile(profile_child_path)
    let first_event = readFile(event_child_path)

    check sorted_entries(root) == @[
      $pcDir & ":children",
      $pcFile & ":state.gene",
    ]
    check sorted_entries(external_dir) == @[
      $pcFile & ":event.gene",
      $pcFile & ":profile.gene",
    ]
    checkpoint("externalized multi parent payload: " & first_parent)
    checkpoint("externalized profile child: " & first_profile)
    checkpoint("externalized event child: " & first_event)
    check first_parent.contains("^profile (gene/serdes/read_file " & gene_string_literal(profile_ref) & ")")
    check first_parent.contains("^event (gene/serdes/read_file " & gene_string_literal(event_ref) & ")")
    check first_profile == "(gene/serialization \"Ada\")"
    check first_event.contains("(gene/serialization (Event")
    check first_event.contains("^kind \"login\"")
    check first_event.contains("\"payload\"")

    discard VM.exec(source, "filesystem_serdes_write_externalize_multiple_repeat")
    check readFile(file_path) == first_parent
    check readFile(profile_child_path) == first_profile
    check readFile(event_child_path) == first_event

    let read_back = VM.exec("(gene/serdes/read " & gene_string_literal(file_path) & ")", "filesystem_serdes_write_externalize_multiple_read")
    check read_back.kind == VkMap
    check map_data(read_back)["profile".to_key()] == "Ada".to_value()
    let event = map_data(read_back)["event".to_key()]
    check event.kind == VkGene
    check event.gene.type == "Event".to_symbol_value()
    check event.gene.props["kind".to_key()] == "login".to_value()
    check event.gene.children == @["payload".to_value()]

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

  test "write rejects malformed externalize selectors before replacing parent":
    init_all()
    let root = fresh_dir("malformed-externalize")
    defer: remove_tree(root)
    let file_path = joinPath(root, "state.gene")

    proc reset_parent() =
      writeFile(file_path, "original parent")

    reset_parent()
    expect_vm_error_contains("(gene/serdes/write " & gene_string_literal(file_path) & " {^profile \"Ada\"} ^externalize \"/profile\")", "filesystem_serdes_write_externalize_non_array", [
      "gene/serdes/write",
      "malformed selector",
      "target: " & file_path,
      "option: ^externalize",
      "^externalize expects an array",
    ])
    check readFile(file_path) == "original parent"

    reset_parent()
    expect_vm_error_contains("(gene/serdes/write " & gene_string_literal(file_path) & " {^profile \"Ada\"} ^externalize [profile])", "filesystem_serdes_write_externalize_relative_selector", [
      "gene/serdes/write",
      "malformed selector",
      "option: ^externalize",
      "selector: profile",
      "absolute child selectors",
    ])
    check readFile(file_path) == "original parent"

    reset_parent()
    expect_vm_error_contains("(gene/serdes/write " & gene_string_literal(file_path) & " {^profile \"Ada\"} ^externalize [/*])", "filesystem_serdes_write_externalize_old_wildcard", [
      "gene/serdes/write",
      "malformed selector",
      "option: ^externalize",
      "selector: /*",
      "wildcard/old selector forms are unsupported",
    ])
    check readFile(file_path) == "original parent"

    reset_parent()
    expect_vm_error_contains("(gene/serdes/write " & gene_string_literal(file_path) & " {^profile \"Ada\"} ^separate [/*])", "filesystem_serdes_write_separate_option_rejected", [
      "gene/serdes/write",
      "unsupported option",
      "target: " & file_path,
      "option: ^separate",
      "use ^externalize",
    ])
    check readFile(file_path) == "original parent"

    reset_parent()
    expect_vm_error_contains("(gene/serdes/write " & gene_string_literal(file_path) & " {^profile \"Ada\"} ^externalize [/profile /profile])", "filesystem_serdes_write_externalize_duplicate", [
      "gene/serdes/write",
      "duplicate selector",
      "option: ^externalize",
      "selector: /profile",
    ])
    check readFile(file_path) == "original parent"

    reset_parent()
    expect_vm_error_contains("(gene/serdes/write " & gene_string_literal(file_path) & " {^profile {^name \"Ada\"}} ^externalize [/profile /profile/name])", "filesystem_serdes_write_externalize_prefix_conflict", [
      "gene/serdes/write",
      "conflicting selector",
      "option: ^externalize",
      "selector: /profile/name",
      "/profile conflicts with /profile/name",
    ])
    check readFile(file_path) == "original parent"

    reset_parent()
    expect_vm_error_contains("(gene/serdes/write " & gene_string_literal(file_path) & " {^profile \"Ada\"} ^externalize [/missing])", "filesystem_serdes_write_externalize_missing", [
      "gene/serdes/write",
      "missing selector target",
      "option: ^externalize",
      "selector: /missing",
    ])
    check readFile(file_path) == "original parent"

  test "write rejects unsafe external_dir and child collisions before replacing parent":
    init_all()
    let root = fresh_dir("unsafe-external-dir")
    defer: remove_tree(root)
    let file_path = joinPath(root, "state.gene")
    let absolute_external_dir = joinPath(root, "absolute-children")

    proc reset_parent() =
      writeFile(file_path, "original parent")

    reset_parent()
    expect_vm_error_contains("(gene/serdes/write " & gene_string_literal(file_path) & " {^profile \"Ada\"} ^externalize [/profile] ^external_dir " & gene_string_literal(absolute_external_dir) & ")", "filesystem_serdes_write_external_dir_absolute", [
      "gene/serdes/write",
      "unsafe external dir",
      "target: " & file_path,
      "option: ^external_dir",
      "must be relative",
    ])
    check readFile(file_path) == "original parent"

    reset_parent()
    expect_vm_error_contains("(gene/serdes/write " & gene_string_literal(file_path) & " {^profile \"Ada\"} ^externalize [/profile] ^external_dir \"../outside\")", "filesystem_serdes_write_external_dir_traversal", [
      "gene/serdes/write",
      "unsafe external dir",
      "option: ^external_dir",
      "non-traversing",
    ])
    check readFile(file_path) == "original parent"

    reset_parent()
    expect_vm_error_contains("(gene/serdes/write " & gene_string_literal(file_path) & " {^profile \"Ada\"} ^externalize [/profile] ^external_dir \"\")", "filesystem_serdes_write_external_dir_empty", [
      "gene/serdes/write",
      "unsafe external dir",
      "option: ^external_dir",
      "must not be empty",
    ])
    check readFile(file_path) == "original parent"

    reset_parent()
    let blocked_external_dir = joinPath(root, "blocked")
    writeFile(blocked_external_dir, "not a directory")
    expect_vm_error_contains("(gene/serdes/write " & gene_string_literal(file_path) & " {^profile \"Ada\"} ^externalize [/profile] ^external_dir \"blocked\")", "filesystem_serdes_write_external_dir_file_collision", [
      "gene/serdes/write",
      "child path collision",
      "option: ^externalize",
      "child: blocked",
    ])
    check readFile(file_path) == "original parent"

    reset_parent()
    let default_external_dir = joinPath(root, "state.files")
    createDir(default_external_dir)
    createDir(joinPath(default_external_dir, "profile.gene"))
    expect_vm_error_contains("(gene/serdes/write " & gene_string_literal(file_path) & " {^profile \"Ada\"} ^externalize [/profile])", "filesystem_serdes_write_child_dir_collision", [
      "gene/serdes/write",
      "child path collision",
      "option: ^externalize",
      "selector: /profile",
      "child: " & joinPath("state.files", "profile.gene"),
    ])
    check readFile(file_path) == "original parent"

  test "write rejects externalizing array and map values until read_dir support lands":
    init_all()
    let root = fresh_dir("unsupported-shapes")
    defer: remove_tree(root)
    let file_path = joinPath(root, "state.gene")
    writeFile(file_path, "original parent")

    expect_vm_error_contains("(gene/serdes/write " & gene_string_literal(file_path) & " {^items [1 2]} ^externalize [/items])", "filesystem_serdes_write_externalize_array_unsupported", [
      "gene/serdes/write",
      "unsupported shape",
      "option: ^externalize",
      "selector: /items",
      "read_dir externalization",
    ])
    check readFile(file_path) == "original parent"
    check not dirExists(joinPath(root, "state.files"))

    expect_vm_error_contains("(gene/serdes/write " & gene_string_literal(file_path) & " {^profile {^name \"Ada\"}} ^externalize [/profile])", "filesystem_serdes_write_externalize_map_unsupported", [
      "gene/serdes/write",
      "unsupported shape",
      "option: ^externalize",
      "selector: /profile",
      "read_dir externalization",
    ])
    check readFile(file_path) == "original parent"

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
