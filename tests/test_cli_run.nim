import unittest, os, streams

import gene/gir
import commands/run as run_command

suite "Run CLI":
  test "run falls back to source when cached GIR is unreadable":
    let source_path = absolutePath("tmp/run_cli_fallback.gene")
    createDir(parentDir(source_path))
    writeFile(source_path, "(var x 42)\nx")

    let gir_path = get_gir_path(source_path, "build")
    createDir(parentDir(gir_path))
    writeFile(gir_path, "broken-gir")

    defer:
      if fileExists(source_path):
        removeFile(source_path)
      if fileExists(gir_path):
        removeFile(gir_path)

    let result = run_command.handle("run", @[source_path])
    check result.success

  test "run invalidates stale GIR version caches and recompiles":
    let source_path = absolutePath("tmp/run_cli_version_invalidation.gene")
    createDir(parentDir(source_path))
    writeFile(source_path, "(var x 7)\nx")

    let gir_path = get_gir_path(source_path, "build")
    if fileExists(gir_path):
      removeFile(gir_path)

    defer:
      if fileExists(source_path):
        removeFile(source_path)
      if fileExists(gir_path):
        removeFile(gir_path)

    let first = run_command.handle("run", @[source_path])
    check first.success
    check fileExists(gir_path)

    var stream = newFileStream(gir_path, fmReadWrite)
    check stream != nil
    stream.setPosition(4)
    stream.write(1'u32)
    stream.close()

    let second = run_command.handle("run", @[source_path])
    check second.success

    let refreshed = load_gir_file(gir_path)
    check refreshed.header.version == GIR_VERSION
