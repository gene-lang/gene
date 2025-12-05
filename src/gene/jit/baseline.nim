import tables
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
      of IkGeneStartDefault:
        buf.emit_helper_call(cast[pointer](jit_gene_start_default))
        let target = inst.arg0.int64.int
        if target < 0 or target >= fn.body_compiled.instructions.len:
          return nil
        buf.code.emit([0xE9'u8]) # jmp rel32
        buf.add_patch(target, "jmp")
      of IkGeneStart:
        buf.emit_helper_call(cast[pointer](jit_gene_start))
      of IkGeneSetType:
        buf.emit_helper_call(cast[pointer](jit_gene_set_type))
      of IkGeneAddChild:
        buf.emit_helper_call(cast[pointer](jit_gene_add_child))
      of IkTailCall:
        buf.emit_helper_call(cast[pointer](jit_tail_call))
      of IkGeneEnd:
        buf.emit_helper_call(cast[pointer](jit_gene_end))
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
      else:
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
    ## arm64 baseline JIT: emits helper calls that operate on the VM frame stack.
    when not (defined(arm64) and defined(geneJit)):
      return nil

    if fn.body_compiled.is_nil:
      return nil

    when defined(geneJitArm64Native):
      var buf = init_asm()
      var has_return = false

      # Prologue: save VM pointer and return address.
      buf.code.emit_sub_sp_imm(16)
      buf.code.emit_str_sp_imm(0, 0)   # save vm (x0)
      buf.code.emit_str_sp_imm(30, 8)  # save lr

      template call_helper(target: pointer) =
        buf.code.emit_ldr_sp_imm(0, 0)
        buf.emit_helper_call(target)

      for idx, inst in fn.body_compiled.instructions:
        buf.mark_label(idx)
        case inst.kind
        of IkStart:
          discard
        of IkPushValue:
          buf.emit_mov_reg_imm64(1, cast[uint64](inst.arg0))
          call_helper(cast[pointer](jit_stack_push_value))
        of IkAdd:
          call_helper(cast[pointer](jit_add_ints))
        of IkSub:
          call_helper(cast[pointer](jit_sub_ints))
        of IkDup:
          call_helper(cast[pointer](jit_stack_dup))
        of IkSwap:
          call_helper(cast[pointer](jit_stack_swap))
        of IkPop:
          call_helper(cast[pointer](jit_stack_pop_discard))
        of IkJumpIfMatchSuccess:
          let idx = inst.arg0.int64.int
          if idx < int32.low or idx > int32.high:
            return nil
          buf.emit_mov_reg_imm64(1, cast[uint64](idx))
          call_helper(cast[pointer](jit_jump_if_match_success))
          buf.add_patch(inst.arg1.int64.int, "cbnz")
        of IkResolveSymbol:
          buf.emit_mov_reg_imm64(1, cast[uint64](inst.arg0))
          call_helper(cast[pointer](jit_resolve_symbol))
        of IkVarResolve:
          let slot = inst.arg0.int64.int
          if slot < int32.low or slot > int32.high:
            return nil
          buf.emit_mov_reg_imm64(1, cast[uint64](slot))
          call_helper(cast[pointer](jit_var_resolve_push))
        of IkVarAssign:
          let slot = inst.arg0.int64.int
          if slot < int32.low or slot > int32.high:
            return nil
          buf.emit_mov_reg_imm64(1, cast[uint64](slot))
          call_helper(cast[pointer](jit_var_assign_top))
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
        of IkGeneStartDefault:
          call_helper(cast[pointer](jit_gene_start_default))
          let target = inst.arg0.int64.int
          if target < 0 or target >= fn.body_compiled.instructions.len:
            return nil
          buf.add_patch(target, "b")
        of IkGeneStart:
          call_helper(cast[pointer](jit_gene_start))
        of IkGeneSetType:
          call_helper(cast[pointer](jit_gene_set_type))
        of IkGeneAddChild:
          call_helper(cast[pointer](jit_gene_add_child))
        of IkTailCall:
          call_helper(cast[pointer](jit_tail_call))
        of IkGeneEnd:
          call_helper(cast[pointer](jit_gene_end))
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
        else:
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
    else:
      # Safe fallback: call interpreter trampoline when native arm64 JIT is disabled.
      JitCompiled(
        entry: jit_interpreter_trampoline,
        code: nil,
        size: 0,
        bytecode_version: cast[uint64](fn.body_compiled.id),
        bytecode_len: fn.body_compiled.instructions.len,
        built_for_arch: "arm64",
        uses_vm_stack: false
      )
