import os, strutils, tables, osproc
import ../gene/types

when defined(GENE_LLM_MOCK):
  type
    ModelState = ref object of CustomValue
      path: string
      context_len: int
      threads: int
      closed: bool
      open_sessions: int

    SessionState = ref object of CustomValue
      model: ModelState
      context_len: int
      temperature: float
      top_p: float
      top_k: int
      seed: int
      max_tokens: int
      closed: bool

  var
    model_class_global {.threadvar.}: Class
    session_class_global {.threadvar.}: Class

  proc expect_map(val: Value, context: string): Value =
    if val == NIL:
      return NIL
    if val.kind != VkMap:
      raise new_exception(types.Exception, context & " options must be a map")
    return val

  proc has_option(opts: Value, name: string): bool =
    if opts == NIL or opts.kind != VkMap:
      return false
    let key = name.to_key()
    opts.ref.map.hasKey(key)

  proc get_int_option(opts: Value, name: string, default_value: int): int =
    if opts == NIL or opts.kind != VkMap:
      return default_value
    let key = name.to_key()
    if opts.ref.map.hasKey(key):
      let val = opts.ref.map[key]
      case val.kind
      of VkInt:
        return val.to_int()
      of VkFloat:
        return int(val.to_float())
      else:
        discard
    return default_value

  proc get_float_option(opts: Value, name: string, default_value: float): float =
    if opts == NIL or opts.kind != VkMap:
      return default_value
    let key = name.to_key()
    if opts.ref.map.hasKey(key):
      let val = opts.ref.map[key]
      case val.kind
      of VkFloat:
        return val.to_float()
      of VkInt:
        return float(val.to_int())
      else:
        discard
    return default_value

  proc get_bool_option(opts: Value, name: string, default_value: bool): bool =
    if opts == NIL or opts.kind != VkMap:
      return default_value
    let key = name.to_key()
    if opts.ref.map.hasKey(key):
      return opts.ref.map[key].to_bool()
    return default_value

  proc normalize_path(path: string): string =
    result = expandTilde(path)
    if result.len == 0:
      result = path

  proc mock_generate(prompt: string, max_tokens: int): (string, seq[string], bool) =
    var source = prompt.strip()
    if source.len == 0:
      source = "Hello from Gene"
    var tokens = source.splitWhitespace()
    if tokens.len == 0:
      tokens = @[source]
    let capped =
      if max_tokens <= 0:
        tokens
      else:
        tokens[0 ..< min(tokens.len, max_tokens)]
    let truncated = max_tokens > 0 and tokens.len > max_tokens
    let completion_text = capped.join(" ") & " [mock]"
    (completion_text, capped, truncated)

  proc build_completion_value(text: string, tokens: seq[string], finish_reason: string, latency_ms: int): Value =
    var map_table = initTable[Key, Value]()
    map_table["text".to_key()] = text.to_value()

    var token_array = new_array_value(@[])
    for token in tokens:
      array_data(token_array).add(token.to_value())
    map_table["tokens".to_key()] = token_array

    map_table["finish_reason".to_key()] = finish_reason.to_symbol_value()
    if latency_ms >= 0:
      map_table["latency_ms".to_key()] = latency_ms.to_value()

    new_map_value(map_table)

  proc cancellation_value(reason: string = ":cancelled"): Value =
    build_completion_value("", @[], reason, 0)

  proc expect_model(val: Value, context: string): ModelState =
    if val.kind != VkCustom or val.ref.custom_class != model_class_global:
      raise new_exception(types.Exception, context & " requires an LLM model instance")
    cast[ModelState](get_custom_data(val, "LLM model payload missing"))

  proc expect_session(val: Value, context: string): SessionState =
    if val.kind != VkCustom or val.ref.custom_class != session_class_global:
      raise new_exception(types.Exception, context & " requires an LLM session instance")
    cast[SessionState](get_custom_data(val, "LLM session payload missing"))

  proc new_model_value(state: ModelState): Value {.gcsafe.} =
    new_custom_value(model_class_global, state)

  proc new_session_value(state: SessionState): Value {.gcsafe.} =
    new_custom_value(session_class_global, state)

  proc ensure_model_open(state: ModelState) =
    if state.closed:
      raise new_exception(types.Exception, "LLM model has been closed")

  proc ensure_session_open(state: SessionState) =
    if state.closed:
      raise new_exception(types.Exception, "LLM session has been closed")

  proc cleanup_session(state: SessionState) =
    if state == nil or state.closed:
      return
    state.closed = true
    if state.model != nil and state.model.open_sessions > 0:
      state.model.open_sessions.dec()

  proc cleanup_model(state: ModelState) =
    if state == nil or state.closed:
      return
    state.closed = true


  proc vm_load_model(vm: VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value {.gcsafe.} =
    let positional = get_positional_count(arg_count, has_keyword_args)
    if positional < 1:
      raise new_exception(types.Exception, "genex/llm/load_model requires a file path")

    let path_val = get_positional_arg(args, 0, has_keyword_args)
    if path_val.kind != VkString:
      raise new_exception(types.Exception, "Model path must be a string")

    let opts =
      if positional >= 2:
        expect_map(get_positional_arg(args, 1, has_keyword_args), "load_model")
      else:
        NIL

    let resolved_path = normalize_path(path_val.str)
    let allow_missing = get_bool_option(opts, "allow_missing", false)
    if not allow_missing and not fileExists(resolved_path):
      raise new_exception(types.Exception, "LLM model not found: " & resolved_path)

    let context_len = max(256, get_int_option(opts, "context", 2048))
    let threads = max(1, get_int_option(opts, "threads", countProcessors()))

    let state = ModelState(
      path: resolved_path,
      context_len: context_len,
      threads: threads
    )
    new_model_value(state)

  proc vm_model_close(vm: VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value {.gcsafe.} =
    let positional = get_positional_count(arg_count, has_keyword_args)
    if positional < 1:
      raise new_exception(types.Exception, "Model.close requires self")
    let self_val = get_positional_arg(args, 0, has_keyword_args)
    let state = expect_model(self_val, "Model.close")
    ensure_model_open(state)
    if state.open_sessions > 0:
      raise new_exception(types.Exception, "Cannot close model while sessions are active")
    cleanup_model(state)
    NIL

  proc vm_model_new_session(vm: VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value {.gcsafe.} =
    let positional = get_positional_count(arg_count, has_keyword_args)
    if positional < 1:
      raise new_exception(types.Exception, "Model.new_session requires self")

    let self_val = get_positional_arg(args, 0, has_keyword_args)
    let model_state = expect_model(self_val, "Model.new_session")
    ensure_model_open(model_state)

    let opts =
      if positional >= 2:
        expect_map(get_positional_arg(args, 1, has_keyword_args), "new_session")
      else:
        NIL

    let context_len = get_int_option(opts, "context", model_state.context_len)
    let temperature = get_float_option(opts, "temperature", 0.7)
    let top_p = get_float_option(opts, "top_p", 0.9)
    let top_k = get_int_option(opts, "top_k", 40)
    let seed = get_int_option(opts, "seed", 42)
    let max_tokens = max(0, get_int_option(opts, "max_tokens", 256))

    let session_state = SessionState(
      model: model_state,
      context_len: context_len,
      temperature: temperature,
      top_p: top_p,
      top_k: top_k,
      seed: seed,
      max_tokens: max_tokens
    )
    model_state.open_sessions.inc()
    new_session_value(session_state)

  proc vm_session_close(vm: VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value {.gcsafe.} =
    let positional = get_positional_count(arg_count, has_keyword_args)
    if positional < 1:
      raise new_exception(types.Exception, "Session.close requires self")
    let self_val = get_positional_arg(args, 0, has_keyword_args)
    let session_state = expect_session(self_val, "Session.close")
    ensure_session_open(session_state)
    cleanup_session(session_state)
    NIL

  proc vm_session_infer(vm: VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value {.gcsafe.} =
    let positional = get_positional_count(arg_count, has_keyword_args)
    if positional < 2:
      raise new_exception(types.Exception, "Session.infer requires self and a prompt string")

    let self_val = get_positional_arg(args, 0, has_keyword_args)
    let session_state = expect_session(self_val, "Session.infer")
    ensure_session_open(session_state)

    let prompt_val = get_positional_arg(args, 1, has_keyword_args)
    if prompt_val.kind != VkString:
      raise new_exception(types.Exception, "Session.infer prompt must be a string")

    let opts =
      if positional >= 3:
        expect_map(get_positional_arg(args, 2, has_keyword_args), "infer")
      else:
        NIL

    var max_tokens = get_int_option(opts, "max_tokens", session_state.max_tokens)
    var temperature = get_float_option(opts, "temperature", session_state.temperature)
    if temperature <= 0:
      temperature = 0.7
    let timeout_provided = has_option(opts, "timeout") or has_option(opts, "timeout_ms")

    if timeout_provided:
      raise new_exception(types.Exception, "Session.infer timeout is not supported for local inference yet")

    if max_tokens <= 0:
      return cancellation_value()

    let (text, tokens, truncated) = mock_generate(prompt_val.str, max_tokens)
    let finish_reason =
      if truncated:
        ":length"
      else:
        ":stop"

    let latency_ms = max(1, prompt_val.str.len * 2)

    build_completion_value(text, tokens, finish_reason, latency_ms)

  proc init_llm_module*() =
    VmCreatedCallbacks.add proc() =
      {.cast(gcsafe).}:
        if App == NIL or App.kind != VkApplication:
          return
        if App.app.genex_ns == NIL or App.app.genex_ns.kind != VkNamespace:
          return

        model_class_global = new_class("Model")
        if App.app.object_class.kind == VkClass:
          model_class_global.parent = App.app.object_class.ref.class
        model_class_global.def_native_method("new_session", vm_model_new_session)
        model_class_global.def_native_method("close", vm_model_close)

        session_class_global = new_class("Session")
        if App.app.object_class.kind == VkClass:
          session_class_global.parent = App.app.object_class.ref.class
        session_class_global.def_native_method("infer", vm_session_infer)
        session_class_global.def_native_method("close", vm_session_close)

        let llm_ns = new_ref(VkNamespace)
        llm_ns.ns = new_namespace("llm")

        let load_fn = new_ref(VkNativeFn)
        load_fn.native_fn = vm_load_model
        llm_ns.ns["load_model".to_key()] = load_fn.to_ref_value()

        let model_class_ref = new_ref(VkClass)
        model_class_ref.class = model_class_global
        llm_ns.ns["Model".to_key()] = model_class_ref.to_ref_value()

        let session_class_ref = new_ref(VkClass)
        session_class_ref.class = session_class_global
        llm_ns.ns["Session".to_key()] = session_class_ref.to_ref_value()

        App.app.genex_ns.ref.ns["llm".to_key()] = llm_ns.to_ref_value()

  init_llm_module()

else:
  const
    llmSourceDir = parentDir(currentSourcePath())
    projectDir = parentDir(parentDir(llmSourceDir))
    llamaIncludeDir = joinPath(projectDir, "tools/llama.cpp/include")
    ggmlIncludeDir = joinPath(projectDir, "tools/llama.cpp/ggml/include")
    shimIncludeDir = joinPath(projectDir, "src/genex/llm/shim")
    llamaBuildDir = joinPath(projectDir, "build/llama")

  static:
    {.passC: "-I" & llamaIncludeDir.}
    {.passC: "-I" & ggmlIncludeDir.}
    {.passC: "-I" & shimIncludeDir.}
    {.passL: "-L" & llamaBuildDir.}
    {.passL: "-L" & llamaBuildDir & "/ggml/src".}
    {.passL: "-L" & llamaBuildDir & "/ggml/src/ggml-blas".}
    {.passL: "-L" & llamaBuildDir & "/ggml/src/ggml-metal".}
    {.passL: "-lgene_llm".}
    {.passL: "-lllama".}
    {.passL: "-lggml".}
    {.passL: "-lggml-base".}
    {.passL: "-lggml-cpu".}
    {.passL: "-lggml-blas".}
    {.passL: "-lggml-metal".}
    {.passL: "-framework Metal".}
    {.passL: "-framework Foundation".}
    {.passL: "-framework Accelerate".}
    {.passL: "-lc++".}

  type
    GeneLlmModel {.importc: "struct gene_llm_model", header: "gene_llm.h".} = object
    GeneLlmSession {.importc: "struct gene_llm_session", header: "gene_llm.h".} = object

    GeneLlmStatus {.size: sizeof(cint).} = enum
      glsOk = 0
      glsError = 1

    GeneLlmFinishReason {.size: sizeof(cint).} = enum
      glfStop = 0
      glfLength = 1
      glfCancelled = 2
      glfError = 3

    GeneLlmModelOptions {.importc: "gene_llm_model_options", header: "gene_llm.h".} = object
      context_length*: cint
      threads*: cint
      gpu_layers*: cint
      use_mmap*: bool
      use_mlock*: bool

    GeneLlmSessionOptions {.importc: "gene_llm_session_options", header: "gene_llm.h".} = object
      context_length*: cint
      batch_size*: cint
      threads*: cint
      seed*: cint
      temperature*: cfloat
      top_p*: cfloat
      top_k*: cint
      max_tokens*: cint

    GeneLlmInferOptions {.importc: "gene_llm_infer_options", header: "gene_llm.h".} = object
      prompt*: cstring
      max_tokens*: cint
      temperature*: cfloat
      top_p*: cfloat
      top_k*: cint
      seed*: cint

    GeneLlmError {.importc: "gene_llm_error", header: "gene_llm.h".} = object
      code*: cint
      message*: array[512, char]

    GeneLlmCompletion {.importc: "gene_llm_completion", header: "gene_llm.h".} = object
      text*: cstring
      tokens*: ptr cstring
      token_count*: cint
      latency_ms*: cint
      finish_reason*: GeneLlmFinishReason

  proc gene_llm_backend_init() {.cdecl, importc: "gene_llm_backend_init", header: "gene_llm.h".}
  proc gene_llm_load_model(path: cstring, opts: ptr GeneLlmModelOptions, out_model: ptr ptr GeneLlmModel, err: ptr GeneLlmError): GeneLlmStatus {.cdecl, importc: "gene_llm_load_model", header: "gene_llm.h".}
  proc gene_llm_free_model(model: ptr GeneLlmModel) {.cdecl, importc: "gene_llm_free_model", header: "gene_llm.h".}
  proc gene_llm_new_session(model: ptr GeneLlmModel, opts: ptr GeneLlmSessionOptions, out_session: ptr ptr GeneLlmSession, err: ptr GeneLlmError): GeneLlmStatus {.cdecl, importc: "gene_llm_new_session", header: "gene_llm.h".}
  proc gene_llm_free_session(session: ptr GeneLlmSession) {.cdecl, importc: "gene_llm_free_session", header: "gene_llm.h".}
  proc gene_llm_infer(session: ptr GeneLlmSession, opts: ptr GeneLlmInferOptions, completion: ptr GeneLlmCompletion, err: ptr GeneLlmError): GeneLlmStatus {.cdecl, importc: "gene_llm_infer", header: "gene_llm.h".}
  proc gene_llm_free_completion(completion: ptr GeneLlmCompletion) {.cdecl, importc: "gene_llm_free_completion", header: "gene_llm.h".}

  type
    ModelState = ref object of CustomValue
      path: string
      handle: ptr GeneLlmModel
      context_len: int
      threads: int
      closed: bool
      open_sessions: int

    SessionState = ref object of CustomValue
      model: ModelState
      handle: ptr GeneLlmSession
      context_len: int
      temperature: float
      top_p: float
      top_k: int
      seed: int
      max_tokens: int
      closed: bool

  var
    model_class_global {.threadvar.}: Class
    session_class_global {.threadvar.}: Class
    backend_ready {.threadvar.}: bool
    tracked_models {.threadvar.}: seq[ModelState]
    tracked_sessions {.threadvar.}: seq[SessionState]

  proc ensure_backend() =
    if not backend_ready:
      gene_llm_backend_init()
      backend_ready = true

  proc track_model(state: ModelState) =
    tracked_models.add(state)

  proc untrack_model(state: ModelState) =
    for i in countdown(tracked_models.len - 1, 0):
      if tracked_models[i] == state:
        tracked_models.delete(i)
        break

  proc track_session(state: SessionState) =
    tracked_sessions.add(state)

  proc untrack_session(state: SessionState) =
    for i in countdown(tracked_sessions.len - 1, 0):
      if tracked_sessions[i] == state:
        tracked_sessions.delete(i)
        break

  proc expect_model(val: Value, context: string): ModelState =
    if val.kind != VkCustom or val.ref.custom_class != model_class_global:
      raise new_exception(types.Exception, context & " requires an LLM model instance")
    cast[ModelState](get_custom_data(val, "LLM model payload missing"))

  proc expect_session(val: Value, context: string): SessionState =
    if val.kind != VkCustom or val.ref.custom_class != session_class_global:
      raise new_exception(types.Exception, context & " requires an LLM session instance")
    cast[SessionState](get_custom_data(val, "LLM session payload missing"))

  proc new_model_value(state: ModelState): Value {.gcsafe.} =
    new_custom_value(model_class_global, state)

  proc new_session_value(state: SessionState): Value {.gcsafe.} =
    new_custom_value(session_class_global, state)

  proc ensure_model_open(state: ModelState) =
    if state.closed:
      raise new_exception(types.Exception, "LLM model has been closed")

  proc ensure_session_open(state: SessionState) =
    if state.closed:
      raise new_exception(types.Exception, "LLM session has been closed")

  proc expect_map(val: Value, context: string): Value =
    if val == NIL:
      return NIL
    if val.kind != VkMap:
      raise new_exception(types.Exception, context & " options must be a map")
    return val

  proc has_option(opts: Value, name: string): bool =
    if opts == NIL or opts.kind != VkMap:
      return false
    opts.ref.map.hasKey(name.to_key())

  proc get_int_option(opts: Value, name: string, default_value: int): int =
    if opts == NIL or opts.kind != VkMap:
      return default_value
    let key = name.to_key()
    if opts.ref.map.hasKey(key):
      let val = opts.ref.map[key]
      case val.kind
      of VkInt:
        return val.to_int()
      of VkFloat:
        return int(val.to_float())
      else:
        discard
    return default_value

  proc get_float_option(opts: Value, name: string, default_value: float): float =
    if opts == NIL or opts.kind != VkMap:
      return default_value
    let key = name.to_key()
    if opts.ref.map.hasKey(key):
      let val = opts.ref.map[key]
      case val.kind
      of VkFloat:
        return val.to_float()
      of VkInt:
        return float(val.to_int())
      else:
        discard
    return default_value

  proc get_bool_option(opts: Value, name: string, default_value: bool): bool =
    if opts == NIL or opts.kind != VkMap:
      return default_value
    let key = name.to_key()
    if opts.ref.map.hasKey(key):
      return opts.ref.map[key].to_bool()
    return default_value

  proc normalize_path(path: string): string =
    result = expandTilde(path)
    if result.len == 0:
      result = path

  proc error_string(err: GeneLlmError): string =
    var buffer = newStringOfCap(512)
    for ch in err.message:
      if ch == '\0':
        break
      buffer.add(ch)
    if buffer.len == 0:
      return "LLM backend error"
    buffer

  proc raise_backend_error(err: GeneLlmError) =
    raise new_exception(types.Exception, error_string(err))

  proc cleanup_session(state: SessionState) =
    if state == nil or state.closed:
      return
    state.closed = true
    if state.handle != nil:
      gene_llm_free_session(state.handle)
      state.handle = nil
    if state.model != nil and state.model.open_sessions > 0:
      state.model.open_sessions.dec()
    untrack_session(state)

  proc cleanup_model(state: ModelState) =
    if state == nil or state.closed:
      return
    state.closed = true
    if state.handle != nil:
      gene_llm_free_model(state.handle)
      state.handle = nil
    untrack_model(state)


  proc completion_to_value(completion: var GeneLlmCompletion): Value =
    var map_table = initTable[Key, Value]()
    let text_value = if completion.text == nil: "" else: $completion.text
    map_table["text".to_key()] = text_value.to_value()

    var token_array = new_array_value(@[])
    if completion.tokens != nil and completion.token_count > 0:
      for i in 0..<completion.token_count:
        let token_ptr = completion.tokens[i]
        if token_ptr != nil:
        array_data(token_array).add(($token_ptr).to_value())
      else:
        array_data(token_array).add("".to_value())
    map_table["tokens".to_key()] = token_array

    let finish_symbol =
      case completion.finish_reason
      of glfStop:
        ":stop"
      of glfLength:
        ":length"
      of glfCancelled:
        ":cancelled"
      of glfError:
        ":error"

    map_table["finish_reason".to_key()] = finish_symbol.to_symbol_value()
    map_table["latency_ms".to_key()] = completion.latency_ms.to_value()

    new_map_value(map_table)

  proc vm_load_model(vm: VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value {.gcsafe.} =
    let positional = get_positional_count(arg_count, has_keyword_args)
    if positional < 1:
      raise new_exception(types.Exception, "genex/llm/load_model requires a file path")

    let path_val = get_positional_arg(args, 0, has_keyword_args)
    if path_val.kind != VkString:
      raise new_exception(types.Exception, "Model path must be a string")

    let opts =
      if positional >= 2:
        expect_map(get_positional_arg(args, 1, has_keyword_args), "load_model")
      else:
        NIL

    ensure_backend()

    let resolved_path = normalize_path(path_val.str)
    let allow_missing = get_bool_option(opts, "allow_missing", false)
    if not allow_missing and not fileExists(resolved_path):
      raise new_exception(types.Exception, "LLM model not found: " & resolved_path)

    var model_opts = GeneLlmModelOptions(
      context_length: cint(max(256, get_int_option(opts, "context", 2048))),
      threads: cint(max(1, get_int_option(opts, "threads", countProcessors()))),
      gpu_layers: cint(max(0, get_int_option(opts, "gpu_layers", 0))),
      use_mmap: not get_bool_option(opts, "disable_mmap", false),
      use_mlock: get_bool_option(opts, "mlock", false)
    )

    var err: GeneLlmError
    var handle: ptr GeneLlmModel
    let status = gene_llm_load_model(resolved_path.cstring, addr model_opts, addr handle, addr err)
    if status != glsOk or handle == nil:
      raise_backend_error(err)

    let state = ModelState(
      path: resolved_path,
      handle: handle,
      context_len: int(model_opts.context_length),
      threads: int(model_opts.threads)
    )
    track_model(state)
    new_model_value(state)

  proc vm_model_close(vm: VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value {.gcsafe.} =
    let positional = get_positional_count(arg_count, has_keyword_args)
    if positional < 1:
      raise new_exception(types.Exception, "Model.close requires self")

    let self_val = get_positional_arg(args, 0, has_keyword_args)
    let state = expect_model(self_val, "Model.close")
    ensure_model_open(state)

    if state.open_sessions > 0:
      raise new_exception(types.Exception, "Cannot close model while sessions are active")

    cleanup_model(state)
    NIL

  proc vm_model_new_session(vm: VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value {.gcsafe.} =
    let positional = get_positional_count(arg_count, has_keyword_args)
    if positional < 1:
      raise new_exception(types.Exception, "Model.new_session requires self")

    let self_val = get_positional_arg(args, 0, has_keyword_args)
    let model_state = expect_model(self_val, "Model.new_session")
    ensure_model_open(model_state)

    let opts =
      if positional >= 2:
        expect_map(get_positional_arg(args, 1, has_keyword_args), "new_session")
      else:
        NIL

    var session_opts = GeneLlmSessionOptions(
      context_length: cint(get_int_option(opts, "context", model_state.context_len)),
      batch_size: cint(min(512, get_int_option(opts, "batch", model_state.context_len))),
      threads: cint(max(1, get_int_option(opts, "threads", model_state.threads))),
      seed: cint(get_int_option(opts, "seed", 42)),
      temperature: get_float_option(opts, "temperature", 0.7).cfloat,
      top_p: get_float_option(opts, "top_p", 0.9).cfloat,
      top_k: cint(get_int_option(opts, "top_k", 40)),
      max_tokens: cint(max(1, get_int_option(opts, "max_tokens", 256)))
    )

    var err: GeneLlmError
    var handle: ptr GeneLlmSession
    let status = gene_llm_new_session(model_state.handle, addr session_opts, addr handle, addr err)
    if status != glsOk or handle == nil:
      raise_backend_error(err)

    let session_state = SessionState(
      model: model_state,
      handle: handle,
      context_len: int(session_opts.context_length),
      temperature: cast[float](session_opts.temperature),
      top_p: cast[float](session_opts.top_p),
      top_k: int(session_opts.top_k),
      seed: int(session_opts.seed),
      max_tokens: int(session_opts.max_tokens)
    )
    model_state.open_sessions.inc()
    track_session(session_state)
    new_session_value(session_state)

  proc vm_session_close(vm: VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value {.gcsafe.} =
    let positional = get_positional_count(arg_count, has_keyword_args)
    if positional < 1:
      raise new_exception(types.Exception, "Session.close requires self")

    let self_val = get_positional_arg(args, 0, has_keyword_args)
    let state = expect_session(self_val, "Session.close")
    ensure_session_open(state)
    cleanup_session(state)
    NIL

  proc vm_session_infer(vm: VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value {.gcsafe.} =
    let positional = get_positional_count(arg_count, has_keyword_args)
    if positional < 2:
      raise new_exception(types.Exception, "Session.infer requires self and a prompt string")

    let self_val = get_positional_arg(args, 0, has_keyword_args)
    let session_state = expect_session(self_val, "Session.infer")
    ensure_session_open(session_state)

    let prompt_val = get_positional_arg(args, 1, has_keyword_args)
    if prompt_val.kind != VkString:
      raise new_exception(types.Exception, "Session.infer prompt must be a string")

    let opts =
      if positional >= 3:
        expect_map(get_positional_arg(args, 2, has_keyword_args), "infer")
      else:
        NIL

    if has_option(opts, "timeout") or has_option(opts, "timeout_ms"):
      raise new_exception(types.Exception, "Session.infer timeout is not supported for local inference yet")

    var infer_opts = GeneLlmInferOptions(
      prompt: prompt_val.str.cstring,
      max_tokens: cint(max(1, get_int_option(opts, "max_tokens", session_state.max_tokens))),
      temperature: get_float_option(opts, "temperature", session_state.temperature).cfloat,
      top_p: get_float_option(opts, "top_p", session_state.top_p).cfloat,
      top_k: cint(max(1, get_int_option(opts, "top_k", session_state.top_k))),
      seed: cint(get_int_option(opts, "seed", session_state.seed))
    )

    var completion: GeneLlmCompletion
    var err: GeneLlmError
    let status = gene_llm_infer(session_state.handle, addr infer_opts, addr completion, addr err)
    if status != glsOk:
      raise_backend_error(err)

    let result_value = completion_to_value(completion)
    gene_llm_free_completion(addr completion)
    result_value

  proc cleanup_llm_backend() {.noconv.} =
    for state in tracked_sessions:
      cleanup_session(state)
    tracked_sessions.setLen(0)
    for state in tracked_models:
      cleanup_model(state)
    tracked_models.setLen(0)

  addQuitProc(cleanup_llm_backend)

  proc init_llm_module*() =
    VmCreatedCallbacks.add proc() =
      {.cast(gcsafe).}:
        ensure_backend()

        if App == NIL or App.kind != VkApplication:
          return
        if App.app.genex_ns == NIL or App.app.genex_ns.kind != VkNamespace:
          return

        model_class_global = new_class("Model")
        if App.app.object_class.kind == VkClass:
          model_class_global.parent = App.app.object_class.ref.class
        model_class_global.def_native_method("new_session", vm_model_new_session)
        model_class_global.def_native_method("close", vm_model_close)

        session_class_global = new_class("Session")
        if App.app.object_class.kind == VkClass:
          session_class_global.parent = App.app.object_class.ref.class
        session_class_global.def_native_method("infer", vm_session_infer)
        session_class_global.def_native_method("close", vm_session_close)

        let llm_ns = new_ref(VkNamespace)
        llm_ns.ns = new_namespace("llm")

        let load_fn = new_ref(VkNativeFn)
        load_fn.native_fn = vm_load_model
        llm_ns.ns["load_model".to_key()] = load_fn.to_ref_value()

        let model_class_ref = new_ref(VkClass)
        model_class_ref.class = model_class_global
        llm_ns.ns["Model".to_key()] = model_class_ref.to_ref_value()

        let session_class_ref = new_ref(VkClass)
        session_class_ref.class = session_class_global
        llm_ns.ns["Session".to_key()] = session_class_ref.to_ref_value()

        App.app.genex_ns.ref.ns["llm".to_key()] = llm_ns.to_ref_value()

  init_llm_module()
