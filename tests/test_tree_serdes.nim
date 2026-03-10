import os, unittest, strformat, tables, strutils

import gene/types except Exception
import gene/vm

import ./helpers

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

proc fresh_path(name: string): string =
  let path = joinPath(getTempDir(), "gene-tree-serdes-" & name)
  remove_tree(path)
  remove_tree(path & ".gene")
  path

proc file_count(path: string): int =
  for kind, child in walkDir(path):
    if kind == pcFile:
      inc(result)

suite "filesystem tree serdes":
  test "logical root path defaults to one inline file":
    init_all()
    let root_path = fresh_path("inline")
    let code = fmt"""
      (var value {{^name "alpha" ^items [1 2 3] ^nested {{^ok true}}}})
      (gene/serdes/write_tree "{root_path}" value)
      (var loaded (gene/serdes/read_tree "{root_path}"))
      (assert (loaded/name == "alpha"))
      (assert (loaded/items/0 == 1))
      (assert (loaded/items/2 == 3))
      (assert (loaded/nested/ok == true))
      true
    """
    check VM.exec(code, "tree_serdes_inline") == TRUE
    check fileExists(root_path & ".gene")
    check not dirExists(root_path)
    check readFile(root_path & ".gene").contains("(gene/serialization ")

  test "^separate [/*] stores root children individually":
    init_all()
    let root_path = fresh_path("root-separated")
    let code = fmt"""
      (var value {{
        ^alpha 1
        ^nested {{^beta 2}}
        ^arr ["x" "y" "z"]
      }})
      (gene/serdes/write_tree "{root_path}" value ^separate [/*])
      (var loaded (gene/serdes/read_tree "{root_path}"))
      (assert (loaded/alpha == 1))
      (assert (loaded/nested/beta == 2))
      (assert (loaded/arr/0 == "x"))
      (assert (loaded/arr/2 == "z"))
      true
    """
    check VM.exec(code, "tree_serdes_dir_map") == TRUE
    check dirExists(root_path)
    check not fileExists(root_path & ".gene")
    check fileExists(joinPath(root_path, "alpha.gene"))
    check fileExists(joinPath(root_path, "nested.gene"))
    check fileExists(joinPath(root_path, "arr.gene"))
    check not dirExists(joinPath(root_path, "nested"))
    check not dirExists(joinPath(root_path, "arr"))

  test "^separate [/a/*] makes ancestors directories and preserves array order":
    init_all()
    let root_path = fresh_path("nested-separated")
    let code = fmt"""
      (var value {{
        ^a [{{^x 1}} {{^x 2}}]
        ^b {{^z 3}}
      }})
      (gene/serdes/write_tree "{root_path}" value ^separate [/a/*])
      (var loaded (gene/serdes/read_tree "{root_path}"))
      (assert (loaded/a/0/x == 1))
      (assert (loaded/a/1/x == 2))
      (assert (loaded/b/z == 3))
      true
    """
    check VM.exec(code, "tree_serdes_nested_separate") == TRUE
    check dirExists(root_path)
    check fileExists(joinPath(root_path, "b.gene"))
    check dirExists(joinPath(root_path, "a"))
    check fileExists(joinPath(root_path, "a", "_genearray.gene"))
    check not fileExists(joinPath(root_path, "a", "0.gene"))
    check not fileExists(joinPath(root_path, "a", "1.gene"))
    check file_count(joinPath(root_path, "a")) == 3

  test "separated Gene values use _genetype.gene with _geneprops and _genechildren directories":
    init_all()
    let root_path = fresh_path("gene-node")
    let code = fmt"""
      (var value `(Widget ^title "hello" "first" {{^count 2}}))
      (gene/serdes/write_tree "{root_path}" value ^separate [/*])
      (gene/serdes/read_tree "{root_path}")
    """
    let loaded = VM.exec(code, "tree_serdes_gene_node")
    check dirExists(root_path)
    check not fileExists(root_path & ".gene")
    check fileExists(joinPath(root_path, "_genetype.gene"))
    check dirExists(joinPath(root_path, "_geneprops"))
    check dirExists(joinPath(root_path, "_genechildren"))
    check fileExists(joinPath(root_path, "_geneprops", "title.gene"))
    check fileExists(joinPath(root_path, "_genechildren", "_genearray.gene"))
    check loaded.gene_type == new_gene_symbol("Widget")
    let props = loaded.gene_props
    check props["title"] == "hello".to_value()
    let children = loaded.gene_children
    check children.len == 2
    check children[0] == "first".to_value()
    check children[1] == new_map_value({"count".to_key(): 2.to_value()}.to_table())

  test "^separate can target _genetype as a synthetic child subtree":
    init_all()
    let root_path = fresh_path("gene-type-separated")
    let code = fmt"""
      (var value `({{^kind "Widget"}} ^title "hello"))
      (gene/serdes/write_tree "{root_path}" value ^separate [/_genetype/*])
      (gene/serdes/read_tree "{root_path}")
    """
    let loaded = VM.exec(code, "tree_serdes_gene_type_separated")
    check dirExists(root_path)
    check dirExists(joinPath(root_path, "_genetype"))
    check fileExists(joinPath(root_path, "_genetype", "kind.gene"))
    check not fileExists(joinPath(root_path, "_genetype.gene"))
    check loaded.gene_type.kind == VkMap
    check map_data(loaded.gene_type)["kind".to_key()] == "Widget".to_value()
    let props = loaded.gene_props
    check props["title"] == "hello".to_value()

  test "empty exploded directory decodes as an empty map":
    init_all()
    let root_path = fresh_path("empty-map")
    createDir(root_path)
    let loaded = VM.exec(fmt"""(gene/serdes/read_tree "{root_path}")""", "tree_serdes_empty_map")
    check loaded.kind == VkMap
    check map_data(loaded).len == 0

  test "generic exploded map roots reject only the reserved _genetype marker":
    init_all()
    let genetype_path = fresh_path("reserved-genetype")
    expect CatchableError:
      discard VM.exec(fmt"""
        (gene/serdes/write_tree "{genetype_path}" {{^_genetype 1}} ^separate [/*])
      """, "tree_serdes_reserved_genetype")

    let array_marker_path = fresh_path("reserved-array-marker")
    let loaded = VM.exec(fmt"""
      (var value {{^_genearray 1 ^plain 2}})
      (gene/serdes/write_tree "{array_marker_path}" value ^separate [/*])
      (gene/serdes/read_tree "{array_marker_path}")
    """, "tree_serdes_reserved_array_marker")
    check loaded.kind == VkMap
    check map_data(loaded)["_genearray".to_key()] == 1.to_value()
    check map_data(loaded)["plain".to_key()] == 2.to_value()
