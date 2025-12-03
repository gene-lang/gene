import unittest

import ../src/gene/types except Exception
import ../src/gene/types/value_core except Exception
import ../src/gene/types/instructions
import ../src/gene/jit/config
import ../src/gene/vm
import ./helpers

proc build_fn(name: string, instructions: seq[Instruction], parent_scope: Scope = nil): (Function, Value) =
  var fn = Function(
    name: name,
    ns: new_namespace("jit_test"),
    scope_tracker: new_scope_tracker(),
    parent_scope: parent_scope,
    matcher: new_arg_matcher(),
    body: @[]
  )
  var cu = new_compilation_unit()
  for inst in instructions:
    cu.instructions.add(inst)
  cu.matcher = fn.matcher
  cu.kind = CkFunction
  fn.body_compiled = cu

  let fn_ref = new_ref(VkFunction)
  fn_ref.fn = fn
  (fn, fn_ref.to_ref_value())

proc reset_vm_state() =
  VM.jit = init_jit_state()
  VM.frame = nil
  VM.cu = nil
  VM.pc = 0

suite "Baseline JIT uses VM stack":
  setup:
    init_all()
    reset_vm_state()

  test "dup/swap/pop path matches interpreter":
    let instructions = @[
      Instruction(kind: IkStart),
      Instruction(kind: IkPushValue, arg0: 1.to_value()),
      Instruction(kind: IkDup),
      Instruction(kind: IkPushValue, arg0: 2.to_value()),
      Instruction(kind: IkSwap),
      Instruction(kind: IkPop),
      Instruction(kind: IkEnd)
    ]
    var (f, fn_val) = build_fn("stack_ops", instructions)

    # Interpreter reference
    VM.jit.enabled = false
    let interp_res = VM.exec_function(fn_val, @[])
    check interp_res.int64 == 2

    # JIT path
    when defined(geneJit) and defined(amd64):
      reset_vm_state()
      VM.jit.enabled = true
      VM.jit.hot_threshold = 0
      VM.jit.very_hot_threshold = 0
      let caller = new_frame()
      VM.frame = caller
      VM.jit_track_call(f)
      check VM.maybe_call_jit_function(fn_val, nil, 0, false)
      let jit_res = caller.pop()
      caller.free()
      VM.frame = nil
      check jit_res.int64 == 2
      check f.jit_compiled != nil and f.jit_compiled.uses_vm_stack

  test "VarResolve/Assign keeps scope consistent":
    let var_instructions = @[
      Instruction(kind: IkStart),
      Instruction(kind: IkVarResolve, arg0: 0.to_value()),
      Instruction(kind: IkVarResolve, arg0: 1.to_value()),
      Instruction(kind: IkAdd),
      Instruction(kind: IkVarAssign, arg0: 0.to_value()),
      Instruction(kind: IkEnd)
    ]

    # Interpreter reference
    var scope_interp = new_scope(new_scope_tracker())
    scope_interp.members.add(3.to_value())
    scope_interp.members.add(5.to_value())
    var (f_interp, fn_val_interp) = build_fn("var_interp", var_instructions, scope_interp)
    VM.jit.enabled = false
    let interp_res = VM.exec_function(fn_val_interp, @[])
    check interp_res.int64 == 8
    check scope_interp.members[0].int64 == 8
    scope_interp.free()

    # JIT path
    when defined(geneJit) and defined(amd64):
      var scope_jit = new_scope(new_scope_tracker())
      scope_jit.members.add(3.to_value())
      scope_jit.members.add(5.to_value())
      var (f_jit, fn_val_jit) = build_fn("var_jit", var_instructions, scope_jit)
      reset_vm_state()
      VM.jit.enabled = true
      VM.jit.hot_threshold = 0
      VM.jit.very_hot_threshold = 0
      let caller = new_frame()
      VM.frame = caller
      VM.jit_track_call(f_jit)
      check VM.maybe_call_jit_function(fn_val_jit, nil, 0, false)
      let jit_res = caller.pop()
      caller.free()
      VM.frame = nil
      check jit_res.int64 == 8
      check scope_jit.members[0].int64 == 8
      check f_jit.jit_compiled != nil and f_jit.jit_compiled.uses_vm_stack
      scope_jit.free()

  test "comparisons and jumps agree with interpreter":
    let jump_target_else = 7
    let jump_target_end = 8
    let branch_instructions = @[
      Instruction(kind: IkStart),
      Instruction(kind: IkPushValue, arg0: 1.to_value()),
      Instruction(kind: IkPushValue, arg0: 2.to_value()),
      Instruction(kind: IkLt),
      Instruction(kind: IkJumpIfFalse, arg0: jump_target_else.to_value()),
      Instruction(kind: IkPushValue, arg0: 10.to_value()),
      Instruction(kind: IkJump, arg0: jump_target_end.to_value()),
      Instruction(kind: IkPushValue, arg0: 0.to_value()),
      Instruction(kind: IkEnd)
    ]

    var (f_branch, fn_val_branch) = build_fn("branch_interp", branch_instructions)
    VM.jit.enabled = false
    let interp_res = VM.exec_function(fn_val_branch, @[])
    check interp_res.int64 == 10

    when defined(geneJit) and defined(amd64):
      reset_vm_state()
      VM.jit.enabled = true
      VM.jit.hot_threshold = 0
      VM.jit.very_hot_threshold = 0
      let caller = new_frame()
      VM.frame = caller
      VM.jit_track_call(f_branch)
      check VM.maybe_call_jit_function(fn_val_branch, nil, 0, false)
      let jit_res = caller.pop()
      caller.free()
      VM.frame = nil
      check jit_res.int64 == 10
      check f_branch.jit_compiled != nil and f_branch.jit_compiled.uses_vm_stack
