import unittest, strutils

import gene/types except Exception
import gene/types/runtime_types
import gene/vm

const TestModulePath = "tests/test_strict_nil_policy.nim"
const StrictNilAllowedTargets = "Any, Nil, Option[T], or unions containing Nil"

proc reset_runtime(strict_nil: bool) =
  init_app_and_vm()
  init_stdlib()
  VM.strict_nil = strict_nil

proc exec_gene(code: string, filename: string, strict_nil = false): Value =
  reset_runtime(strict_nil)
  try:
    result = VM.exec(code.strip(), filename)
  finally:
    if VM != nil:
      VM.strict_nil = false

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
    check e.msg.contains(StrictNilAllowedTargets)
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

proc expect_vm_type_mismatch(code: string, filename: string, strict_nil: bool,
                             expected_parts: openArray[string]): string =
  reset_runtime(strict_nil)
  var raised = false
  try:
    discard VM.exec(code.strip(), filename)
  except CatchableError as e:
    raised = true
    result = e.msg
    checkpoint result
    check result.contains(TYPE_DIAG_MISMATCH_CODE)
    for part in expected_parts:
      check result.contains(part)
  finally:
    if VM != nil:
      VM.strict_nil = false
  check raised

proc expect_vm_error(code: string, filename: string, expected_parts: openArray[string]): string =
  reset_runtime(false)
  var raised = false
  try:
    discard VM.exec(code.strip(), filename)
  except CatchableError as e:
    raised = true
    result = e.msg
    checkpoint result
    for part in expected_parts:
      check result.contains(part)
  finally:
    if VM != nil:
      VM.strict_nil = false
  check raised

proc expect_vm_strict_nil_mismatch(code: string, filename: string, expected_parts: openArray[string]) =
  let message = expect_vm_type_mismatch(code, filename, strict_nil = true, expected_parts)
  check message.contains("strict nil mode")
  check message.contains(StrictNilAllowedTargets)
  check message.contains("got Nil")

