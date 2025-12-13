import strutils

# Nimble does not support path to dependency yet
include ../../../../src/gene/extension/boilerplate

proc init*(vm: ptr VirtualMachine): Namespace {.exportc, dynlib.} =
  result = new_namespace("my_lib")
  let upcase_fn = proc(vm: ptr VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value {.wrap_exception, gcsafe, nimcall.} =
    if arg_count < 1:
      not_allowed("upcase expects 1 argument")
    let v = args[0]
    case v.kind
    of VkString, VkSymbol:
      result = v.str.to_upper().to_value()
    else:
      not_allowed("upcase expects string or symbol, got " & $v.kind)
  result["upcase".to_key()] = wrap_native_fn(upcase_fn)
