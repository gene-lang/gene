import unittest, strutils

import gene/parser
import gene/types except Exception
import gene/types/runtime_types

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
      producer: "caller",
      consumer: "function",
      site: "unit-test:1")
    let result = guard_runtime_type("oops".to_value(), BUILTIN_TYPE_INT_ID, descs,
      param_name = "argument x", context = context)

    check not result.ok
    check result.error.code == TYPE_DIAG_MISMATCH_CODE
    check result.error.expected == "Int"
    check result.error.got == "String"
    check result.error.message.contains("Type error [GENE_TYPE_MISMATCH]: expected Int, got String in argument x")
    check result.error.message.contains("phase=argument")
    check result.error.message.contains("producer=caller")
    check result.error.message.contains("consumer=function")
    check result.error.message.contains("site=unit-test:1")

  test "guard strict nil mismatch keeps policy wording and site fallback":
    let descs = builtin_type_descs()
    let context = GuardContext(
      enabled: true,
      phase: GpArgument,
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