proc property_guard_parts(got_text = "got String"): seq[string] = @[
  TYPE_DIAG_MISMATCH_CODE,
  "expected Int",
  got_text,
  "property x",
  "phase=property",
  "producer=assignment",
  "consumer=property",
  "site=",
]

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

  test "default VM execution remains nil-compatible for typed Int arguments":
    let value = exec_gene("""
      (fn passthrough [x: Int] x)
      (passthrough nil)
    """, "strict_nil_default_arg.gene")
    check value == NIL
    check VM.strict_nil == false

  test "default VM execution remains nil-compatible for typed Int returns":
    let value = exec_gene("""
      (fn nil_return [] -> Int nil)
      (nil_return)
    """, "strict_nil_default_return.gene")
    check value == NIL
    check VM.strict_nil == false

  test "default VM execution remains nil-compatible for typed Int locals":
    let value = exec_gene("""
      (var local_value: Int nil)
      local_value
    """, "strict_nil_default_local.gene")
    check value == NIL
    check VM.strict_nil == false

  test "VM argument mismatch diagnostics include callable guard context":
    let simple_message = expect_vm_type_mismatch("""
      (fn wrong_arg [x: Int] x)
      (wrong_arg "oops")
    """, "arg_mismatch.gene", strict_nil = false, [
      "expected Int",
      "got String",
      "in x",
      "phase=argument",
      "producer=caller",
      "consumer=function",
      "site="
    ])
    check not simple_message.contains("strict nil mode")

    let regular_message = expect_vm_type_mismatch("""
      (fn wrong_arg_regular [x: Int y: Int] y)
      (wrong_arg_regular 1 "oops")
    """, "arg_mismatch_regular.gene", strict_nil = false, [
      "expected Int",
      "got String",
      "in y",
      "phase=argument",
      "producer=caller",
      "consumer=function",
      "site="
    ])
    check not regular_message.contains("strict nil mode")

  test "secondary VM argument mismatch diagnostics include callable guard context":
    let keyword_message = expect_vm_type_mismatch("""
      (fn wrong_arg_keyword [^limit: Int] limit)
      (wrong_arg_keyword ^limit "oops")
    """, "arg_mismatch_keyword.gene", strict_nil = false, [
      "expected Int",
      "got String",
      "in limit",
      "phase=argument",
      "producer=caller",
      "consumer=function",
      "site="
    ])
    check not keyword_message.contains("strict nil mode")

    let callable_method_message = expect_vm_type_mismatch("""
      (class CallableTarget
        (method call [^value: Int] value))
      (var target (new CallableTarget))
      (target ^value "oops")
    """, "arg_mismatch_callable_method.gene", strict_nil = false, [
      "expected Int",
      "got String",
      "in value",
      "phase=argument",
      "producer=caller",
      "consumer=function",
      "site="
    ])
    check not callable_method_message.contains("strict nil mode")

    let super_method_message = expect_vm_type_mismatch("""
      (class Base
        (method take [x: Int] x))
      (class Child < Base
        (method call_super [x]
          (super .take x)))
      ((new Child) .call_super "oops")
    """, "arg_mismatch_super_method.gene", strict_nil = false, [
      "expected Int",
      "got String",
      "in x",
      "phase=argument",
      "producer=caller",
      "consumer=function",
      "site="
    ])
    check not super_method_message.contains("strict nil mode")

    let block_message = expect_vm_error("""
      (var b (block [x y] x))
      (b "oops")
    """, "arg_mismatch_block.gene", [
      "Expected 2 arguments, got 1"
    ])
    check not block_message.contains("phase=argument")
    check not block_message.contains("producer=caller")
    check not block_message.contains("consumer=function")

  test "VM return mismatch diagnostics include callable guard context":
    let message = expect_vm_type_mismatch("""
      (fn wrong_return [] -> Int "oops")
      (wrong_return)
    """, "return_mismatch.gene", strict_nil = false, [
      "expected Int",
      "got String",
      "return value of wrong_return",
      "phase=return",
      "producer=callee",
      "consumer=caller",
      "site="
    ])
    check not message.contains("strict nil mode")

  test "VM local mismatch diagnostics include local guard context":
    let declaration_message = expect_vm_type_mismatch("""
      (var local_value: Int "oops")
    """, "local_declaration_mismatch.gene", strict_nil = false, [
      "expected Int",
      "got String",
      "in variable",
      "phase=local",
      "producer=assignment",
      "consumer=local",
      "site="
    ])
    check not declaration_message.contains("strict nil mode")

    let assignment_message = expect_vm_type_mismatch("""
      (fn assign_bad []
        (var local_value: Int 1)
        (local_value = "oops"))
      (assign_bad)
    """, "local_assignment_mismatch.gene", strict_nil = false, [
      "expected Int",
      "got String",
      "in variable",
      "phase=local",
      "producer=assignment",
      "consumer=local",
      "site="
    ])
    check not assignment_message.contains("strict nil mode")

  test "VM property mismatch diagnostics include property guard context":
    let direct_message = expect_vm_type_mismatch("""
      (class GuardedPoint
        (field x: Int)
        (ctor [] (/x = 1)))
      (var point (new GuardedPoint))
      (point/x = "oops")
    """, "property_direct_mismatch.gene", strict_nil = false, property_guard_parts())
    check not direct_message.contains("strict nil mode")

    let dynamic_message = expect_vm_type_mismatch("""
      (class GuardedPoint
        (field x: Int)
        (ctor [] (/x = 1)))
      (fn property_name [] "x")
      (var point (new GuardedPoint))
      ($set point (@ (property_name)) "oops")
    """, "property_dynamic_mismatch.gene", strict_nil = false, property_guard_parts())
    check not dynamic_message.contains("strict nil mode")

  test "default VM execution remains nil-compatible for typed properties":
    let value = exec_gene("""
      (class DefaultNilPoint
        (field x: Int)
        (ctor [] (/x = 1)))
      (var point (new DefaultNilPoint))
      (point/x = nil)
      point/x
    """, "strict_nil_default_property.gene")
    check value == NIL
    check VM.strict_nil == false

  test "property parameter shorthand guards values and stores coerced values":
    let coerced = exec_gene("""
      (class Metric
        (field x: Float)
        (ctor [/x] nil))
      (var metric (new Metric ^x 3))
      metric/x
    """, "property_param_coercion.gene")
    check coerced.kind == VkFloat
    check coerced.float == 3.0

    let message = expect_vm_type_mismatch("""
      (class GuardedPropertyParam
        (field x: Int)
        (ctor [/x] nil))
      (new GuardedPropertyParam ^x "oops")
    """, "property_param_mismatch.gene", strict_nil = false, property_guard_parts())
    check not message.contains("strict nil mode")

  test "strict VM execution rejects nil at representative typed boundaries":
    expect_vm_strict_nil_mismatch("""
      (fn strict_arg [x: Int] x)
      (strict_arg nil)
    """, "strict_nil_arg.gene", [
      "expected Int",
      "in x",
      "strict_nil_arg.gene",
      "phase=argument",
      "producer=caller",
      "consumer=function",
      "site="
    ])

    expect_vm_strict_nil_mismatch("""
      (fn strict_return [] -> Int nil)
      (strict_return)
    """, "strict_nil_return.gene", [
      "expected Int",
      "return value of strict_return",
      "phase=return",
      "producer=callee",
      "consumer=caller",
      "site="
    ])

    let local_message = expect_vm_type_mismatch("""
      (var local_value: Int nil)
    """, "strict_nil_local.gene", strict_nil = true, [
      "expected Int",
      "in variable",
      "strict_nil_local.gene",
      "phase=local",
      "producer=assignment",
      "consumer=local",
      "site="
    ])
    check local_message.contains("strict nil mode")
    check local_message.contains(StrictNilAllowedTargets)
    check local_message.contains("got Nil")
    check not local_message.contains("phase=argument")

    expect_vm_strict_nil_mismatch("""
      (class StrictNilPoint
        (field x: Int)
        (ctor [] (/x = 1)))
      (var point (new StrictNilPoint))
      (point/x = nil)
    """, "strict_nil_property.gene", [
      "expected Int",
      "property x",
      "strict_nil_property.gene",
      "phase=property",
      "producer=assignment",
      "consumer=property",
      "site="
    ])

  test "strict VM execution admits nil through compiled Any Nil Option and union descriptors":
    let value = exec_gene("""
      (fn accepts_any [x: Any] "any-admitted")
      (fn accepts_nil [x: Nil] "nil-admitted")
      (fn accepts_option [x: (Option Int)] "option-admitted")
      (type MaybeInt (Int | Nil))
      (fn accepts_union [x: MaybeInt] "union-admitted")
      [(accepts_any nil) (accepts_nil nil) (accepts_option nil) (accepts_union nil)]
    """, "strict_nil_admitted_compiled_metadata.gene", strict_nil = true)

    check value.kind == VkArray
    let items = array_data(value)
    check items.len == 4
    check items[0].kind == VkString
    check items[0].str == "any-admitted"
    check items[1].kind == VkString
    check items[1].str == "nil-admitted"
    check items[2].kind == VkString
    check items[2].str == "option-admitted"
    check items[3].kind == VkString
    check items[3].str == "union-admitted"
    check VM.strict_nil == false
