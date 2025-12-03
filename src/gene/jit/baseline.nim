import tables
import ../types
import ../types/type_defs
import ./memory
import ./x64/asm
import ./x64/encoders

proc jit_interpreter_trampoline(vm: VirtualMachine, fn_value: Value, args: ptr UncheckedArray[Value], arg_count: int): Value {.cdecl, importc.}

const
  REG_SP = 0  # we use rax/rbx for computation, track stack_index in memory

proc emit_prologue(buf: var AsmBuffer) =
  # Prologue: currently empty (we operate directly on VM frame stack)
  discard

proc emit_epilogue(buf: var AsmBuffer) =
  buf.code.emit_ret()

proc emit_push_const_int(buf: var AsmBuffer, imm: int32) =
  # Load small int into RAX and push to VM stack (stack_index++)
  buf.code.emit_mov_rax_imm64(cast[uint64](imm.to_value()))
  # TODO: write back into frame.stack[stack_index]; increment stack_index.

proc compile_instruction(buf: var AsmBuffer, inst: Instruction, pc: int) =
  case inst.kind
  of IkPushValue:
    if inst.arg0.kind == VkInt and inst.arg0.to_int() >= int32.low and inst.arg0.to_int() <= int32.high:
      emit_push_const_int(buf, inst.arg0.to_int().int32)
    else:
      # Unsupported literal -> fallback by leaving label unresolved.
      raise newException(types.Exception, "Unsupported literal in JIT baseline")
  of IkReturn:
    buf.emit_epilogue()
  else:
    raise newException(types.Exception, "Unsupported opcode in baseline JIT: " & $inst.kind)

proc compile_function_x64*(vm: VirtualMachine, fn: Function): JitCompiled =
  when not (defined(amd64) and defined(geneJit)):
    return nil

  if fn.body_compiled.is_nil:
    return nil

  var buf = init_asm()
  emit_prologue(buf)

  for pc, inst in fn.body_compiled.instructions:
    try:
      compile_instruction(buf, inst, pc)
    except CatchableError:
      return nil

  buf.emit_epilogue()
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
    built_for_arch: "x86_64"
  )
