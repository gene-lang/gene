import tables
import ../types
import ../types/type_defs
import ../types/value_core
import ../vm/utils
import ./memory
import ./x64/asm_helpers
import ./x64/encoders

proc jit_interpreter_trampoline(vm: VirtualMachine, fn_value: Value, args: ptr UncheckedArray[Value], arg_count: int): Value {.cdecl, importc.}

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
