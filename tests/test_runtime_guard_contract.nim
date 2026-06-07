import unittest, strutils

import gene/parser
import gene/types except Exception
import gene/types/runtime_types

proc runtime_guard_native_identity(vm: ptr VirtualMachine,
                                   args: ptr UncheckedArray[Value],
                                   arg_count: int,
                                   has_keyword_args: bool): Value {.gcsafe.} =
  get_positional_arg(args, 0, has_keyword_args)

proc expect_runtime_error(action: proc() {.closure.}): string =
  var raised = false
  try:
    action()
  except CatchableError as e:
    raised = true
    result = e.msg
  check raised

proc fn_type_id(descs: var seq[TypeDesc], param_type: TypeId,
                return_type: TypeId): TypeId =
  intern_type_desc(descs,
    TypeDesc(module_path: "tests/test_runtime_guard_contract.nim", kind: TdkFn,
      params: @[CallableParamDesc(kind: CpkPositional, keyword_name: "",
        type_id: param_type)],
      ret: return_type,
      effects: @[]))

suite "Runtime guard contract":
  test "guard accepts compatible values without warning":
    let descs = builtin_type_descs()
    let result = guard_runtime_type(1.to_value(), BUILTIN_TYPE_INT_ID, descs, param_name = "argument x")

    check result.ok
    check result.value == 1.to_value()
    check result.warning == ""
    check result.error.message == ""

  test "guard mismatch reports expected got and explicit context fields":
    let descs = builtin_type_descs()
    let context = GuardContext(
      enabled: true,
      phase: GpArgument,
      party: BpNegative,
      producer: "caller",
      consumer: "function",
      site: "unit-test:1")
    let result = guard_runtime_type("oops".to_value(), BUILTIN_TYPE_INT_ID, descs,
      param_name = "argument x", context = context)

    check not result.ok
    check result.error.code == TYPE_DIAG_MISMATCH_CODE
    check result.error.expected == "Int"
    check result.error.got == "String"
    check result.error.blame == "negative"
    check result.error.message.contains("Type error [GENE_TYPE_MISMATCH]: expected Int, got String in argument x")
    check result.error.message.contains("phase=argument")
    check result.error.message.contains("blame=negative")
    check result.error.message.contains("producer=caller")
    check result.error.message.contains("consumer=function")
    check result.error.message.contains("site=unit-test:1")

  test "guard strict nil mismatch keeps policy wording and site fallback":
    let descs = builtin_type_descs()
    let context = GuardContext(
      enabled: true,
      phase: GpArgument,
      party: BpNegative,
      producer: "caller",
      consumer: "function")
    let result = guard_runtime_type(NIL, BUILTIN_TYPE_INT_ID, descs,
      param_name = "argument x", strict_nil = true, context = context)

    check not result.ok
    check result.error.expected == "Int"
    check result.error.got == "Nil"
    check result.error.message.contains("Type error [GENE_TYPE_MISMATCH]: expected Int, got Nil in argument x")
    check result.error.message.contains("strict nil mode")
    check result.error.message.contains("Any, Nil, Option[T], or unions containing Nil")
    check result.error.message.contains("phase=argument")
    check result.error.message.contains("blame=negative")
    check result.error.message.contains("producer=caller")
    check result.error.message.contains("consumer=function")
    check result.error.message.contains("site=<unknown>")

  test "guard admits implicit nil only when enabled":
    let descs = builtin_type_descs()

    let denied = guard_runtime_type(NIL, BUILTIN_TYPE_INT_ID, descs,
      param_name = "argument x")
    check not denied.ok
    check denied.error.message.contains("expected Int, got Nil")

    let admitted = guard_runtime_type(NIL, BUILTIN_TYPE_INT_ID, descs,
      param_name = "argument x", allow_implicit_nil = true)
    check admitted.ok
    check admitted.value == NIL
    check admitted.warning == ""
    check admitted.error.message == ""

  test "guard preserves lossy coercion warning and converted value":
    let descs = builtin_type_descs()
    let result = guard_runtime_type(1.5.to_value(), BUILTIN_TYPE_INT_ID, descs,
      param_name = "argument x", location = "guard_contract:1")

    check result.ok
    check result.value.kind == VkInt
    check result.value.int64 == 1'i64
    check result.warning.contains("Lossy conversion Float -> Int for argument x")
    check result.warning.contains("1.5 -> 1")
    check result.warning.contains("guard_contract:1")
    check result.error.message == ""

  test "guard no-context mismatch preserves legacy text without guard fields":
    let descs = builtin_type_descs()
    let result = guard_runtime_type("oops".to_value(), BUILTIN_TYPE_INT_ID, descs,
      param_name = "argument x", location = "guard_contract:2")

    check not result.ok
    check result.error.message.contains("Type error [GENE_TYPE_MISMATCH]: expected Int, got String in argument x")
    check result.error.message.contains("guard_contract:2")
    check not result.error.message.contains("phase=")
    check not result.error.message.contains("blame=")
    check not result.error.message.contains("producer=")
    check not result.error.message.contains("consumer=")
    check not result.error.message.contains("site=")

  test "guard strict nil admits explicit nil-capable descriptors":
    var descs = builtin_type_descs()
    let option_int_id = intern_type_desc(descs,
      TypeDesc(module_path: "tests/test_runtime_guard_contract.nim", kind: TdkApplied,
        ctor: "Option", args: @[BUILTIN_TYPE_INT_ID]))

    let result = guard_runtime_type(NIL, option_int_id, descs,
      param_name = "argument option", strict_nil = true)

    check result.ok
    check result.value == NIL
    check result.warning == ""
    check result.error.message == ""

  test "guard preserves legacy ADT migration guidance":
    var descs = builtin_type_descs()
    let result_id = intern_type_desc(descs,
      TypeDesc(module_path: "tests/test_runtime_guard_contract.nim", kind: TdkNamed,
        name: "Result"))
    let legacy_value = parser.read("(Ok 1)")
    let result = guard_runtime_type(legacy_value, result_id, descs,
      param_name = "argument result")

    check not result.ok
    check result.error.message.contains("Type error [GENE_TYPE_MISMATCH]")
    check result.error.message.contains("legacy Gene-expression ADT value")
    check result.error.message.contains("Result")
    check result.error.message.contains("enum-backed Result constructors")
    check not result.error.message.contains("phase=")
    check not result.error.message.contains("blame=")

  test "guard consults native signatures for Fn-typed values":
    var descs = builtin_type_descs()
    let expected_fn_id = fn_type_id(descs, BUILTIN_TYPE_INT_ID, BUILTIN_TYPE_INT_ID)
    let native_fn = NativeFn(runtime_guard_native_identity)
    let native_value = native_fn.to_value()
    defer:
      invalidate_native_signature(native_fn)

    let non_callable = guard_runtime_type(1.to_value(), expected_fn_id, descs,
      param_name = "callback")
    check not non_callable.ok
    check non_callable.error.expected == "(Fn [Int] -> Int)"
    check non_callable.error.got == "Int"

    register_native_signature(native_fn, native_sig("[n: Int] -> Int"))
    let accepted = guard_runtime_type(native_value, expected_fn_id, descs,
      param_name = "callback")
    check accepted.ok

    register_native_signature(native_fn, native_sig("[s: String] -> String"))
    let rejected = guard_runtime_type(native_value, expected_fn_id, descs,
      param_name = "callback")
    check not rejected.ok
    check rejected.error.expected == "(Fn [Int] -> Int)"
    check rejected.error.got == "Function"
    check rejected.error.message.contains("expected (Fn [Int] -> Int), got Function")

  test "guard consults native method signatures for bound Fn-typed values":
    var descs = builtin_type_descs()
    let expected_fn_id = fn_type_id(descs, BUILTIN_TYPE_INT_ID, BUILTIN_TYPE_INT_ID)
    let native_fn = NativeFn(runtime_guard_native_identity)
    let cls = new_class("RuntimeGuardFnMethodTest")
    cls.def_native_method("id", native_fn, native_sig("[n: Int] -> Int"))
    let bound_ref = new_ref(VkBoundMethod)
    bound_ref.bound_method = BoundMethod(self: NIL, `method`: cls.get_method("id"))
    let bound_value = bound_ref.to_ref_value()
    defer:
      invalidate_native_signature(native_fn)

    let accepted = guard_runtime_type(bound_value, expected_fn_id, descs,
      param_name = "callback")
    check accepted.ok

    let wrong_fn_id = fn_type_id(descs, BUILTIN_TYPE_STRING_ID, BUILTIN_TYPE_STRING_ID)
    let rejected = guard_runtime_type(bound_value, wrong_fn_id, descs,
      param_name = "callback")
    check not rejected.ok
    check rejected.error.expected == "(Fn [String] -> String)"
    check rejected.error.got == "VkBoundMethod"

  test "validate_or_coerce_type preserves legacy no-context mismatch text":
    let descs = builtin_type_descs()
    var value = "oops".to_value()
    let message = expect_runtime_error(proc() =
      discard validate_or_coerce_type(value, BUILTIN_TYPE_INT_ID, descs,
        param_name = "argument x", location = "wrapper_contract:1"))

    check message.contains("Type error [GENE_TYPE_MISMATCH]: expected Int, got String in argument x")
    check message.contains("wrapper_contract:1")
    check not message.contains("phase=")
    check not message.contains("blame=")
    check not message.contains("producer=")
    check not message.contains("consumer=")
    check not message.contains("site=")

  test "validate_type explicit context mismatch appends guard fields":
    let descs = builtin_type_descs()
    let context = GuardContext(
      enabled: true,
      phase: GpArgument,
      party: BpNegative,
      producer: "caller",
      consumer: "function",
      site: "unit-test:1")
    let message = expect_runtime_error(proc() =
      validate_type("oops".to_value(), BUILTIN_TYPE_INT_ID, descs,
        param_name = "argument x", context = context))

    check message.contains("Type error [GENE_TYPE_MISMATCH]: expected Int, got String in argument x")
    check message.contains("phase=argument")
    check message.contains("blame=negative")
    check message.contains("producer=caller")
    check message.contains("consumer=function")
    check message.contains("site=unit-test:1")

  test "validate_or_coerce_type mutates caller value and returns warning":
    let descs = builtin_type_descs()
    var value = 1.5.to_value()
    let warning = validate_or_coerce_type(value, BUILTIN_TYPE_INT_ID, descs,
      param_name = "argument x", location = "wrapper_contract:2")

    check value.kind == VkInt
    check value.int64 == 1'i64
    check warning.contains("Lossy conversion Float -> Int for argument x")
    check warning.contains("1.5 -> 1")
    check warning.contains("wrapper_contract:2")

  test "validate_type keeps Float to Int invalid instead of coercing":
    let descs = builtin_type_descs()
    let value = 1.5.to_value()
    let message = expect_runtime_error(proc() =
      validate_type(value, BUILTIN_TYPE_INT_ID, descs,
        param_name = "argument x", location = "wrapper_contract:3"))

    check value.kind == VkFloat
    check message.contains("Type error [GENE_TYPE_MISMATCH]: expected Int, got Float in argument x")
    check message.contains("wrapper_contract:3")
    check not message.contains("phase=")
    check not message.contains("blame=")

  test "wrapper strict nil rejects Int and admits Option Int":
    var descs = builtin_type_descs()
    let option_int_id = intern_type_desc(descs,
      TypeDesc(module_path: "tests/test_runtime_guard_contract.nim", kind: TdkApplied,
        ctor: "Option", args: @[BUILTIN_TYPE_INT_ID]))

    var nil_value = NIL
    let message = expect_runtime_error(proc() =
      discard validate_or_coerce_type(nil_value, BUILTIN_TYPE_INT_ID, descs,
        param_name = "argument x", strict_nil = true))
    check message.contains("Type error [GENE_TYPE_MISMATCH]: expected Int, got Nil in argument x")
    check message.contains("strict nil mode")
    check not message.contains("phase=")
    check not message.contains("blame=")

    nil_value = NIL
    let warning = validate_or_coerce_type(nil_value, option_int_id, descs,
      param_name = "argument option", strict_nil = true)
    check warning == ""
    check nil_value == NIL

    validate_type(NIL, option_int_id, descs,
      param_name = "argument option", strict_nil = true)
