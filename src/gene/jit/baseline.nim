{.push warning[UnreachableCode]: off.}
import ../types
import ../types/type_defs
import ../types/value_core
import ../vm/utils
import ./memory

when defined(amd64):
  import ./x64/asm_helpers
  import ./x64/encoders
when defined(arm64):
  import ./arm64/asm_helpers
  import ./arm64/encoders

  # Struct layout and NaN-boxing constants for inline arm64 codegen.
  const
    OFF_VM_FRAME = offsetof(VirtualMachine, frame).uint16
    OFF_FRAME_STACK = offsetof(FrameObj, stack).uint16
    OFF_FRAME_STACK_INDEX = offsetof(FrameObj, stack_index).uint16
    VAL_SMALL_INT_TAG = SMALL_INT_TAG
    VAL_PAYLOAD_MASK = PAYLOAD_MASK
    VAL_TAG_MASK = (not PAYLOAD_MASK)
    VAL_TRUE = TRUE
    VAL_FALSE = FALSE

proc jit_interpreter_trampoline(vm: VirtualMachine, fn_value: Value, args: ptr UncheckedArray[Value], arg_count: int): Value {.cdecl, importc.}

when defined(amd64):
  proc compile_function_x64*(vm: VirtualMachine, fn: Function): JitCompiled =
    ## amd64 baseline JIT: emits helper calls that operate on the VM frame stack.
    when not (defined(amd64) and defined(geneJit)):
      return nil

    if fn.body_compiled.is_nil:
      return nil

    template emit_helper_call(buf: var AsmBuffer, target: pointer) =
      buf.code.emit_mov_rax_imm64(cast[uint64](target))
      buf.code.emit_call_rax()

    var buf = init_asm()
    var has_return = false

    for idx, inst in fn.body_compiled.instructions:
      buf.mark_label(idx)
      case inst.kind
      of IkStart:
        discard
      of IkGeneStartDefault, IkGeneStart, IkGeneSetType, IkGeneAddChild, IkTailCall, IkGeneEnd:
        # Complex gene/tail-call handling not supported by the baseline JIT yet.
        return nil
      of IkPushValue:
        buf.code.emit_mov_rsi_imm64(cast[uint64](inst.arg0))
        buf.emit_helper_call(cast[pointer](jit_stack_push_value))
      of IkAdd:
        buf.emit_helper_call(cast[pointer](jit_add_ints))
      of IkSub:
        buf.emit_helper_call(cast[pointer](jit_sub_ints))
      of IkDup:
        buf.emit_helper_call(cast[pointer](jit_stack_dup))
      of IkSwap:
        buf.emit_helper_call(cast[pointer](jit_stack_swap))
      of IkPop:
        buf.emit_helper_call(cast[pointer](jit_stack_pop_discard))
      of IkScopeStart, IkScopeEnd:
        if inst.kind == IkScopeStart:
          buf.code.emit_mov_rsi_imm64(cast[uint64](inst.arg0))
          buf.emit_helper_call(cast[pointer](jit_scope_start))
        else:
          buf.emit_helper_call(cast[pointer](jit_scope_end))
      of IkJumpIfMatchSuccess:
        let idx = inst.arg0.int64.int
        if idx < int32.low or idx > int32.high:
          return nil
        buf.code.emit_mov_reg_imm32(6, idx.int32) # rsi
        buf.emit_helper_call(cast[pointer](jit_jump_if_match_success))
        buf.code.emit_test_al_al()
        buf.code.emit([0x0F'u8, 0x85'u8]) # jne rel32
        buf.add_patch(inst.arg1.int64.int, "jne")
      of IkResolveSymbol:
        buf.code.emit_mov_rsi_imm64(cast[uint64](inst.arg0))
        buf.emit_helper_call(cast[pointer](jit_resolve_symbol))
      of IkVarResolve:
        let slot = inst.arg0.int64.int
        if slot < int32.low or slot > int32.high:
          return nil
        buf.code.emit_mov_reg_imm32(6, slot.int32) # rsi
        buf.emit_helper_call(cast[pointer](jit_var_resolve_push))
      of IkVarAssign:
        let slot = inst.arg0.int64.int
        if slot < int32.low or slot > int32.high:
          return nil
        buf.code.emit_mov_reg_imm32(6, slot.int32) # rsi
        buf.emit_helper_call(cast[pointer](jit_var_assign_top))
      of IkVarLtValue, IkVarLeValue, IkVarGtValue, IkVarGeValue, IkVarEqValue, IkVarSubValue:
        let slot = inst.arg0.int64.int
        let parent_depth = inst.arg1.int64.int
        if slot < int32.low or slot > int32.high:
          return nil
        if parent_depth < int32.low or parent_depth > int32.high:
          return nil
        if idx + 1 >= fn.body_compiled.instructions.len:
          return nil
        let literal_inst = fn.body_compiled.instructions[idx + 1]
        let literal_value = literal_inst.arg0
        buf.code.emit_mov_reg_imm32(6, slot.int32) # rsi = slot
        buf.code.emit_mov_reg_imm32(2, parent_depth.int32) # rdx = parent depth
        buf.code.emit_mov_rcx_imm64(cast[uint64](literal_value)) # rcx = literal
        case inst.kind
        of IkVarLtValue:
          buf.emit_helper_call(cast[pointer](jit_var_lt_value))
        of IkVarLeValue:
          buf.emit_helper_call(cast[pointer](jit_var_le_value))
        of IkVarGtValue:
          buf.emit_helper_call(cast[pointer](jit_var_gt_value))
        of IkVarGeValue:
          buf.emit_helper_call(cast[pointer](jit_var_ge_value))
        of IkVarEqValue:
          buf.emit_helper_call(cast[pointer](jit_var_eq_value))
        else:
          buf.emit_helper_call(cast[pointer](jit_var_sub_value))
      of IkLt:
        buf.emit_helper_call(cast[pointer](jit_compare_lt))
      of IkLe:
        buf.emit_helper_call(cast[pointer](jit_compare_le))
      of IkGt:
        buf.emit_helper_call(cast[pointer](jit_compare_gt))
      of IkGe:
        buf.emit_helper_call(cast[pointer](jit_compare_ge))
      of IkEq:
        buf.emit_helper_call(cast[pointer](jit_compare_eq))
      of IkData:
        discard
      of IkJump:
        let target = inst.arg0.int64.int
        if target < 0 or target >= fn.body_compiled.instructions.len:
          return nil
        buf.code.emit([0xE9'u8]) # jmp rel32
        buf.add_patch(target, "jmp")
      of IkJumpIfFalse:
        let target = inst.arg0.int64.int
        if target < 0 or target >= fn.body_compiled.instructions.len:
          return nil
        buf.emit_helper_call(cast[pointer](jit_pop_is_false))
        buf.code.emit_test_al_al()
        buf.code.emit([0x0F'u8, 0x85'u8]) # jne rel32
        buf.add_patch(target, "jne")
      of IkReturn:
        buf.emit_helper_call(cast[pointer](jit_stack_pop_value))
        buf.code.emit_ret()
        has_return = true
      of IkEnd:
        buf.emit_helper_call(cast[pointer](jit_stack_pop_value))
        buf.code.emit_ret()
        has_return = true
      of IkThrow:
        buf.emit_helper_call(cast[pointer](jit_throw))
      of IkUnifiedCall0:
        buf.emit_helper_call(cast[pointer](jit_unified_call0))
      of IkUnifiedCall1:
        buf.emit_helper_call(cast[pointer](jit_unified_call1))
      of IkUnifiedCall:
        let arg_count = inst.arg1.int64.int
        if arg_count < int32.low or arg_count > int32.high:
          return nil
        buf.code.emit_mov_reg_imm32(6, arg_count.int32) # rsi = arg_count
        buf.emit_helper_call(cast[pointer](jit_unified_call))
      else:
        when defined(geneJitDebug):
          echo "x64 jit unsupported ", inst.kind
        return nil

    if not has_return:
      buf.emit_helper_call(cast[pointer](jit_stack_pop_value))
      buf.code.emit_ret()

    buf.patch_labels()
    let mem = allocate_executable_memory(buf.code.len)
    copyMem(mem, buf.code[0].unsafeAddr, buf.code.len)
    make_executable(mem, buf.code.len)

    JitCompiled(
      entry: cast[JittedFn](mem),
      code: mem,
      size: buf.code.len,
      bytecode_version: cast[uint64](fn.body_compiled.id),
      bytecode_len: fn.body_compiled.instructions.len,
      built_for_arch: "x86_64",
      uses_vm_stack: true
    )

when defined(arm64):
  proc compile_function_arm64*(vm: VirtualMachine, fn: Function): JitCompiled =
    ## arm64 baseline JIT with small-int inline ops; var ops use slot-pointer helper.
    when not (defined(arm64) and defined(geneJit)):
      return nil

    if fn.body_compiled.is_nil:
      return nil

    var buf = init_asm()
    var has_return = false
    var label_counter: int = if fn.body_compiled != nil: fn.body_compiled.instructions.len + 100 else: 100

    # Prologue: save VM pointer and return address.
    buf.code.emit_sub_sp_imm(16)
    buf.code.emit_str_sp_imm(0, 0)   # save vm (x0)
    buf.code.emit_str_sp_imm(30, 8)  # save lr

    template call_helper(target: pointer) =
      buf.code.emit_ldr_sp_imm(0, 0)
      buf.emit_helper_call(target)

    template load_frame(dest: uint8) =
      buf.code.emit_ldr_sp_imm(dest, 0)
      buf.code.emit_ldr_reg_imm(dest, dest, OFF_VM_FRAME)

    template load_stack_base(dest: uint8) =
      load_frame(dest)
      buf.code.emit_add_reg_imm(dest, dest, OFF_FRAME_STACK)

    template load_stack_index(dest: uint8) =
      load_frame(dest)
      buf.code.emit_ldrh_reg_imm(dest, dest, OFF_FRAME_STACK_INDEX)

    template store_stack_index(src: uint8) =
      load_frame(17)
      buf.code.emit_strh_reg_imm(src, 17, OFF_FRAME_STACK_INDEX)

    template push_literal(lit: Value) =
      load_stack_base(1)
      load_stack_index(2)
      buf.code.emit_mov_reg_imm64(3, cast[uint64](lit))
      buf.code.emit_add_reg_reg_lsl(4, 1, 2, 3) # addr = base + idx*8
      buf.code.emit_str_reg_imm(3, 4, 0)
      buf.code.emit_add_reg_imm(2, 2, 1)
      store_stack_index(2)

    template pop(dest: uint8) =
      load_stack_base(1)
      load_stack_index(2)
      buf.code.emit_sub_reg_imm(2, 2, 1)
      store_stack_index(2)
      buf.code.emit_add_reg_reg_lsl(3, 1, 2, 3)
      buf.code.emit_ldr_reg_imm(dest, 3, 0)

    template peek(dest: uint8) =
      load_stack_base(1)
      load_stack_index(2)
      buf.code.emit_sub_reg_imm(3, 2, 1)
      buf.code.emit_add_reg_reg_lsl(4, 1, 3, 3)
      buf.code.emit_ldr_reg_imm(dest, 4, 0)

    template push_reg(src: uint8) =
      load_stack_base(1)
      load_stack_index(2)
      buf.code.emit_add_reg_reg_lsl(3, 1, 2, 3)
      buf.code.emit_str_reg_imm(src, 3, 0)
      buf.code.emit_add_reg_imm(2, 2, 1)
      store_stack_index(2)

    template smallint_payload(dest: uint8, src: uint8) =
      buf.code.emit_mov_reg_imm64(dest, VAL_PAYLOAD_MASK)
      buf.code.emit_and_reg_reg(dest, dest, src)

    template box_smallint(dest: uint8, src: uint8) =
      buf.code.emit_mov_reg_imm64(dest, VAL_SMALL_INT_TAG)
      buf.code.emit_orr_reg_reg(dest, dest, src)

    template ensure_smallint_or_branch(val_reg: uint8, tmp: uint8, slow_label: int) =
      buf.code.emit_mov_reg_imm64(tmp, VAL_TAG_MASK)
      buf.code.emit_and_reg_reg(tmp, tmp, val_reg)
      buf.code.emit_mov_reg_imm64(15, VAL_SMALL_INT_TAG)
      buf.code.emit_cmp_reg_reg(tmp, 15)
      buf.add_patch(slow_label, "cbnz")

    proc next_lbl(): int =
      label_counter.inc
      label_counter - 1

    template snapshot_stack_index(dest: uint8) =
      load_stack_index(dest)

    template restore_stack_index(src: uint8) =
      store_stack_index(src)

    when defined(geneJitDebug):
      if fn.name.len > 0:
        echo "JIT arm64 compiling ", fn.name, " (", fn.body_compiled.instructions.len, " insts)"
        for i, ins in fn.body_compiled.instructions:
          echo "  ", i, ": ", ins.kind, " arg0=", ins.arg0, " arg1=", ins.arg1

    for idx, inst in fn.body_compiled.instructions:
      buf.mark_label(idx)
      case inst.kind
      of IkStart:
        discard
      of IkGeneStartDefault, IkGeneStart, IkGeneSetType, IkGeneAddChild, IkTailCall, IkGeneEnd:
        return nil
      of IkPushValue:
        buf.code.emit_mov_reg_imm64(1, cast[uint64](inst.arg0))
        call_helper(cast[pointer](jit_stack_push_value))
      of IkAdd:
        let slow_add = next_lbl()
        let done_add = next_lbl()
        # Pop operands (rhs, lhs)
        pop(3)
        pop(4)
        ensure_smallint_or_branch(3, 5, slow_add)
        ensure_smallint_or_branch(4, 6, slow_add)
        smallint_payload(7, 3)
        smallint_payload(8, 4)
        buf.code.emit_add_reg_reg(9, 7, 8)
        box_smallint(10, 9)
        push_reg(10)
        buf.add_patch(done_add, "b")
        buf.mark_label(slow_add)
        # Slow path: restore operands then call helper
        push_reg(4) # lhs
        push_reg(3) # rhs
        call_helper(cast[pointer](jit_add_ints))
        buf.mark_label(done_add)
      of IkSub:
        let slow_sub = next_lbl()
        let done_sub = next_lbl()
        pop(3)
        pop(4)
        ensure_smallint_or_branch(3, 5, slow_sub)
        ensure_smallint_or_branch(4, 6, slow_sub)
        smallint_payload(7, 3)
        smallint_payload(8, 4)
        buf.code.emit_sub_reg_reg(9, 8, 7) # lhs - rhs
        box_smallint(10, 9)
        push_reg(10)
        buf.add_patch(done_sub, "b")
        buf.mark_label(slow_sub)
        push_reg(4)
        push_reg(3)
        call_helper(cast[pointer](jit_sub_ints))
        buf.mark_label(done_sub)
      of IkDup:
        call_helper(cast[pointer](jit_stack_dup))
      of IkSwap:
        call_helper(cast[pointer](jit_stack_swap))
      of IkPop:
        call_helper(cast[pointer](jit_stack_pop_discard))
      of IkScopeStart, IkScopeEnd:
        if inst.kind == IkScopeStart:
          buf.code.emit_mov_reg_imm64(1, cast[uint64](inst.arg0))
          call_helper(cast[pointer](jit_scope_start))
        else:
          call_helper(cast[pointer](jit_scope_end))
      of IkJumpIfMatchSuccess:
        let idx = inst.arg0.int64.int
        if idx < int32.low or idx > int32.high:
          return nil
        buf.code.emit_mov_reg_imm64(1, cast[uint64](idx))
        call_helper(cast[pointer](jit_jump_if_match_success))
        buf.add_patch(inst.arg1.int64.int, "cbnz")
      of IkResolveSymbol:
        buf.code.emit_mov_reg_imm64(1, cast[uint64](inst.arg0))
        call_helper(cast[pointer](jit_resolve_symbol))
      of IkVarResolve:
        let slot = inst.arg0.int64.int
        if slot < int32.low or slot > int32.high:
          return nil
        buf.code.emit_mov_reg_imm64(1, cast[uint64](slot))
        call_helper(cast[pointer](jit_var_resolve_push))
      of IkVarAssign:
        let slot = inst.arg0.int64.int
        if slot < int32.low or slot > int32.high:
          return nil
        buf.code.emit_mov_reg_imm64(1, cast[uint64](slot))
        call_helper(cast[pointer](jit_var_assign_top))
      of IkVarLtValue, IkVarLeValue, IkVarGtValue, IkVarGeValue, IkVarEqValue, IkVarSubValue:
        let slot = inst.arg0.int64.int
        let parent_depth = inst.arg1.int64.int
        if slot < int32.low or slot > int32.high:
          return nil
        if parent_depth < int32.low or parent_depth > int32.high:
          return nil
        if idx + 1 >= fn.body_compiled.instructions.len:
          return nil
        let literal_inst = fn.body_compiled.instructions[idx + 1]
        let literal_value = literal_inst.arg0
        buf.code.emit_mov_reg_imm64(1, cast[uint64](slot))
        buf.code.emit_mov_reg_imm64(2, cast[uint64](parent_depth))
        buf.code.emit_mov_reg_imm64(3, cast[uint64](literal_value))
        case inst.kind
        of IkVarLtValue:
          call_helper(cast[pointer](jit_var_lt_value))
        of IkVarLeValue:
          call_helper(cast[pointer](jit_var_le_value))
        of IkVarGtValue:
          call_helper(cast[pointer](jit_var_gt_value))
        of IkVarGeValue:
          call_helper(cast[pointer](jit_var_ge_value))
        of IkVarEqValue:
          call_helper(cast[pointer](jit_var_eq_value))
        else:
          call_helper(cast[pointer](jit_var_sub_value))
      of IkLt:
        call_helper(cast[pointer](jit_compare_lt))
      of IkLe:
        call_helper(cast[pointer](jit_compare_le))
      of IkGt:
        call_helper(cast[pointer](jit_compare_gt))
      of IkGe:
        call_helper(cast[pointer](jit_compare_ge))
      of IkEq:
        call_helper(cast[pointer](jit_compare_eq))
      of IkData:
        discard
      of IkJump:
        let target = inst.arg0.int64.int
        if target < 0 or target >= fn.body_compiled.instructions.len:
          return nil
        buf.add_patch(target, "b")
      of IkJumpIfFalse:
        let target = inst.arg0.int64.int
        if target < 0 or target >= fn.body_compiled.instructions.len:
          return nil
        call_helper(cast[pointer](jit_pop_is_false))
        buf.add_patch(target, "cbnz")
      of IkReturn:
        call_helper(cast[pointer](jit_stack_pop_value))
        buf.code.emit_ldr_sp_imm(30, 8)
        buf.code.emit_add_sp_imm(16)
        buf.emit_ret()
        has_return = true
      of IkEnd:
        call_helper(cast[pointer](jit_stack_pop_value))
        buf.code.emit_ldr_sp_imm(30, 8)
        buf.code.emit_add_sp_imm(16)
        buf.emit_ret()
        has_return = true
      of IkThrow:
        call_helper(cast[pointer](jit_throw))
      of IkUnifiedCall0:
        call_helper(cast[pointer](jit_unified_call0))
      of IkUnifiedCall1:
        call_helper(cast[pointer](jit_unified_call1))
      of IkUnifiedCall:
        let arg_count = inst.arg1.int64.int
        if arg_count < int32.low or arg_count > int32.high:
          return nil
        buf.code.emit_mov_reg_imm64(1, cast[uint64](arg_count))
        call_helper(cast[pointer](jit_unified_call))
      else:
        when defined(geneJitDebug):
          echo "arm64 jit unsupported ", inst.kind, " at ", idx
        return nil

    if not has_return:
      call_helper(cast[pointer](jit_stack_pop_value))
      buf.code.emit_ldr_sp_imm(30, 8)
      buf.code.emit_add_sp_imm(16)
      buf.emit_ret()

    buf.patch_labels()
    if buf.code.len == 0:
      return nil
    let code_size = buf.code.len * sizeof(uint32)
    let mem = allocate_executable_memory(code_size)
    copyMem(mem, buf.code[0].unsafeAddr, code_size)
    make_executable(mem, code_size)

    JitCompiled(
      entry: cast[JittedFn](mem),
      code: mem,
      size: code_size,
      bytecode_version: cast[uint64](fn.body_compiled.id),
      bytecode_len: fn.body_compiled.instructions.len,
      built_for_arch: "arm64",
      uses_vm_stack: true
    )

{.pop.}
