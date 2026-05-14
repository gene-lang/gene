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

const TreeSerdesLeakFragments = ["_genetype", "_geneprops", "_genechildren", "_genearray", "^separate"]
const RemovedFilesystemPrefixes = ["read", "write"]

proc expect_no_tree_serdes_leak(label, text: string) =
  checkpoint(label & ": " & text)
  for fragment in TreeSerdesLeakFragments:
    checkpoint("forbidden tree-serdes fragment: " & fragment)
    check not text.contains(fragment)
  for prefix in RemovedFilesystemPrefixes:
    let api_name = prefix & "_" & "tree"
    checkpoint("forbidden removed API fragment: " & api_name)
    check not text.contains(api_name)

proc expect_read_file_ref_payload(parent_payload, ref_path: string) =
  expect_no_tree_serdes_leak("write parent payload", parent_payload)
  check parent_payload.contains("(gene/serdes/read_file " & gene_string_literal(ref_path) & ")")

proc expect_read_dir_ref_payload(parent_payload, ref_path, shape: string) =
  expect_no_tree_serdes_leak("write parent payload", parent_payload)
  check parent_payload.contains("(gene/serdes/read_dir")
  check parent_payload.contains(gene_string_literal(ref_path))
  check parent_payload.contains("^shape " & shape)
  check parent_payload.contains("^order name")

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
      "phase: child path generation",
    ])
    check readFile(file_path) == "original parent"

  test "write externalizes selected arrays with deterministic read_dir refs":
    init_all()
    let root = fresh_dir("externalize-array-dir")
    defer: remove_tree(root)
    let file_path = joinPath(root, "state.gene")
    let external_dir = joinPath(root, "state.files")
    let items_dir = joinPath(external_dir, "items")
    let items_ref = joinPath("state.files", "items")

    discard VM.exec("(gene/serdes/write " & gene_string_literal(file_path) & " {^items [0 1 2 3 4 5 6 7 8 9 10 11]} ^externalize [/items])", "filesystem_serdes_write_externalize_array_dir")

    check fileExists(file_path)
    check dirExists(items_dir)
    check sorted_entries(root) == @[
      $pcDir & ":state.files",
      $pcFile & ":state.gene",
    ]
    check sorted_entries(external_dir) == @[$pcDir & ":items"]
    check sorted_entries(items_dir) == @[
      $pcFile & ":000000.gene",
      $pcFile & ":000001.gene",
      $pcFile & ":000002.gene",
      $pcFile & ":000003.gene",
      $pcFile & ":000004.gene",
      $pcFile & ":000005.gene",
      $pcFile & ":000006.gene",
      $pcFile & ":000007.gene",
      $pcFile & ":000008.gene",
      $pcFile & ":000009.gene",
      $pcFile & ":000010.gene",
      $pcFile & ":000011.gene",
    ]
    check not fileExists(joinPath(items_dir, "_genearray.gene"))
    check not fileExists(joinPath(items_dir, "_genetype.gene"))
    check not dirExists(joinPath(items_dir, "_geneprops"))
    check not dirExists(joinPath(items_dir, "_genechildren"))

    let parent_serialized = readFile(file_path)
    checkpoint("externalized array parent payload: " & parent_serialized)
    expect_read_dir_ref_payload(parent_serialized, items_ref, "array")
    check readFile(joinPath(items_dir, "000000.gene")) == "(gene/serialization 0)"
    check readFile(joinPath(items_dir, "000011.gene")) == "(gene/serialization 11)"

    let read_back = VM.exec("(gene/serdes/read " & gene_string_literal(file_path) & ")", "filesystem_serdes_write_externalize_array_dir_read")
    check read_back.kind == VkMap
    let items = map_data(read_back)["items".to_key()]
    check items.kind == VkArray
    var expected: seq[Value] = @[]
    for i in 0..11:
      expected.add(i.to_value())
    check array_data(items) == expected

  test "write externalizes selected maps with encoded keys and stable cleanup":
    init_all()
    let root = fresh_dir("externalize-map-dir")
    defer: remove_tree(root)
    let file_path = joinPath(root, "state.gene")
    let external_dir = joinPath(root, "state.files")
    let profile_dir = joinPath(external_dir, "profile")
    let profile_ref = joinPath("state.files", "profile")
    createDir(profile_dir)
    writeFile(joinPath(profile_dir, "stale.gene"), "(gene/serialization \"stale\")")

    var profile = new_map_value()
    map_data(profile) = initTable[Key, Value]()
    map_data(profile)["plain".to_key()] = "plain-value".to_value()
    map_data(profile)["a/b".to_key()] = "slash-value".to_value()
    map_data(profile)["a b".to_key()] = "space-value".to_value()
    var payload = new_map_value()
    map_data(payload) = initTable[Key, Value]()
    map_data(payload)["profile".to_key()] = profile
    App.app.global_ns.ref.ns["writer_map_payload".to_key()] = payload

    let source = "(gene/serdes/write " & gene_string_literal(file_path) & " writer_map_payload ^externalize [/profile])"
    discard VM.exec(source, "filesystem_serdes_write_externalize_map_dir")
    let first_parent = readFile(file_path)
    let first_entries = sorted_entries(profile_dir)
    let first_plain = readFile(joinPath(profile_dir, "plain.gene"))
    let first_slash = readFile(joinPath(profile_dir, "a%2Fb.gene"))
    let first_space = readFile(joinPath(profile_dir, "a%20b.gene"))

    check sorted_entries(external_dir) == @[$pcDir & ":profile"]
    check first_entries == @[
      $pcFile & ":a%20b.gene",
      $pcFile & ":a%2Fb.gene",
      $pcFile & ":plain.gene",
    ]
    checkpoint("externalized map parent payload: " & first_parent)
    check first_parent.contains("(gene/serdes/read_dir")
    check first_parent.contains(gene_string_literal(profile_ref))
    check first_parent.contains("^shape map")
    check first_parent.contains("^order name")
    check first_plain == "(gene/serialization \"plain-value\")"
    check first_slash == "(gene/serialization \"slash-value\")"
    check first_space == "(gene/serialization \"space-value\")"

    writeFile(joinPath(profile_dir, "zz-stale.gene"), "(gene/serialization \"stale\")")
    discard VM.exec(source, "filesystem_serdes_write_externalize_map_dir_repeat")
    check readFile(file_path) == first_parent
    check sorted_entries(profile_dir) == first_entries
    check readFile(joinPath(profile_dir, "plain.gene")) == first_plain
    check readFile(joinPath(profile_dir, "a%2Fb.gene")) == first_slash
    check readFile(joinPath(profile_dir, "a%20b.gene")) == first_space

    let read_back = VM.exec("(gene/serdes/read " & gene_string_literal(file_path) & ")", "filesystem_serdes_write_externalize_map_dir_read")
    check read_back.kind == VkMap
    let profile_back = map_data(read_back)["profile".to_key()]
    check profile_back.kind == VkMap
    check map_data(profile_back)["plain".to_key()] == "plain-value".to_value()
    check map_data(profile_back)["a/b".to_key()] == "slash-value".to_value()
    check map_data(profile_back)["a b".to_key()] == "space-value".to_value()

  test "write externalizes empty arrays and maps as empty read_dir directories":
    init_all()
    let root = fresh_dir("externalize-empty-dirs")
    defer: remove_tree(root)
    let file_path = joinPath(root, "state.gene")
    let items_dir = joinPath(root, "state.files", "items")
    let profile_dir = joinPath(root, "state.files", "profile")

    var payload = new_map_value()
    map_data(payload) = initTable[Key, Value]()
    map_data(payload)["items".to_key()] = new_array_value()
    var profile = new_map_value()
    map_data(profile) = initTable[Key, Value]()
    map_data(payload)["profile".to_key()] = profile
    App.app.global_ns.ref.ns["writer_empty_payload".to_key()] = payload

    discard VM.exec("(gene/serdes/write " & gene_string_literal(file_path) & " writer_empty_payload ^externalize [/items /profile])", "filesystem_serdes_write_externalize_empty_dirs")

    check dirExists(items_dir)
    check dirExists(profile_dir)
    check sorted_entries(items_dir) == newSeq[string]()
    check sorted_entries(profile_dir) == newSeq[string]()
    let parent_serialized = readFile(file_path)
    checkpoint("externalized empty collections parent payload: " & parent_serialized)
    check parent_serialized.contains(gene_string_literal(joinPath("state.files", "items")))
    check parent_serialized.contains(gene_string_literal(joinPath("state.files", "profile")))
    check parent_serialized.contains("^shape array")
    check parent_serialized.contains("^shape map")

    let read_back = VM.exec("(gene/serdes/read " & gene_string_literal(file_path) & ")", "filesystem_serdes_write_externalize_empty_dirs_read")
    check array_data(map_data(read_back)["items".to_key()]).len == 0
    check map_data(map_data(read_back)["profile".to_key()]).len == 0

  test "write rejects unsafe map child keys before replacing parent":
    init_all()
    let root = fresh_dir("externalize-map-unsafe-keys")
    defer: remove_tree(root)
    let file_path = joinPath(root, "state.gene")
    let profile_dir = joinPath(root, "state.files", "profile")

    proc reset_parent() =
      writeFile(file_path, "original parent")
      remove_tree(profile_dir)
      if dirExists(joinPath(root, "state.files")) and sorted_entries(joinPath(root, "state.files")) == newSeq[string]():
        removeDir(joinPath(root, "state.files"))

    proc install_payload(key_name: string) =
      var profile = new_map_value()
      map_data(profile) = initTable[Key, Value]()
      map_data(profile)[key_name.to_key()] = "value".to_value()
      var payload = new_map_value()
      map_data(payload) = initTable[Key, Value]()
      map_data(payload)["profile".to_key()] = profile
      App.app.global_ns.ref.ns["writer_unsafe_map_payload".to_key()] = payload

    reset_parent()
    install_payload("")
    expect_vm_error_contains("(gene/serdes/write " & gene_string_literal(file_path) & " writer_unsafe_map_payload ^externalize [/profile])", "filesystem_serdes_write_externalize_empty_map_key", [
      "gene/serdes/write",
      "unsafe child name",
      "phase: pre-validation",
      "selector: /profile",
      "map key is empty",
    ])
    check readFile(file_path) == "original parent"
    check not dirExists(profile_dir)

    reset_parent()
    install_payload(".")
    expect_vm_error_contains("(gene/serdes/write " & gene_string_literal(file_path) & " writer_unsafe_map_payload ^externalize [/profile])", "filesystem_serdes_write_externalize_dot_map_key", [
      "gene/serdes/write",
      "unsafe child name",
      "phase: pre-validation",
      "selector: /profile",
      "key: .",
    ])
    check readFile(file_path) == "original parent"
    check not dirExists(profile_dir)

    reset_parent()
    install_payload("..")
    expect_vm_error_contains("(gene/serdes/write " & gene_string_literal(file_path) & " writer_unsafe_map_payload ^externalize [/profile])", "filesystem_serdes_write_externalize_dotdot_map_key", [
      "gene/serdes/write",
      "unsafe child name",
      "phase: pre-validation",
      "selector: /profile",
      "key: ..",
    ])
    check readFile(file_path) == "original parent"
    check not dirExists(profile_dir)

  test "write preserves parent and existing children when externalized child serialization fails":
    init_all()
    let root = fresh_dir("externalize-child-serialization-failure")
    defer: remove_tree(root)
    let file_path = joinPath(root, "state.gene")
    let external_dir = joinPath(root, "state.files")
    let child_ref = joinPath("state.files", "profile.gene")
    let child_path = joinPath(root, child_ref)

    writeFile(file_path, "original parent")
    createDir(external_dir)
    writeFile(child_path, "(gene/serialization \"original child\")")

    expect_vm_error_contains("(var pending (async 1))\n(gene/serdes/write " & gene_string_literal(file_path) & " {^profile pending} ^externalize [/profile])", "filesystem_serdes_write_externalized_child_serialization_failure", [
      "gene/serdes/write",
      "serialization failed",
      "target: " & file_path,
      "option: ^externalize",
      "selector: /profile",
      "child: " & child_ref,
      "phase: pre-validation",
      "not serializable",
    ])
    check readFile(file_path) == "original parent"
    check readFile(child_path) == "(gene/serialization \"original child\")"
    check sorted_entries(external_dir) == @[$pcFile & ":profile.gene"]
    check not fileExists(file_path & ".tmp")
    check not fileExists(child_path & ".tmp")

  test "write materializes lazy read_file refs before writing exact roots and external children":
    init_all()
    let root = fresh_dir("materialize-lazy-read-file")
    defer: remove_tree(root)
    let source_map_path = joinPath(root, "source-map.gene")
    let source_scalar_path = joinPath(root, "source-scalar.gene")
    let exact_path = joinPath(root, "exact.gene")
    let file_path = joinPath(root, "state.gene")
    let child_ref = joinPath("state.files", "child.gene")
    let child_path = joinPath(root, child_ref)

    writeFile(source_map_path, "(gene/serialization {^name \"lazy-child\" ^count 2})")
    writeFile(source_scalar_path, "(gene/serialization \"lazy-scalar\")")

    discard VM.exec("(var lazy_map (gene/serdes/read_file " & gene_string_literal(source_map_path) & " ^lazy true))\n" &
      "(var lazy_child (gene/serdes/read_file " & gene_string_literal(source_scalar_path) & " ^lazy true))\n" &
      "(gene/serdes/write " & gene_string_literal(exact_path) & " lazy_map)\n" &
      "(gene/serdes/write " & gene_string_literal(file_path) & " {^child lazy_child ^label \"wrapper\"} ^externalize [/child])",
      "filesystem_serdes_write_materializes_lazy_ref")

    let exact_serialized = readFile(exact_path)
    let parent_serialized = readFile(file_path)
    let child_serialized = readFile(child_path)
    expect_no_tree_serdes_leak("exact lazy write payload", exact_serialized)
    expect_read_file_ref_payload(parent_serialized, child_ref)
    expect_no_tree_serdes_leak("externalized lazy child payload", child_serialized)
    check exact_serialized.contains("^name \"lazy-child\"")
    check exact_serialized.contains("^count 2")
    check child_serialized == "(gene/serialization \"lazy-scalar\")"
    check not exact_serialized.contains("LazyFileRefValue")
    check not child_serialized.contains("LazyFileRefValue")

    let read_back = VM.exec("(gene/serdes/read " & gene_string_literal(file_path) & ")", "filesystem_serdes_write_materializes_lazy_ref_read")
    check read_back.kind == VkMap
    check map_data(read_back)["child".to_key()] == "lazy-scalar".to_value()

  test "write repeats mixed externalization with stable refs files and no tree marker leakage":
    init_all()
    let root = fresh_dir("mixed-stability")
    defer: remove_tree(root)
    let file_path = joinPath(root, "state.gene")
    let external_dir = joinPath(root, "state.files")
    let count_ref = joinPath("state.files", "count.gene")
    let items_ref = joinPath("state.files", "items")
    let profile_ref = joinPath("state.files", "profile")
    let count_path = joinPath(root, count_ref)
    let items_dir = joinPath(root, items_ref)
    let profile_dir = joinPath(root, profile_ref)
    let source = "(gene/serdes/write " & gene_string_literal(file_path) &
      " {^count 7 ^items [\"a\" \"b\"] ^profile {^name \"Ada\" ^team \"core\"}} ^externalize [/count /items /profile])"

    discard VM.exec(source, "filesystem_serdes_write_mixed_stability_first")
    let first_parent = readFile(file_path)
    let first_count = readFile(count_path)
    let first_external_entries = sorted_entries(external_dir)
    let first_items_entries = sorted_entries(items_dir)
    let first_profile_entries = sorted_entries(profile_dir)

    expect_read_file_ref_payload(first_parent, count_ref)
    expect_read_dir_ref_payload(first_parent, items_ref, "array")
    expect_read_dir_ref_payload(first_parent, profile_ref, "map")
    check first_count == "(gene/serialization 7)"
    check first_items_entries == @[
      $pcFile & ":000000.gene",
      $pcFile & ":000001.gene",
    ]
    check first_profile_entries == @[
      $pcFile & ":name.gene",
      $pcFile & ":team.gene",
    ]

    writeFile(joinPath(items_dir, "999999.gene"), "(gene/serialization \"stale\")")
    writeFile(joinPath(profile_dir, "stale.gene"), "(gene/serialization \"stale\")")
    discard VM.exec(source, "filesystem_serdes_write_mixed_stability_repeat")
    check readFile(file_path) == first_parent
    check readFile(count_path) == first_count
    check sorted_entries(external_dir) == first_external_entries
    check sorted_entries(items_dir) == first_items_entries
    check sorted_entries(profile_dir) == first_profile_entries

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
