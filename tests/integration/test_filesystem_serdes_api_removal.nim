import strutils, tables, unittest

import gene/types except Exception
import gene/vm

import ../helpers

const
  RemovedTreeSuffix = "tree"
  RemovedFilesystemPrefixes = ["read", "write"]

proc removed_member_name(prefix: string): string =
  prefix & "_" & RemovedTreeSuffix

proc expect_vm_error(source, name: string): string =
  var raised = false
  try:
    discard VM.exec(source, name)
  except CatchableError as e:
    raised = true
    result = e.msg

  checkpoint("VM error message: " & result)
  check raised

suite "filesystem serdes API removal":
  test "old tree filesystem members are absent from namespace":
    init_all()
    let serdes_value = App.app.gene_ns.ref.ns["serdes".to_key()]
    check serdes_value.kind == VkNamespace

    let serdes_ns = serdes_value.ref.ns
    for prefix in RemovedFilesystemPrefixes:
      let name = removed_member_name(prefix)
      checkpoint("removed member: " & name)
      check not serdes_ns.members.hasKey(name.to_key())

    for supported in ["write", "read", "read_file", "read_dir"]:
      checkpoint("supported member: " & supported)
      check serdes_ns.members.hasKey(supported.to_key())

  test "old tree filesystem calls fail instead of aliasing":
    init_all()
    for prefix in RemovedFilesystemPrefixes:
      let name = removed_member_name(prefix)
      let message = expect_vm_error("(gene/serdes/" & name & " \"unused\")", "filesystem_serdes_removed_" & prefix)
      check not message.contains("gene/serdes/write failed")
      check not message.contains("gene/serdes/read_file failed")
      check not message.contains("gene/serdes/read_dir failed")
