import unittest, strutils

import gene/types except Exception
import gene/types/runtime_types

const TestModulePath = "tests/test_strict_nil_policy.nim"

proc expect_strict_nil_mismatch(type_id: TypeId, type_descs: seq[TypeDesc], context: string) =
  var value = NIL
  var raised = false
  try:
    discard validate_or_coerce_type(value, type_id, type_descs, context, "strict_nil_policy:1", strict_nil = true)
  except CatchableError as e:
    raised = true
    checkpoint e.msg
    check e.msg.contains(TYPE_DIAG_MISMATCH_CODE)
    check e.msg.contains("strict nil mode")
    check e.msg.contains("Any, Nil, Option[T], or unions containing Nil")
    check e.msg.contains("expected")
    check e.msg.contains("got Nil")
    check e.msg.contains(context)
    check e.msg.contains("strict_nil_policy:1")
  check raised

proc expect_strict_nil_admitted(type_id: TypeId, type_descs: seq[TypeDesc], context: string) =
  var value = NIL
  let warning = validate_or_coerce_type(value, type_id, type_descs, context, "strict_nil_policy:1", strict_nil = true)
  check warning == ""
  check value == NIL

suite "Strict nil policy":
  test "descriptor admissibility admits only explicit nil-capable targets":
    var descs = builtin_type_descs()
    let option_int_id = intern_type_desc(descs,
      TypeDesc(module_path: TestModulePath, kind: TdkApplied, ctor: "Option", args: @[BUILTIN_TYPE_INT_ID]))
    let int_or_nil_id = intern_type_desc(descs,
      TypeDesc(module_path: TestModulePath, kind: TdkUnion, members: @[BUILTIN_TYPE_INT_ID, BUILTIN_TYPE_NIL_ID]))

    check nil_admitted_by_type_id(BUILTIN_TYPE_ANY_ID, descs)
    check nil_admitted_by_type_id(BUILTIN_TYPE_NIL_ID, descs)
    check nil_admitted_by_type_id(option_int_id, descs)
    check nil_admitted_by_type_id(int_or_nil_id, descs)

    check not nil_admitted_by_type_id(BUILTIN_TYPE_INT_ID, descs)
    check not nil_admitted_by_type_id(NO_TYPE_ID, descs)
    check not nil_admitted_by_type_id(9999'i32, descs)

  test "descriptor admissibility fails closed for malformed applied and union metadata":
    var descs = builtin_type_descs()
    let malformed_option_id = intern_type_desc(descs,
      TypeDesc(module_path: TestModulePath, kind: TdkApplied, ctor: "Option", args: @[9999'i32]))
    let arityless_option_id = intern_type_desc(descs,
      TypeDesc(module_path: TestModulePath, kind: TdkApplied, ctor: "Option", args: @[]))
    let malformed_union_id = intern_type_desc(descs,
      TypeDesc(module_path: TestModulePath, kind: TdkUnion, members: @[BUILTIN_TYPE_NIL_ID, 9999'i32]))

    check not nil_admitted_by_type_id(malformed_option_id, descs)
    check not nil_admitted_by_type_id(arityless_option_id, descs)
    check not nil_admitted_by_type_id(malformed_union_id, descs)

  test "strict validation rejects implicit nil and reports stable diagnostics":
    let descs = builtin_type_descs()
    expect_strict_nil_mismatch(BUILTIN_TYPE_INT_ID, descs, "argument x")

  test "strict validation admits nil for explicit nil-capable descriptors":
    var descs = builtin_type_descs()
    let option_int_id = intern_type_desc(descs,
      TypeDesc(module_path: TestModulePath, kind: TdkApplied, ctor: "Option", args: @[BUILTIN_TYPE_INT_ID]))
    let int_or_nil_id = intern_type_desc(descs,
      TypeDesc(module_path: TestModulePath, kind: TdkUnion, members: @[BUILTIN_TYPE_INT_ID, BUILTIN_TYPE_NIL_ID]))

    expect_strict_nil_admitted(BUILTIN_TYPE_ANY_ID, descs, "argument any")
    expect_strict_nil_admitted(BUILTIN_TYPE_NIL_ID, descs, "argument nil")
    expect_strict_nil_admitted(option_int_id, descs, "argument option")
    expect_strict_nil_admitted(int_or_nil_id, descs, "argument union")
