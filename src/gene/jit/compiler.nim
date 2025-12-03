import ../types
import ../types/type_defs
proc jit_interpreter_trampoline(vm: VirtualMachine, fn_value: Value, args: ptr UncheckedArray[Value], arg_count: int): Value {.cdecl, gcsafe, importc.}

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
  compiled.entry = jit_interpreter_trampoline  # Interpreter bridge until native codegen lands
  compiled.code = nil
  compiled.size = 0
  compiled.bytecode_version = if fn.body_compiled != nil: cast[uint64](fn.body_compiled.id) else: 0'u64
  compiled.bytecode_len = if fn.body_compiled != nil: fn.body_compiled.instructions.len else: 0
  compiled.built_for_arch =
    when defined(amd64): "x86_64"
    elif defined(arm64): "arm64"
    else: "unknown"

  fn.jit_status = JsCompiled
  vm.jit.stats.compilations.inc()
  result = compiled
