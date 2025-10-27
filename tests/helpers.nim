import unittest, strutils, tables

import ../src/gene/types except Exception
import ../src/gene/parser
import ../src/gene/vm
import ../src/gene/serdes

# Uncomment below lines to see logs
# import logging
# addHandler(newConsoleLogger())

converter to_value*(self: seq[int]): Value =
  let r = new_ref(VkArray)
  for item in self:
    r.arr.add(item.to_value())
  result = r.to_ref_value()

converter seq_to_gene*(self: seq[string]): Value =
  let r = new_ref(VkArray)
  for item in self:
    r.arr.add(item.to_value())
  result = r.to_ref_value()

converter to_value*(self: openArray[(string, Value)]): Value =
  var map = Table[Key, Value]()
  for (k, v) in self:
    map[k.to_key()] = v
  new_map_value(map)

# Helper functions for serialization tests
proc new_gene_int*(val: int): Value =
  val.to_value()

proc new_gene_symbol*(s: string): Value =
  s.to_symbol_value()

proc gene_type*(v: Value): Value =
  if v.kind == VkGene:
    v.gene.type
  else:
    raise newException(ValueError, "Not a gene value")

proc gene_props*(v: Value): Table[string, Value] =
  if v.kind == VkGene:
    result = initTable[string, Value]()
    for k, val in v.gene.props:
      # k is a Key (distinct int64), which is a packed symbol value
      let symbol_value = cast[Value](k)
      let symbol_index = cast[uint64](symbol_value) and PAYLOAD_MASK
      result[get_symbol(symbol_index.int)] = val
  else:
    raise newException(ValueError, "Not a gene value")

proc gene_children*(v: Value): seq[Value] =
  if v.kind == VkGene:
    v.gene.children
  else:
    raise newException(ValueError, "Not a gene value")

proc cleanup*(code: string): string =
  result = code
  result.stripLineEnd
  if result.contains("\n"):
    result = "\n" & result

var initialized = false

# Test-specific native functions
proc test1(vm: VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value =
  1.to_value()

proc test2(vm: VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value =
  # TODO: Implement instance_props access when needed
  # For now, just add the two arguments
  if arg_count >= 2:
    let a = get_positional_arg(args, 0, has_keyword_args).to_int()
    let b = get_positional_arg(args, 1, has_keyword_args).to_int()
    return (a + b).to_value()
  else:
    return 0.to_value()

proc test_increment(vm: VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value {.gcsafe, nimcall.} =
  if arg_count > 0:
    let x = get_positional_arg(args, 0, has_keyword_args).to_int()
    return (x + 1).to_value()
  else:
    return 1.to_value()

proc test_reentry(vm: VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value =
  if arg_count < 2:
    return NIL

  let fn_val = get_positional_arg(args, 0, has_keyword_args)
  let arg_val = get_positional_arg(args, 1, has_keyword_args)

  if fn_val.kind != VkFunction:
    not_allowed("test_reentry expects a function as first argument")

  let first = vm.exec_function(fn_val, @[arg_val])
  let second = vm.exec_function(fn_val, @[first])
  return second

proc init_all*() =
  if not initialized:
    init_app_and_vm()
    init_stdlib()
    # Register test functions in gene namespace
    App.app.gene_ns.ns["test1".to_key()] = test1.to_value()
    App.app.gene_ns.ns["test2".to_key()] = test2.to_value()
    App.app.gene_ns.ns["test_increment".to_key()] = test_increment.to_value()
    let reentry_fn = cast[NativeFn](test_reentry)
    App.app.gene_ns.ns["test_reentry".to_key()] = reentry_fn.to_value()
    initialized = true

proc test_parser*(code: string, result: Value) =
  var code = cleanup(code)
  test "Parser / read: " & code:
    check read(code) == result

proc test_parser*(code: string, callback: proc(result: Value)) =
  var code = cleanup(code)
  test "Parser / read: " & code:
    var parser = new_parser()
    callback parser.read(code)

proc test_parser_error*(code: string) =
  var code = cleanup(code)
  test "Parser error expected: " & code:
    try:
      discard read(code)
      fail()
    except ParseError:
      discard

proc test_read_all*(code: string, result: seq[Value]) =
  var code = cleanup(code)
  test "Parser / read_all: " & code:
    check read_all(code) == result

proc test_read_all*(code: string, callback: proc(result: seq[Value])) =
  var code = cleanup(code)
  test "Parser / read_all: " & code:
    callback read_all(code)

proc test_vm*(code: string) =
  var code = cleanup(code)
  test "Compilation & VM: " & code:
    init_all()
    discard VM.exec(code, "test_code")

proc test_vm*(trace: bool, code: string, result: Value) =
  var code = cleanup(code)
  test "Compilation & VM: " & code:
    init_all()
    VM.trace = trace
    check VM.exec(code, "test_code") == result

proc test_vm*(code: string, result: Value) =
  test_vm(false, code, result)

proc test_vm*(code: string, callback: proc(result: Value)) =
  var code = cleanup(code)
  test "Compilation & VM: " & code:
    init_all()
    callback VM.exec(code, "test_code")

proc test_vm*(trace: bool, code: string, callback: proc(result: Value)) =
  var code = cleanup(code)
  test "Compilation & VM: " & code:
    init_all()
    VM.trace = trace
    callback VM.exec(code, "test_code")

proc test_vm_error*(code: string) =
  var code = cleanup(code)
  test "Compilation & VM: " & code:
    init_all()
    try:
      discard VM.exec(code, "test_code")
      fail()
    except CatchableError:
      discard

proc test_serdes*(code: string, result: Value) =
  var code = cleanup(code)
  test "Serdes: " & code:
    init_all()
    init_serdes()
    var value = VM.exec(code, "test_code")
    var s = serialize(value).to_s()
    var value2 = deserialize(s)
    check value2 == result

proc test_serdes*(code: string, callback: proc(result: Value)) =
  var code = cleanup(code)
  test "Serdes: " & code:
    init_all()
    init_serdes()
    var value = VM.exec(code, "test_code")
    var s = serialize(value).to_s()
    var value2 = deserialize(s)
    callback(value2)
