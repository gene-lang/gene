import std/[os, strutils, unittest]

import ../helpers
import gene/types except Exception
import gene/vm

proc gene_string_literal(value: string): string =
  "\"" & value.replace("\\", "\\\\").replace("\"", "\\\"") & "\""

proc fresh_dir(name: string): string =
  result = joinPath(getTempDir(), "gene-stdlib-filesystem-" & name & "-" & intToStr(getCurrentProcessId()))
  if dirExists(result):
    removeDir(result)

suite "Filesystem stdlib":
  test "file, directory, and path helpers cover common workflows":
    init_all()

    let root = fresh_dir("workflow")
    defer:
      if dirExists(root):
        removeDir(root)

    let moved = joinPath(root, "moved.txt")
    let expectedRelative = relativePath(moved, root)
    let expectedNormalized = normalizedPath(joinPath(root, ".", "moved.txt"))

    let result = VM.exec("""
      (var root """ & gene_string_literal(root) & """)
      (var nested (Path/join root "a" "b"))
      (Dir/create_all nested)
      (var original (Path/join nested "note.txt"))
      (File/write original "hello")
      (var copy (Path/join root "copy.txt"))
      (File/copy original copy)
      (var moved (Path/join root "moved.txt"))
      (File/move copy moved)
      (var info (File/info moved))
      (var split (Path/split moved))
      [
        (Dir/exists nested)
        (File/exists original)
        (File/exists copy)
        (File/read moved)
        (File/size moved)
        info/kind
        split/name
        split/ext
        (Path/base moved)
        (Path/relative moved root)
        (Path/normalize (Path/join root "." "moved.txt"))
        (Path/is_abs moved)
      ]
    """, "stdlib_filesystem_workflow.gene")

    check result.kind == VkArray
    let values = array_data(result)
    check values.len == 12
    check values[0].to_bool == true
    check values[1].to_bool == true
    check values[2].to_bool == false
    check values[3].str == "hello"
    check values[4].to_int == 5
    check values[5].str == "file"
    check values[6].str == "moved"
    check values[7].str == ".txt"
    check values[8].str == "moved.txt"
    check values[9].str == expectedRelative
    check values[10].str == expectedNormalized
    check values[11].to_bool == true

  test "directory entries and recursive walk include kind metadata":
    init_all()

    let root = fresh_dir("walk")
    defer:
      if dirExists(root):
        removeDir(root)

    let result = VM.exec("""
      (var root """ & gene_string_literal(root) & """)
      (Dir/create_all (Path/join root "nested"))
      (File/write (Path/join root "alpha.txt") "a")
      (File/write (Path/join root "nested" "beta.txt") "b")
      [
        ((Dir/entries root) .size)
        ((Dir/walk root) .size)
      ]
    """, "stdlib_filesystem_walk.gene")

    check result.kind == VkArray
    let values = array_data(result)
    check values[0].to_int == 2
    check values[1].to_int == 3
