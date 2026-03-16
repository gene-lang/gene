import os, strutils, unittest

import gene/viewer/model

suite "Terminal Gene Viewer Model":
  test "multi-form input becomes a synthetic root sequence":
    let source = """
      # comment
      (log ^level "info" ^msg "ready")
      [1 {^inner [2 3]}]
      {^status true}
    """
    let doc = open_viewer_document_from_source(source, "logs/sample.gene")
    let state = new_viewer_state(doc)

    check doc.root.kind == VnkSequence
    check doc.root.entries.len == 3
    check state.selected_path() == "/0"
    check doc.root.entries[0].summary.contains("(log")
    check doc.root.entries[1].node.kind == VnkArray
    check doc.root.entries[2].node.kind == VnkMap

  test "navigation drills into nested values and restores parent selection":
    let source = """
      (root
        ^meta {^name "demo" ^enabled true}
        [10 {^leaf [1 2]}]
        ^flag true
      )
    """
    let doc = open_viewer_document_from_source(source, "nested.gene")
    let state = new_viewer_state(doc)

    check doc.root.kind == VnkGene
    check state.current_frame().node.entries.len == 4
    check state.selected_path() == "/type"

    state.move_selection(2, 10)
    check state.selected_path() == "/0"

    state.enter_selected()
    check state.frames.len == 2
    check state.current_frame().node.kind == VnkArray
    check state.selected_path() == "/0/0"

    state.move_selection(1, 10)
    check state.selected_path() == "/0/1"

    state.enter_selected()
    check state.frames.len == 3
    check state.current_frame().node.kind == VnkMap
    check state.selected_path() == "/0/1/leaf"

    state.enter_selected()
    check state.frames.len == 4
    check state.current_frame().node.kind == VnkArray
    check state.selected_path() == "/0/1/leaf/0"

    state.leave_current()
    check state.frames.len == 3
    check state.current_frame().selected == 0
    check state.selected_path() == "/0/1/leaf"

    state.leave_current()
    check state.frames.len == 2
    check state.current_frame().selected == 1
    check state.selected_path() == "/0/1"

  test "reload preserves the deepest still-valid selection path":
    let source_path = absolutePath("tmp/viewer_reload.gene")
    createDir(parentDir(source_path))
    writeFile(source_path, "[1 [2 3] 4]")

    defer:
      if fileExists(source_path):
        removeFile(source_path)

    let doc = open_viewer_document(source_path)
    let state = new_viewer_state(doc)
    state.move_selection(1, 10)
    state.enter_selected()
    state.move_selection(1, 10)
    check state.selected_path() == "/1/1"

    writeFile(source_path, "[1 [2 3 4] 5]")
    state.reload()

    check state.frames.len == 2
    check state.current_frame().node.kind == VnkArray
    check state.selected_path() == "/1/1"
