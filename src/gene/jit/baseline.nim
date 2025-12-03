import tables
import ../types
import ../types/type_defs
import ../types/value_core
import ./memory
import ./x64/asm
import ./x64/encoders

proc jit_interpreter_trampoline(vm: VirtualMachine, fn_value: Value, args: ptr UncheckedArray[Value], arg_count: int): Value {.cdecl, importc.}

proc compile_function_x64*(vm: VirtualMachine, fn: Function): JitCompiled =
  ## Minimal amd64 baseline: supports small-int push/add/return using a local eval stack.
  when not (defined(amd64) and defined(geneJit)):
    return nil

  if fn.body_compiled.is_nil:
    return nil

  var buf = init_asm()
  # Simple evaluation stack on machine stack; emit code per instruction.
  for inst in fn.body_compiled.instructions:
    case inst.kind
    of IkPushValue:
      if inst.arg0.kind != VkInt:
        return nil
      let v = inst.arg0.to_int()
      if v < int32.low or v > int32.high:
        return nil
      buf.code.emit_mov_rax_imm64(cast[uint64](v.to_value()))
      buf.code.emit_push_rax()
    of IkAdd:
      # Pop rhs into rbx (Value), unbox -> rbx=int
      buf.code.emit_pop_rbx()
      buf.code.emit_shl_rbx_imm8(16)  # sign-extend payload: shl; sar
      buf.code.emit_sar_rbx_imm8(16)
      # Pop lhs into rax (Value), unbox -> rax=int
      buf.code.emit_pop_rax()
      buf.code.emit_shl_rax_imm8(16)
      buf.code.emit_sar_rax_imm8(16)
      # Add ints
      buf.code.emit_add_rax_rbx()
      # Box back to Value: rax=int -> rbx=payload -> rax=tag|payload
      buf.code.emit_mov_rbx_rax()
      buf.code.emit_and_rbx_imm64(PAYLOAD_MASK)
      buf.code.emit_mov_rax_imm64(SMALL_INT_TAG)
      buf.code.emit_or_rax_rbx()
      buf.code.emit_push_rax()
    of IkReturn:
      buf.code.emit_pop_rax()
      buf.code.emit_ret()
    else:
      return nil

  let mem = allocate_executable_memory(buf.code.len)
  copyMem(mem, buf.code[0].unsafeAddr, buf.code.len)
  make_executable(mem, buf.code.len)

  JitCompiled(
    entry: cast[JittedFn](mem),
    code: mem,
    size: buf.code.len,
    bytecode_version: cast[uint64](fn.body_compiled.id),
    bytecode_len: fn.body_compiled.instructions.len,
    built_for_arch: "x86_64"
  )
