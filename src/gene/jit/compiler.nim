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

proc is_likely_recursive(fn: Function): bool =
  ## Heuristic: detect likely recursive functions to avoid JIT performance regression.
  ## Current baseline JIT allocates frames on every call, making recursion slower than interpreter.
  if fn.body_compiled.is_nil:
    return false

  let inst_count = fn.body_compiled.instructions.len

  # Count call instructions - recursive functions typically have multiple call sites
  var call_count = 0
  for inst in fn.body_compiled.instructions:
    case inst.kind
    of IkUnifiedCall0, IkUnifiedCall1, IkUnifiedCall, IkTailCall:
      call_count.inc()
      if call_count >= 2:  # Multiple calls suggest recursion (e.g., fib has 2)
        break
    else:
      discard

  # DEBUG: Log detection
  when defined(geneJitDebug):
    if fn.name.len > 0 and (call_count >= 2 or inst_count < 40):
      echo "JIT heuristic for '", fn.name, "': calls=", call_count, " instrs=", inst_count

  # If function has less than 2 calls, unlikely to be recursive
  if call_count < 2:
    return false

  # Recursive functions are typically small and tight loops
  # fib has 43 instructions, factorial ~30, ackermann ~50
  # Skip JIT for small functions with multiple calls (likely recursive)
  if inst_count < 60:
    when defined(geneJitDebug):
      if fn.name.len > 0:
        echo "  -> SKIPPING (likely recursive)"
    return true

  return false

proc compile_baseline*(vm: VirtualMachine, fn: Function): JitCompiled =
  ## Baseline compiler stub: prepares metadata placeholder until real codegen lands.
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

  # TEMPORARY: Skip likely recursive functions until frame pooling is fixed
  # Current baseline JIT is 5x slower than interpreter on recursion due to
  # frame allocation overhead on every call (see tmp/jit_performance_analysis.md)
  if is_likely_recursive(fn):
    fn.jit_status = JsFailed  # Don't retry
    vm.jit.stats.compilation_failures.inc()
    when defined(geneJitDebug):
      echo "JIT: Skipping recursive function '", fn.name, "'"
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
      # Fallback thunk to interpreter trampoline if compilation declined.
      let thunk = build_jmp_thunk(cast[pointer](jit_interpreter_trampoline))
      compiled = JitCompiled(
        entry: cast[JittedFn](thunk.code),
        code: thunk.code,
        size: thunk.size,
        bytecode_version: if fn.body_compiled != nil: cast[uint64](fn.body_compiled.id) else: 0'u64,
        bytecode_len: if fn.body_compiled != nil: fn.body_compiled.instructions.len else: 0,
        built_for_arch: "arm64",
        uses_vm_stack: true
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
