{.push warning[UnusedImport]: off, warning[UnreachableCode]: off.}
import ../types
import ../types/type_defs
import ./memory
when defined(amd64) or defined(arm64):
  import ./baseline
when defined(amd64):
  import ./x64/thunk
when defined(arm64):
  import ./arm64/thunk

proc jit_interpreter_trampoline(vm: VirtualMachine, fn_value: Value, args: ptr UncheckedArray[Value], arg_count: int): Value {.cdecl, importc.}

proc compile_baseline*(vm: VirtualMachine, fn: Function): JitCompiled =
  ## Baseline compiler: emits native code that calls helper functions.
  ## Recursive calls are handled efficiently by routing through jit_call_function
  ## which uses the interpreter's optimized frame pool.
  when defined(geneJitDebug):
    echo "JIT: Attempting to compile function '", fn.name, "'"

  if not vm.jit.enabled:
    return nil
  when not defined(geneJit):
    vm.jit.stats.compilation_failures.inc()
    return nil

  # Avoid recompiling after a failure.
  if fn.jit_status == JsFailed:
    when defined(geneJitDebug):
      echo "  -> Already marked as failed, skipping"
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
        built_for_arch: "x86_64",
        uses_vm_stack: false
      )
  elif defined(arm64) and defined(geneJit):
    compiled = compile_function_arm64(vm, fn)
    if compiled.is_nil:
      # Fallback thunk to interpreter trampoline if compilation declined.
      let thunk = build_jmp_thunk(cast[pointer](jit_interpreter_trampoline))
      compiled = JitCompiled(
        entry: cast[JittedFn](thunk.code),
        code: thunk.code,
        size: thunk.size,
        bytecode_version: if fn.body_compiled != nil: cast[uint64](fn.body_compiled.id) else: 0'u64,
        bytecode_len: if fn.body_compiled != nil: fn.body_compiled.instructions.len else: 0,
        built_for_arch: "arm64",
        uses_vm_stack: false
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

{.pop.}
