import ../types
import ../types/type_defs
import ./memory

when defined(amd64):
  import ./x64/thunk

proc jit_interpreter_trampoline(vm: VirtualMachine, fn_value: Value, args: ptr UncheckedArray[Value], arg_count: int): Value {.cdecl, importc.}

proc compile_baseline*(vm: VirtualMachine, fn: Function): JitCompiled =
  ## Baseline compiler stub: prepares metadata placeholder until real codegen lands.
  if not vm.jit.enabled:
    return nil
  when not defined(geneJit):
    vm.jit.stats.compilation_failures.inc()
    return nil

  # Avoid recompiling after a failure.
  if fn.jit_status == JsFailed:
    return nil

  fn.jit_status = JsCompiling
  var compiled = JitCompiled()
  compiled.entry = nil
  compiled.code = nil
  compiled.size = 0
  compiled.bytecode_version = if fn.body_compiled != nil: cast[uint64](fn.body_compiled.id) else: 0'u64
  compiled.bytecode_len = if fn.body_compiled != nil: fn.body_compiled.instructions.len else: 0
  compiled.built_for_arch =
    when defined(amd64): "x86_64"
    elif defined(arm64): "arm64"
    else: "unknown"

  when defined(amd64) and defined(geneJit):
    # Build a tiny thunk that jumps to the interpreter trampoline (exercises emit + RW→RX path).
    let thunk = build_jmp_thunk(cast[pointer](jit_interpreter_trampoline))
    compiled.code = thunk.code
    compiled.size = thunk.size
    compiled.entry = cast[JittedFn](compiled.code)
  else:
    compiled.entry = jit_interpreter_trampoline  # Interpreter bridge until native codegen lands

  fn.jit_status = JsCompiled
  vm.jit.stats.compilations.inc()
  result = compiled
