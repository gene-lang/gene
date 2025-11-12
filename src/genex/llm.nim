import os, strutils, tables, math, osproc
include ../gene/extension/boilerplate
import ../gene/vm

when defined(GENE_LLM_MOCK):
  type
    ModelState = ref object
      id: int64
      path: string
      context_len: int
      threads: int

    SessionState = ref object
      id: int64
      model_id: int64
      context_len: int
      temperature: float
      top_p: float
      top_k: int
      seed: int
      max_tokens: int

  var
    model_class_global: Class
    session_class_global: Class

  var
    model_table {.threadvar.}: Table[int64, ModelState]
    session_table {.threadvar.}: Table[int64, SessionState]
    next_model_id {.threadvar.}: int64
    next_session_id {.threadvar.}: int64
    tables_initialized {.threadvar.}: bool

  const
    MODEL_ID_KEY = "__model_id__"
    SESSION_ID_KEY = "__session_id__"

  proc ensure_tables_initialized() =
    if not tables_initialized:
      model_table = initTable[int64, ModelState]()
      session_table = initTable[int64, SessionState]()
      next_model_id = 1
      next_session_id = 1
      tables_initialized = true

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
      token_array.ref.arr.add(token.to_value())
    map_table["tokens".to_key()] = token_array

    map_table["finish_reason".to_key()] = finish_reason.to_symbol_value()
    if latency_ms >= 0:
      map_table["latency_ms".to_key()] = latency_ms.to_value()

    new_map_value(map_table)

  proc cancellation_value(reason: string = ":cancelled"): Value =
    build_completion_value("", @[], reason, 0)

  proc create_model_instance(state: ModelState): Value =
    let model_id_key = MODEL_ID_KEY.to_key()
    var instance = new_ref(VkInstance)
    instance.instance_class = model_class_global
    if instance.instance_props == nil:
      instance.instance_props = initTable[Key, Value]()
    instance.instance_props[model_id_key] = state.id.to_value()
    instance.instance_props["path".to_key()] = state.path.to_value()
    instance.instance_props["context".to_key()] = state.context_len.to_value()
    instance.instance_props["threads".to_key()] = state.threads.to_value()
    instance.to_ref_value()

  proc create_session_instance(state: SessionState): Value =
    let session_id_key = SESSION_ID_KEY.to_key()
    var instance = new_ref(VkInstance)
    instance.instance_class = session_class_global
    if instance.instance_props == nil:
      instance.instance_props = initTable[Key, Value]()
    instance.instance_props[session_id_key] = state.id.to_value()
    instance.instance_props["model_id".to_key()] = state.model_id.to_value()
    instance.instance_props["context".to_key()] = state.context_len.to_value()
    instance.instance_props["max_tokens".to_key()] = state.max_tokens.to_value()
    instance.instance_props["temperature".to_key()] = state.temperature.to_value()
    instance.instance_props["top_p".to_key()] = state.top_p.to_value()
    instance.instance_props["top_k".to_key()] = state.top_k.to_value()
    instance.to_ref_value()

  proc read_model_id(val: Value): int64 =
    let key = MODEL_ID_KEY.to_key()
    if val.kind != VkInstance or val.ref.instance_props == nil or not val.ref.instance_props.hasKey(key):
      raise new_exception(types.Exception, "LLM model instance is invalid or missing internal id")
    val.ref.instance_props[key].to_int()

  proc read_session_id(val: Value): int64 =
    let key = SESSION_ID_KEY.to_key()
    if val.kind != VkInstance or val.ref.instance_props == nil or not val.ref.instance_props.hasKey(key):
      raise new_exception(types.Exception, "LLM session instance is invalid or missing internal id")
    val.ref.instance_props[key].to_int()

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

    ensure_tables_initialized()

    let resolved_path = normalize_path(path_val.str)
    let allow_missing = get_bool_option(opts, "allow_missing", false)
    if not allow_missing and not fileExists(resolved_path):
      raise new_exception(types.Exception, "LLM model not found: " & resolved_path)

    let context_len = max(256, get_int_option(opts, "context", 2048))
    let threads = max(1, get_int_option(opts, "threads", countProcessors()))

    let model_id = next_model_id
    inc next_model_id

    let state = ModelState(
      id: model_id,
      path: resolved_path,
      context_len: context_len,
      threads: threads
    )
    model_table[model_id] = state

    create_model_instance(state)

  proc vm_model_new_session(vm: VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value {.gcsafe.} =
    let positional = get_positional_count(arg_count, has_keyword_args)
    if positional < 1:
      raise new_exception(types.Exception, "Model.new_session requires self")

    let self_val = get_positional_arg(args, 0, has_keyword_args)
    let model_id = read_model_id(self_val)
    if not model_table.hasKey(model_id):
      raise new_exception(types.Exception, "Referenced LLM model has been released or never loaded")

    let opts =
      if positional >= 2:
        expect_map(get_positional_arg(args, 1, has_keyword_args), "new_session")
      else:
        NIL

    let model_state = model_table[model_id]

    let context_len = get_int_option(opts, "context", model_state.context_len)
    let temperature = get_float_option(opts, "temperature", 0.7)
    let top_p = get_float_option(opts, "top_p", 0.9)
    let top_k = get_int_option(opts, "top_k", 40)
    let seed = get_int_option(opts, "seed", 42)
    let max_tokens = max(0, get_int_option(opts, "max_tokens", 256))

    let session_id = next_session_id
    inc next_session_id

    let session_state = SessionState(
      id: session_id,
      model_id: model_id,
      context_len: context_len,
      temperature: temperature,
      top_p: top_p,
      top_k: top_k,
      seed: seed,
      max_tokens: max_tokens
    )
    session_table[session_id] = session_state

    create_session_instance(session_state)

  proc vm_session_infer(vm: VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value {.gcsafe.} =
    let positional = get_positional_count(arg_count, has_keyword_args)
    if positional < 2:
      raise new_exception(types.Exception, "Session.infer requires self and a prompt string")

    let self_val = get_positional_arg(args, 0, has_keyword_args)
    let session_id = read_session_id(self_val)
    if not session_table.hasKey(session_id):
      raise new_exception(types.Exception, "LLM session no longer exists or was never created")

    let prompt_val = get_positional_arg(args, 1, has_keyword_args)
    if prompt_val.kind != VkString:
      raise new_exception(types.Exception, "Session.infer prompt must be a string")

    let opts =
      if positional >= 3:
        expect_map(get_positional_arg(args, 2, has_keyword_args), "infer")
      else:
        NIL

    let session_state = session_table[session_id]
    var max_tokens = get_int_option(opts, "max_tokens", session_state.max_tokens)
    var temperature = get_float_option(opts, "temperature", session_state.temperature)
    if temperature <= 0:
      temperature = 0.7
    let timeout_provided = has_option(opts, "timeout") or has_option(opts, "timeout_ms")

    if timeout_provided:
      return cancellation_value()

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
        ensure_tables_initialized()

        if App == NIL or App.kind != VkApplication:
          return
        if App.app.genex_ns == NIL or App.app.genex_ns.kind != VkNamespace:
          return

        model_class_global = new_class("Model")
        model_class_global.def_native_method("new_session", vm_model_new_session)

        session_class_global = new_class("Session")
        session_class_global.def_native_method("infer", vm_session_infer)

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
    {.passL: "-lgene_llm".}
    {.passL: "-lllama".}
    {.passL: "-lc++".}

  type
    GeneLlmModel {.importc: "gene_llm_model", header: "gene_llm.h".} = object
    GeneLlmSession {.importc: "gene_llm_session", header: "gene_llm.h".} = object

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
    ModelState = ref object
      id: int64
      path: string
      handle: ptr GeneLlmModel
      context_len: int
      threads: int
      closed: bool

    SessionState = ref object
      id: int64
      model_id: int64
      handle: ptr GeneLlmSession
      context_len: int
      temperature: float
      top_p: float
      top_k: int
      seed: int
      max_tokens: int
      closed: bool

  var
    model_class_global: Class
    session_class_global: Class

  var
    model_table {.threadvar.}: Table[int64, ModelState]
    session_table {.threadvar.}: Table[int64, SessionState]
    next_model_id {.threadvar.}: int64
    next_session_id {.threadvar.}: int64
    tables_initialized {.threadvar.}: bool
    backend_ready {.threadvar.}: bool

  const
    MODEL_ID_KEY = "__model_id__"
    SESSION_ID_KEY = "__session_id__"

  proc ensure_tables_initialized() =
    if not tables_initialized:
      model_table = initTable[int64, ModelState]()
      session_table = initTable[int64, SessionState]()
      next_model_id = 1
      next_session_id = 1
      tables_initialized = true

  proc ensure_backend() =
    if not backend_ready:
      gene_llm_backend_init()
      backend_ready = true

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

  proc completion_to_value(completion: var GeneLlmCompletion): Value =
    var map_table = initTable[Key, Value]()
    let text_value = if completion.text == nil: "" else: $completion.text
    map_table["text".to_key()] = text_value.to_value()

    var token_array = new_array_value(@[])
    if completion.tokens != nil and completion.token_count > 0:
      for i in 0..<completion.token_count:
        let token_ptr = completion.tokens[i]
        if token_ptr != nil:
          token_array.ref.arr.add(($token_ptr).to_value())
        else:
          token_array.ref.arr.add("".to_value())
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

  proc create_model_instance(state: ModelState): Value =
    let model_id_key = MODEL_ID_KEY.to_key()
    var instance = new_ref(VkInstance)
    instance.instance_class = model_class_global
    if instance.instance_props == nil:
      instance.instance_props = initTable[Key, Value]()
    instance.instance_props[model_id_key] = state.id.to_value()
    instance.instance_props["path".to_key()] = state.path.to_value()
    instance.instance_props["context".to_key()] = state.context_len.to_value()
    instance.instance_props["threads".to_key()] = state.threads.to_value()
    instance
    instance.to_ref_value()

  proc create_session_instance(state: SessionState): Value =
    let session_id_key = SESSION_ID_KEY.to_key()
    var instance = new_ref(VkInstance)
    instance.instance_class = session_class_global
    if instance.instance_props == nil:
      instance.instance_props = initTable[Key, Value]()
    instance.instance_props[session_id_key] = state.id.to_value()
    instance.instance_props["model_id".to_key()] = state.model_id.to_value()
    instance.instance_props["context".to_key()] = state.context_len.to_value()
    instance.instance_props["max_tokens".to_key()] = state.max_tokens.to_value()
    instance.instance_props["temperature".to_key()] = state.temperature.to_value()
    instance.instance_props["top_p".to_key()] = state.top_p.to_value()
    instance.instance_props["top_k".to_key()] = state.top_k.to_value()
    instance

  proc read_model_id(val: Value): int64 =
    let key = MODEL_ID_KEY.to_key()
    if val.kind != VkInstance or val.ref.instance_props == nil or not val.ref.instance_props.hasKey(key):
      raise new_exception(types.Exception, "LLM model instance is invalid or missing internal id")
    val.ref.instance_props[key].to_int()

  proc read_session_id(val: Value): int64 =
    let key = SESSION_ID_KEY.to_key()
    if val.kind != VkInstance or val.ref.instance_props == nil or not val.ref.instance_props.hasKey(key):
      raise new_exception(types.Exception, "LLM session instance is invalid or missing internal id")
    val.ref.instance_props[key].to_int()

  proc ensure_model_open(state: ModelState) =
    if state.closed:
      raise new_exception(types.Exception, "LLM model has been closed")

  proc ensure_session_open(state: SessionState) =
    if state.closed:
      raise new_exception(types.Exception, "LLM session has been closed")

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

    ensure_tables_initialized()
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

    let model_id = next_model_id
    inc next_model_id

    let state = ModelState(
      id: model_id,
      path: resolved_path,
      handle: handle,
      context_len: int(model_opts.context_length),
      threads: int(model_opts.threads),
      closed: false
    )
    model_table[model_id] = state

    create_model_instance(state)

  proc vm_model_close(vm: VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value {.gcsafe.} =
    let positional = get_positional_count(arg_count, has_keyword_args)
    if positional < 1:
      raise new_exception(types.Exception, "Model.close requires self")

    let self_val = get_positional_arg(args, 0, has_keyword_args)
    let model_id = read_model_id(self_val)
    if not model_table.hasKey(model_id):
      raise new_exception(types.Exception, "Unknown LLM model instance")

    let state = model_table[model_id]
    ensure_model_open(state)

    for _, session_state in session_table:
      if session_state.model_id == model_id and not session_state.closed:
        raise new_exception(types.Exception, "Cannot close model while sessions are active")

    gene_llm_free_model(state.handle)
    state.closed = true
    model_table.del(model_id)
    NIL

  proc vm_model_new_session(vm: VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value {.gcsafe.} =
    let positional = get_positional_count(arg_count, has_keyword_args)
    if positional < 1:
      raise new_exception(types.Exception, "Model.new_session requires self")

    let self_val = get_positional_arg(args, 0, has_keyword_args)
    let model_id = read_model_id(self_val)
    if not model_table.hasKey(model_id):
      raise new_exception(types.Exception, "Referenced LLM model has been released or never loaded")

    let model_state = model_table[model_id]
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

    let session_id = next_session_id
    inc next_session_id

    let session_state = SessionState(
      id: session_id,
      model_id: model_id,
      handle: handle,
      context_len: int(session_opts.context_length),
      temperature: float(session_opts.temperature),
      top_p: float(session_opts.top_p),
      top_k: int(session_opts.top_k),
      seed: int(session_opts.seed),
      max_tokens: int(session_opts.max_tokens),
      closed: false
    )
    session_table[session_id] = session_state

    create_session_instance(session_state)

  proc vm_session_close(vm: VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value {.gcsafe.} =
    let positional = get_positional_count(arg_count, has_keyword_args)
    if positional < 1:
      raise new_exception(types.Exception, "Session.close requires self")

    let self_val = get_positional_arg(args, 0, has_keyword_args)
    let session_id = read_session_id(self_val)
    if not session_table.hasKey(session_id):
      raise new_exception(types.Exception, "Unknown LLM session instance")

    let state = session_table[session_id]
    ensure_session_open(state)
    gene_llm_free_session(state.handle)
    state.closed = true
    session_table.del(session_id)
    NIL

  proc vm_session_infer(vm: VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value {.gcsafe.} =
    let positional = get_positional_count(arg_count, has_keyword_args)
    if positional < 2:
      raise new_exception(types.Exception, "Session.infer requires self and a prompt string")

    let self_val = get_positional_arg(args, 0, has_keyword_args)
    let session_id = read_session_id(self_val)
    if not session_table.hasKey(session_id):
      raise new_exception(types.Exception, "LLM session no longer exists or was never created")

    let session_state = session_table[session_id]
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
    if not tables_initialized:
      return
    for session_id, state in session_table.mpairs:
      if not state.closed:
        gene_llm_free_session(state.handle)
        state.closed = true
    session_table.clear()
    for model_id, state in model_table.mpairs:
      if not state.closed:
        gene_llm_free_model(state.handle)
        state.closed = true
    model_table.clear()

  addQuitProc(cleanup_llm_backend)

  proc init_llm_module*() =
    VmCreatedCallbacks.add proc() =
      {.cast(gcsafe).}:
        ensure_tables_initialized()
        ensure_backend()

        if App == NIL or App.kind != VkApplication:
          return
        if App.app.genex_ns == NIL or App.app.genex_ns.kind != VkNamespace:
          return

        model_class_global = new_class("Model")
        model_class_global.def_native_method("new_session", vm_model_new_session)
        model_class_global.def_native_method("close", vm_model_close)

        session_class_global = new_class("Session")
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
