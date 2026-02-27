import algorithm
import os
import sets
import strutils
import unittest

proc extract_ik_tokens(line: string): seq[string] =
  var i = 0
  while true:
    let start = line.find("Ik", i)
    if start < 0:
      break
    var j = start + 2
    while j < line.len and (line[j].isAlphaNumeric or line[j] == '_'):
      inc(j)
    result.add(line[start ..< j])
    i = j

proc emitted_opcodes(): HashSet[string] =
  var files = @["src/gene/compiler.nim"]
  for path in walkDirRec("src/gene/compiler"):
    if path.endsWith(".nim"):
      files.add(path)

  for path in files:
    for line in lines(path):
      if line.find("kind:") >= 0 and line.find("Ik") >= 0:
        for token in extract_ik_tokens(line):
          result.incl(token)

proc vm_dispatch_opcodes(): HashSet[string] =
  for line in lines("src/gene/vm/exec.nim"):
    if line.find("of Ik") >= 0:
      for token in extract_ik_tokens(line):
        result.incl(token)

suite "Opcode dispatch coverage":
  test "compiler-emitted opcodes exist in VM dispatch":
    let emitted = emitted_opcodes()
    let handled = vm_dispatch_opcodes()
    var missing: seq[string] = @[]

    for opcode in emitted:
      if not handled.contains(opcode):
        missing.add(opcode)

    missing.sort(system.cmp[string])
    check missing.len == 0
    if missing.len > 0:
      checkpoint("Missing VM handlers for emitted opcodes: " & missing.join(", "))
