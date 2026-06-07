import unittest, strutils, tables

import ./helpers
import ../src/gene/native/trampoline
import ../src/gene/parser
import ../src/gene/type_checker as tc
import ../src/gene/types except Exception
import ../src/gene/vm

proc native_identity(vm: ptr VirtualMachine, args: ptr UncheckedArray[Value],
                     arg_count: int, has_keyword_args: bool): Value {.gcsafe.} =
  get_positional_arg(args, 0, has_keyword_args)

proc native_bad_return(vm: ptr VirtualMachine, args: ptr UncheckedArray[Value],
                       arg_count: int, has_keyword_args: bool): Value {.gcsafe.} =
  "bad".to_value()

proc native_method_arg(vm: ptr VirtualMachine, args: ptr UncheckedArray[Value],
                       arg_count: int, has_keyword_args: bool): Value {.gcsafe.} =
  get_method_arg(args, 0, has_keyword_args)

proc expect_error(action: proc() {.closure.}): string =
  try:
    action()
    fail()
  except CatchableError as e:
    result = e.msg

proc expect_static_error(code: string): string =
  let checker = tc.new_type_checker(strict = true, module_filename = "native_static.gene")
  try:
    for node in read_all(code):
      checker.type_check_node(node)
    fail()
  except CatchableError as e:
    result = e.msg

proc expect_static_ok(code: string) =
  let checker = tc.new_type_checker(strict = true, module_filename = "native_static.gene")
  for node in read_all(code):
    checker.type_check_node(node)

proc map_value(value: Value, key: string): Value =
  check value.kind == VkMap
  map_data(value)[key.to_key()]

proc param_at(params: Value, index: int): Value =
  check params.kind == VkArray
  array_data(params)[index]

