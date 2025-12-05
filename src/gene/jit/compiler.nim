import ../types
import ../types/type_defs
import ./memory
when defined(amd64) or defined(arm64):
  import ./baseline
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

  when defined(amd64) and defined(geneJit):
    compiled = compile_function_x64(vm, fn)
    if compiled.is_nil:
      # Fallback thunk to interpreter trampoline if compilation declined.
      let thunk = build_jmp_thunk(cast[pointer](jit_interpreter_trampoline))
      compiled = JitCompiled(
        entry: cast[JittedFn](thunk.code),
        code: thunk.code,
        size: thunk.size,
        bytecode_version: if fn.body_compiled != nil: cast[uint64](fn.body_compiled.id) else: 0'u64,
        bytecode_len: if fn.body_compiled != nil: fn.body_compiled.instructions.len else: 0,
        built_for_arch: "x86_64"
      )
  elif defined(arm64) and defined(geneJit):
    compiled = compile_function_arm64(vm, fn)
    if compiled.is_nil:
      compiled = JitCompiled(
        entry: jit_interpreter_trampoline,
        code: nil,
        size: 0,
        bytecode_version: if fn.body_compiled != nil: cast[uint64](fn.body_compiled.id) else: 0'u64,
        bytecode_len: if fn.body_compiled != nil: fn.body_compiled.instructions.len else: 0,
        built_for_arch: "arm64"
      )
  else:
    compiled.entry = jit_interpreter_trampoline
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
