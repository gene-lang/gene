import unittest, strutils

import ./helpers
import ../src/gene/native/trampoline
import ../src/gene/types except Exception

proc native_identity(vm: ptr VirtualMachine, args: ptr UncheckedArray[Value],
                     arg_count: int, has_keyword_args: bool): Value {.gcsafe.} =
  get_positional_arg(args, 0, has_keyword_args)

proc native_bad_return(vm: ptr VirtualMachine, args: ptr UncheckedArray[Value],
                       arg_count: int, has_keyword_args: bool): Value {.gcsafe.} =
  "bad".to_value()

proc expect_error(action: proc() {.closure.}): string =
  try:
    action()
    fail()
  except CatchableError as e:
    result = e.msg

suite "Native signatures":
  test "native_sig parses built-in signatures and rejects unknown types":
    let sig = native_sig("[n: Int label: String] -> (Int | Nil)")
    check sig.params.len == 2
    check sig.param_names == @["n", "label"]
    check sig.params[0].type_id == BUILTIN_TYPE_INT_ID
    check sig.params[1].type_id == BUILTIN_TYPE_STRING_ID
    check sig.return_type_id notin [NO_TYPE_ID, BUILTIN_TYPE_ANY_ID]
    check sig.abi_arg_types == @[CatInt64, CatValue]
    check sig.abi_return_type == CrtValue

    let message = expect_error(proc() =
      discard native_sig("[user: User] -> Int")
    )
    check message.contains("native_sig only accepts built-in types")

  test "native method signature overload prefixes receiver ABI":
    init_all()
    let cls = new_class("NativeSignatureTest")
    let fn = NativeFn(native_identity)
    cls.def_native_method("id", fn, native_sig("[n: Int] -> Int"))
    defer:
      invalidate_native_signature(fn)

    let meth = cls.get_method("id")
    check meth != nil
    check meth.native_signature != nil
    check meth.native_signature.receives_self
    check meth.native_signature.abi_arg_types == @[CatValue, CatInt64]

    var abi: NativeFnSig
    check lookup_native_sig(fn, abi)
    check abi.argTypes == @[CatValue, CatInt64]
    check abi.returnType == CrtInt64

  test "typed native signature validates arguments and exposes ABI":
    init_all()
    let fn = NativeFn(native_identity)
    let sig = build_native_signature_from_legacy(@[("n", App.app.int_class)],
      App.app.int_class, receives_self = false)
    register_native_signature(fn, sig)
    defer:
      invalidate_native_signature(fn)

    check call_native_fn(fn, VM, @[42.to_value()]).to_int() == 42

    let message = expect_error(proc() =
      discard call_native_fn(fn, VM, @["oops".to_value()])
    )
    check message.contains("expected Int, got String")
    check message.contains("phase=argument")
    check message.contains("producer=caller")
    check message.contains("consumer=native")

    var abi: NativeFnSig
    check lookup_native_sig(fn, abi)
    check abi.argTypes == @[CatInt64]
    check abi.returnType == CrtInt64

  test "typed native signature validates return value":
    init_all()
    let fn = NativeFn(native_bad_return)
    let sig = build_native_signature_from_legacy([], App.app.int_class,
      receives_self = false)
    register_native_signature(fn, sig)
    defer:
      invalidate_native_signature(fn)

    let message = expect_error(proc() =
      discard call_native_fn(fn, VM, @[])
    )
    check message.contains("expected Int, got String")
    check message.contains("phase=return")
    check message.contains("producer=native")
    check message.contains("consumer=caller")