proc desc_at(sig: NativeSignature, type_id: TypeId): TypeDesc =
  check sig != nil
  check type_id != NO_TYPE_ID
  check type_id.int >= 0
  check type_id.int < sig.type_descriptors.len
  sig.type_descriptors[type_id.int]

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

  test "stdlib type retrofits annotate callback-shaped collection methods at bootstrap":
    init_all()

    let array_map = App.app.array_class.ref.class.get_method("map")
    check array_map != nil
    check array_map.native_signature_known
    check array_map.native_signature != nil
    check array_map.native_signature.receives_self
    check array_map.native_signature.params.len == 1
    check array_map.native_signature.param_names == @["callback"]

    let callback_desc = desc_at(array_map.native_signature,
      array_map.native_signature.params[0].type_id)
    check callback_desc.kind == TdkFn
    check callback_desc.params.len == 1
    check callback_desc.params[0].type_id == BUILTIN_TYPE_ANY_ID
    check callback_desc.ret == BUILTIN_TYPE_ANY_ID

    let array_return_desc = desc_at(array_map.native_signature,
      array_map.native_signature.return_type_id)
    check array_return_desc.kind == TdkApplied
    check array_return_desc.ctor == "Array"
    check array_return_desc.args == @[BUILTIN_TYPE_ANY_ID]

    let array_filter = App.app.array_class.ref.class.get_method("filter")
    check array_filter != nil
    let predicate_desc = desc_at(array_filter.native_signature,
      array_filter.native_signature.params[0].type_id)
    check predicate_desc.kind == TdkFn
    check predicate_desc.ret == BUILTIN_TYPE_BOOL_ID

    let map_reduce = App.app.map_class.ref.class.get_method("reduce")
    check map_reduce != nil
    let reducer_desc = desc_at(map_reduce.native_signature,
      map_reduce.native_signature.params[1].type_id)
    check reducer_desc.kind == TdkFn
    check reducer_desc.params.len == 3

    let mapped = VM.exec("""
      ([1 2] .map (fn [value: Any] -> Any
        (* value 2)))
    """, "stdlib_collection_type_retrofit_callback.gene")
    check mapped.kind == VkArray
    check array_data(mapped)[0].to_int() == 2
    check array_data(mapped)[1].to_int() == 4

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
    check message.contains("blame=negative")
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
    check message.contains("blame=positive")
    check message.contains("producer=native")
    check message.contains("consumer=caller")

  test "strict native types reject unannotated native callables until typed":
    init_all()
    let fn = NativeFn(native_identity)
    defer:
      VM.strict_native_types = false
      App.app.strict_native_types = false
      invalidate_native_signature(fn)

    VM.strict_native_types = true
    var message = expect_error(proc() =
      discard call_native_fn(fn, VM, @[42.to_value()])
    )
    check message.contains("strict native types require a non-Any NativeSignature")

    register_native_signature(fn, native_sig("[value: Any] -> Any"))
    message = expect_error(proc() =
      discard call_native_fn(fn, VM, @[42.to_value()])
    )
    check message.contains("strict native types require a non-Any NativeSignature")

    register_native_signature(fn, native_sig("[n: Int] -> Int"))
    check call_native_fn(fn, VM, @[42.to_value()]).to_int() == 42

    VM.strict_native_types = false
    invalidate_native_signature(fn)
    App.app.strict_native_types = true
    message = expect_error(proc() =
      discard call_native_fn(fn, VM, @[42.to_value()])
    )
    check message.contains("strict native types require a non-Any NativeSignature")

  test "$assign-method-type attaches and enforces a native method signature":
    init_all()
    let cls = new_class("AssignMethodSigTest")
    cls.def_native_method("id", native_method_arg)
    let cls_ref = new_ref(VkClass)
    cls_ref.class = cls
    let cls_val = cls_ref.to_ref_value()
    App.app.global_ns.ref.ns["AssignMethodSigTest".to_key()] = cls_val

    check App.app.global_ns.ref.ns["$assign-method-type".to_key()].kind == VkNativeMacro
    discard VM.exec("""($assign-method-type AssignMethodSigTest "id" [n: Int] -> Int)""",
      "assign_method_type.gene")
    defer:
      invalidate_native_signature(NativeFn(native_method_arg))

    let meth = cls.get_method("id")
    let registry_sig = lookup_native_signature(NativeFn(native_method_arg))
    check registry_sig != nil
    check meth.native_signature_known
    check meth.native_signature != nil
    check meth.native_signature.receives_self
    check meth.native_signature.abi_arg_types == @[CatValue, CatInt64]

    check VM.exec("""((new AssignMethodSigTest) .id 7)""",
      "assign_method_type_ok.gene").to_int() == 7
    let message = expect_error(proc() =
      discard VM.exec("""((new AssignMethodSigTest) .id "bad")""",
        "assign_method_type_bad.gene")
    )
    check message.contains("expected Int, got String")
    check message.contains("phase=argument")

  test "$assign-type attaches and enforces a standalone native function signature":
    init_all()
    let fn = NativeFn(native_identity)
    App.app.global_ns.ref.ns["assignEcho".to_key()] = fn.to_value()

    discard VM.exec("""($assign-type assignEcho [n: Int] -> Int)""",
      "assign_type.gene")
    defer:
      invalidate_native_signature(fn)

    let sig = lookup_native_signature(fn)
    check sig != nil
    check sig.params.len == 1
    check sig.params[0].type_id == BUILTIN_TYPE_INT_ID
    check sig.abi_arg_types == @[CatInt64]

    check VM.exec("""(assignEcho 9)""", "assign_type_ok.gene").to_int() == 9
    let message = expect_error(proc() =
      discard VM.exec("""(assignEcho "bad")""", "assign_type_bad.gene")
    )
    check message.contains("expected Int, got String")
    check message.contains("phase=argument")

  test "$assign-type rejects conflicts and bang form overrides":
    init_all()
    let fn = NativeFn(native_identity)
    App.app.global_ns.ref.ns["assignConflictEcho".to_key()] = fn.to_value()

    discard VM.exec("""($assign-type assignConflictEcho [n: Int] -> Int)""",
      "assign_type_conflict_initial.gene")
    defer:
      invalidate_native_signature(fn)

    discard VM.exec("""($assign-type assignConflictEcho [n: Int] -> Int)""",
      "assign_type_conflict_same.gene")

    let conflict_message = expect_error(proc() =
      discard VM.exec("""($assign-type assignConflictEcho [s: String] -> String)""",
        "assign_type_conflict_bad.gene")
    )
    check conflict_message.contains("$assign-type conflicts with existing native signature")
    check conflict_message.contains("$assign-type! to override")
    check lookup_native_signature(fn).return_type_id == BUILTIN_TYPE_INT_ID

    discard VM.exec("""($assign-type! assignConflictEcho [s: String] -> String)""",
      "assign_type_conflict_override.gene")

    let overridden = lookup_native_signature(fn)
    check overridden != nil
    check overridden.return_type_id == BUILTIN_TYPE_STRING_ID
    check VM.exec("""(assignConflictEcho "ok")""",
      "assign_type_conflict_override_call.gene").str == "ok"

  test "binding-site fn ^native attaches and enforces a native function signature":
    init_all()
    let fn = NativeFn(native_identity)
    App.app.global_ns.ref.ns["nativeDeclEchoImpl".to_key()] = fn.to_value()

    let declared = VM.exec("""
      (fn nativeDeclEcho [n: Int] -> Int
        ^native nativeDeclEchoImpl)
    """, "native_decl_fn.gene")
    defer:
      invalidate_native_signature(fn)

    check declared.kind == VkNativeFn
    let sig = lookup_native_signature(fn)
    check sig != nil
    check sig.params.len == 1
    check sig.params[0].type_id == BUILTIN_TYPE_INT_ID
    check sig.return_type_id == BUILTIN_TYPE_INT_ID
    check sig.abi_arg_types == @[CatInt64]

    check VM.exec("""
      (fn nativeDeclEchoOk [n: Int] -> Int
        ^native nativeDeclEchoImpl)
      (nativeDeclEchoOk 13)
    """,
      "native_decl_fn_ok.gene").to_int() == 13
    let message = expect_error(proc() =
      discard VM.exec("""
        (fn nativeDeclEchoBad [n: Int] -> Int
          ^native nativeDeclEchoImpl)
        (nativeDeclEchoBad "bad")
      """,
        "native_decl_fn_bad.gene")
    )
    check message.contains("expected Int, got String")
    check message.contains("phase=argument")

  test "generic native signatures are rejected until native generics are designed":
    init_all()
    let fn = NativeFn(native_identity)
    App.app.global_ns.ref.ns["genericNativeDeclImpl".to_key()] = fn.to_value()
    defer:
      invalidate_native_signature(fn)

    let message = expect_error(proc() =
      discard VM.exec("""
        (fn genericNativeDecl:T [value: T] -> T
          ^native genericNativeDeclImpl)
      """, "native_decl_generic_rejected.gene")
    )
    check message.contains("does not support generic native signatures yet")
    check message.contains("concrete types or Any")
    check lookup_native_signature(fn) == nil

  test "Function reflection exposes user and standalone native signatures uniformly":
    init_all()
    let fn = NativeFn(native_identity)
    App.app.global_ns.ref.ns["nativeReflectImpl".to_key()] = fn.to_value()

    let reflected = VM.exec("""
      (fn reflectedUser [n: Int ^label: String] -> String
        label)
      (fn reflectedNative [n: Int] -> Int
        ^native nativeReflectImpl)
      [(reflectedUser .signature)
       (reflectedNative .signature)
       (reflectedNative .params)
       (reflectedNative .return_type)
       ((reflectedNative .class) .name)]
    """, "native_reflection_fn.gene")
    defer:
      invalidate_native_signature(fn)

    check reflected.kind == VkArray
    let user_meta = array_data(reflected)[0]
    let native_meta = array_data(reflected)[1]
    let native_params = array_data(reflected)[2]

    let user_params = map_value(user_meta, "params")
    check map_value(param_at(user_params, 0), "name").str == "n"
    check map_value(param_at(user_params, 0), "kind").str == "positional"
    check map_value(param_at(user_params, 0), "type").str == "Int"
    check map_value(param_at(user_params, 1), "name").str == "label"
    check map_value(param_at(user_params, 1), "kind").str == "keyword"
    check map_value(param_at(user_params, 1), "keyword").str == "label"
    check map_value(param_at(user_params, 1), "type").str == "String"
    check map_value(user_meta, "return_type").str == "String"
    check map_value(user_meta, "native?") == FALSE

    check map_value(native_meta, "return_type").str == "Int"
    check map_value(native_meta, "native?") == TRUE
    check map_value(native_meta, "receives_self?") == FALSE
    check map_value(native_meta, "has_type_annotations?") == TRUE
    check map_value(param_at(map_value(native_meta, "params"), 0), "name").str == "n"
    check map_value(param_at(map_value(native_meta, "params"), 0), "type").str == "Int"
    check map_value(param_at(native_params, 0), "type").str == "Int"
    check array_data(reflected)[3].str == "Int"
    check array_data(reflected)[4].str == "Function"

  test "Function reflection hides implicit self for user and native methods":
    init_all()
    let native_fn = NativeFn(native_method_arg)
    let cls = new_class("NativeReflectionMethodTest")
    cls.def_native_method("native_id", native_fn, native_sig("[n: Int] -> Int"))
    let cls_ref = new_ref(VkClass)
    cls_ref.class = cls
    App.app.global_ns.ref.ns["NativeReflectionMethodTest".to_key()] =
      cls_ref.to_ref_value()
    defer:
      invalidate_native_signature(native_fn)

    let user_class = VM.exec("""
      (class UserReflectionMethodTest
        (ctor [] nil)
        (method id [n: Int] -> Int n))
    """, "native_reflection_user_method.gene")
    check user_class.kind == VkClass

    let signature_method = App.app.function_class.ref.class.get_method("signature")
    check signature_method != nil
    check signature_method.callable.kind == VkNativeFn

    let native_bound_ref = new_ref(VkBoundMethod)
    native_bound_ref.bound_method = BoundMethod(self: NIL, `method`: cls.get_method("native_id"))
    let native_meta = call_native_fn(signature_method.callable.ref.native_fn, VM,
      @[native_bound_ref.to_ref_value()])

    let user_bound_ref = new_ref(VkBoundMethod)
    user_bound_ref.bound_method = BoundMethod(self: NIL,
      `method`: user_class.ref.class.get_method("id"))
    let user_meta = call_native_fn(signature_method.callable.ref.native_fn, VM,
      @[user_bound_ref.to_ref_value()])

    check map_value(native_meta, "native?") == TRUE
    check map_value(native_meta, "receives_self?") == TRUE
    check map_value(native_meta, "return_type").str == "Int"
    check array_data(map_value(native_meta, "params")).len == 1
    check map_value(param_at(map_value(native_meta, "params"), 0), "name").str == "n"
    check map_value(param_at(map_value(native_meta, "params"), 0), "type").str == "Int"

    check map_value(user_meta, "native?") == FALSE
    check map_value(user_meta, "receives_self?") == TRUE
    check map_value(user_meta, "return_type").str == "Int"
    check array_data(map_value(user_meta, "params")).len == 1
    check map_value(param_at(map_value(user_meta, "params"), 0), "name").str == "n"
    check map_value(param_at(map_value(user_meta, "params"), 0), "type").str == "Int"

  test "binding-site method ^native treats self as implicit and enforces user args":
    init_all()
    let fn = NativeFn(native_method_arg)
    App.app.global_ns.ref.ns["nativeDeclMethodImpl".to_key()] = fn.to_value()

    let class_value = VM.exec("""
      (class NativeDeclMethodMetaTest
        (ctor [] nil)
        (method id [n: Int] -> Int
          ^native nativeDeclMethodImpl))
    """, "native_decl_method.gene")
    defer:
      invalidate_native_signature(fn)

    check class_value.kind == VkClass
    let cls = class_value.ref.class
    let meth = cls.get_method("id")
    check meth != nil
    check meth.callable.kind == VkNativeFn
    check meth.native_signature_known
    check meth.native_signature != nil
    check meth.native_signature.receives_self
    check meth.native_signature.params.len == 1
    check meth.native_signature.params[0].type_id == BUILTIN_TYPE_INT_ID
    check meth.native_signature.abi_arg_types == @[CatValue, CatInt64]

    check VM.exec("""
      (class NativeDeclMethodCallTest
        (ctor [] nil)
        (method id [n: Int] -> Int
          ^native nativeDeclMethodImpl))
      ((new NativeDeclMethodCallTest) .id 21)
    """,
      "native_decl_method_ok.gene").to_int() == 21
    let message = expect_error(proc() =
      discard VM.exec("""
        (class NativeDeclMethodBadTest
          (ctor [] nil)
          (method id [n: Int] -> Int
            ^native nativeDeclMethodImpl))
        ((new NativeDeclMethodBadTest) .id "bad")
      """,
        "native_decl_method_bad.gene")
    )
    check message.contains("expected Int, got String")
    check message.contains("phase=argument")

  test "$assign-method-type rejects conflicts and bang form overrides":
    init_all()
    let fn = NativeFn(native_method_arg)
    let cls = new_class("AssignMethodConflictTest")
    cls.def_native_method("id", fn)
    let cls_ref = new_ref(VkClass)
    cls_ref.class = cls
    App.app.global_ns.ref.ns["AssignMethodConflictTest".to_key()] =
      cls_ref.to_ref_value()

    discard VM.exec("""($assign-method-type AssignMethodConflictTest "id" [n: Int] -> Int)""",
      "assign_method_type_conflict_initial.gene")
    defer:
      invalidate_native_signature(fn)

    discard VM.exec("""($assign-method-type AssignMethodConflictTest "id" [n: Int] -> Int)""",
      "assign_method_type_conflict_same.gene")

    let conflict_message = expect_error(proc() =
      discard VM.exec("""($assign-method-type AssignMethodConflictTest "id" [s: String] -> String)""",
        "assign_method_type_conflict_bad.gene")
    )
    check conflict_message.contains("$assign-method-type conflicts with existing native signature")
    check conflict_message.contains("$assign-method-type! to override")
    check cls.get_method("id").native_signature.return_type_id == BUILTIN_TYPE_INT_ID

    discard VM.exec("""($assign-method-type! AssignMethodConflictTest "id" [s: String] -> String)""",
      "assign_method_type_conflict_override.gene")

    let overridden = cls.get_method("id").native_signature
    check overridden != nil
    check overridden.return_type_id == BUILTIN_TYPE_STRING_ID
    check VM.exec("""((new AssignMethodConflictTest) .id "ok")""",
      "assign_method_type_conflict_override_call.gene").str == "ok"

  test "static checker consumes standalone native function signatures":
    init_all()
    let fn = NativeFn(native_identity)
    App.app.global_ns.ref.ns["staticNativeEcho".to_key()] = fn.to_value()
    register_native_signature(fn, native_sig("[n: Int] -> Int"))
    defer:
      invalidate_native_signature(fn)

    expect_static_ok("""(staticNativeEcho 9)""")

    let arg_message = expect_static_error("""(staticNativeEcho "bad")""")
    check arg_message.contains("expected Int")
    check arg_message.contains("got String")

    let ret_message = expect_static_error("""
      (var x: String (staticNativeEcho 9))
    """)
    check ret_message.contains("expected String")
    check ret_message.contains("got Int")

  test "static checker consumes binding-site fn ^native declaration signatures":
    expect_static_ok("""
      (fn nativeStaticDecl [n: Int] -> Int
        ^native nativeStaticDeclImpl)
      (var x: Int (nativeStaticDecl 9))
    """)

    let arg_message = expect_static_error("""
      (fn nativeStaticDeclBad [n: Int] -> Int
        ^native nativeStaticDeclImpl)
      (nativeStaticDeclBad "bad")
    """)
    check arg_message.contains("expected Int")
    check arg_message.contains("got String")

  test "$assign-ctor-type attaches and enforces a native constructor signature":
    init_all()
    let cls = new_class("AssignCtorSigTest")
    cls.def_native_constructor(NativeFn(native_identity))
    let cls_ref = new_ref(VkClass)
    cls_ref.class = cls
    let cls_val = cls_ref.to_ref_value()
    App.app.global_ns.ref.ns["AssignCtorSigTest".to_key()] = cls_val

    discard VM.exec("""($assign-ctor-type AssignCtorSigTest [n: Int] -> Int)""",
      "assign_ctor_type.gene")
    defer:
      invalidate_native_signature(NativeFn(native_identity))

    check cls.constructor_native_signature_known
    check cls.constructor_native_signature != nil
    check cls.constructor_native_signature.abi_arg_types == @[CatInt64]

    check VM.exec("""(new AssignCtorSigTest 11)""",
      "assign_ctor_type_ok.gene").to_int() == 11
    let message = expect_error(proc() =
      discard VM.exec("""(new AssignCtorSigTest "bad")""",
        "assign_ctor_type_bad.gene")
    )
    check message.contains("expected Int, got String")
    check message.contains("phase=argument")

  test "$assign-ctor-type rejects conflicts and bang form overrides":
    init_all()
    let fn = NativeFn(native_identity)
    let cls = new_class("AssignCtorConflictTest")
    cls.def_native_constructor(fn)
    let cls_ref = new_ref(VkClass)
    cls_ref.class = cls
    App.app.global_ns.ref.ns["AssignCtorConflictTest".to_key()] =
      cls_ref.to_ref_value()

    discard VM.exec("""($assign-ctor-type AssignCtorConflictTest [n: Int] -> Int)""",
      "assign_ctor_type_conflict_initial.gene")
    defer:
      invalidate_native_signature(fn)

    discard VM.exec("""($assign-ctor-type AssignCtorConflictTest [n: Int] -> Int)""",
      "assign_ctor_type_conflict_same.gene")

    let conflict_message = expect_error(proc() =
      discard VM.exec("""($assign-ctor-type AssignCtorConflictTest [s: String] -> String)""",
        "assign_ctor_type_conflict_bad.gene")
    )
    check conflict_message.contains("$assign-ctor-type conflicts with existing native signature")
    check conflict_message.contains("$assign-ctor-type! to override")
    check cls.constructor_native_signature.return_type_id == BUILTIN_TYPE_INT_ID

    discard VM.exec("""($assign-ctor-type! AssignCtorConflictTest [s: String] -> String)""",
      "assign_ctor_type_conflict_override.gene")

    check cls.constructor_native_signature != nil
    check cls.constructor_native_signature.return_type_id == BUILTIN_TYPE_STRING_ID
    check VM.exec("""(new AssignCtorConflictTest "ok")""",
      "assign_ctor_type_conflict_override_call.gene").str == "ok"

  test "static checker consumes native constructor signatures":
    init_all()
    let cls = new_class("StaticNativeCtorSigTest")
    cls.def_native_constructor(NativeFn(native_identity),
      native_sig("[n: Int] -> Int"))
    let cls_ref = new_ref(VkClass)
    cls_ref.class = cls
    App.app.global_ns.ref.ns["StaticNativeCtorSigTest".to_key()] =
      cls_ref.to_ref_value()
    defer:
      invalidate_native_signature(NativeFn(native_identity))

    expect_static_ok("""(new StaticNativeCtorSigTest 11)""")

    let message = expect_static_error("""
      (new StaticNativeCtorSigTest "bad")
    """)
    check message.contains("expected Int")
    check message.contains("got String")

  test "binding-site ctor ^native attaches and enforces a native constructor signature":
    init_all()
    let fn = NativeFn(native_identity)
    App.app.global_ns.ref.ns["nativeDeclCtorImpl".to_key()] = fn.to_value()

    let class_value = VM.exec("""
      (class NativeDeclCtorMetaTest
        (ctor [n: Int] -> Int
          ^native nativeDeclCtorImpl))
    """, "native_decl_ctor.gene")
    defer:
      invalidate_native_signature(fn)

    check class_value.kind == VkClass
    let cls = class_value.ref.class
    check cls.constructor.kind == VkNativeFn
    check cls.constructor_native_signature_known
    check cls.constructor_native_signature != nil
    check cls.constructor_native_signature.params.len == 1
    check cls.constructor_native_signature.params[0].type_id == BUILTIN_TYPE_INT_ID
    check cls.constructor_native_signature.abi_arg_types == @[CatInt64]

    check VM.exec("""
      (class NativeDeclCtorCallTest
        (ctor [n: Int] -> Int
          ^native nativeDeclCtorImpl))
      (new NativeDeclCtorCallTest 34)
    """,
      "native_decl_ctor_ok.gene").to_int() == 34
    let message = expect_error(proc() =
      discard VM.exec("""
        (class NativeDeclCtorBadTest
          (ctor [n: Int] -> Int
            ^native nativeDeclCtorImpl))
        (new NativeDeclCtorBadTest "bad")
      """,
        "native_decl_ctor_bad.gene")
    )
    check message.contains("expected Int, got String")
    check message.contains("phase=argument")
