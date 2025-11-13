# Design: LLM Inference (add-llm-inference)

## Context
- Gene needs a first-class API for local LLM inference to unlock automation demos and future assistants.
- We will embed llama.cpp as the native engine; it already supports GGUF models and portable CPU/GPU builds.
- Open questions in the proposal are now resolved by the user: (1) no streaming tokens in v1, (2) vendor the runtime under `tools/llama_cpp`, (3) surface all runtime errors as Gene exceptions.
- Constraints: keep VM single-threaded (no direct Nim thread usage on the Gene stack), avoid changing instruction set, and keep build optional so contributors without models can still work.

## Goals / Non-Goals
**Goals**
1. Provide `genex/llm/load_model`, `Model .new_session`, and `Session .infer` primitives per spec.
2. Manage native resources safely (finalizers) without leaking model/session memory.
3. Keep VM responsive by running blocking llama.cpp inference off the main thread.
4. Document build + model requirements and add mock-backed tests so CI runs without real weights.

**Non-Goals**
1. Streaming token callbacks (explicitly deferred by user answer; design only lays groundwork).
2. Remote/networked inference—scope is offline GGUF via llama.cpp only.
3. Tool-calling / JSON-mode semantics beyond raw text completions.
4. Instruction or compiler changes; API exposed entirely through natives + stdlib helpers.

## Key Decisions
1. **Runtime packaging**: Add llama.cpp as a git submodule under `tools/llama_cpp/` and build a thin shim (`libgene_llm.a`). Keeps versions pinned and reproducible.
2. **Shim boundary**: Expose C functions (`gene_llm_load_model`, `gene_llm_new_session`, `gene_llm_infer`) that wrap llama.cpp structs and hide STL usage, keeping Nim FFI simple.
3. **Value representation**: Wrap Model/Session handles inside `VkExternal` records that store a pointer + finalizer; the GC will free native objects once unreachable.
4. **Concurrency**: Use a dedicated background worker threadpool (1 thread initially) to execute blocking inference. Work is queued from Nim and results returned via `Channel[Value]`, mirroring the HTTP server pattern.
5. **API semantics**: `.infer` executes synchronously from the Gene caller’s perspective but the heavy lifting happens off-thread; optional `^timeout` parameter cancels the background task.
6. **Error propagation**: Every shim call returns an error code/string; Nim converts failures into Gene exceptions so user code can `catch *` normally. No status tuples.
7. **Testing**: Provide a mock shim implementation (compiled when `-d:GENE_LLM_MOCK`) that returns deterministic strings, enabling Nim tests + Gene example without downloading weights.

## Architecture Overview
```
Gene code  ──(call genex/llm)──> Nim native shim ──FFI──> llama.cpp runtime
   |                               |                          |
   |                    background job queue        llama.cpp context/session
   |<────── completion map (Value) ◄──── results ◄── tokens / logits
```

### Native shim (tools/llama_cpp)
- Structure mirrors llama.cpp’s `examples/common` but trimmed to only the APIs we need.
- Provides opaque structs:
  - `gene_llm_model` wraps `llama_model*` + metadata (context max, vocab size).
  - `gene_llm_session` wraps `llama_context*` plus sampling config.
- Functions:
  - `gene_llm_load_model(const char *path, gene_llm_model **out_model, gene_llm_load_opts *opts)`
  - `gene_llm_free_model(gene_llm_model*)`
  - `gene_llm_new_session(gene_llm_model*, gene_llm_session **out_session, gene_llm_session_opts *opts)`
  - `gene_llm_free_session(gene_llm_session*)`
  - `gene_llm_infer(gene_llm_session*, const gene_llm_infer_opts*, gene_llm_infer_result*)`
- Build integration: add `tools/build_llm_runtime.sh` that configures llama.cpp with `LLAMA_STATIC=ON`, Metal off by default, CUDA optional. Nimble gains `--define:geneLLM` to opt in.

### Nim bindings (`src/genex/llm.nim`)
- Imports shim headers via `{.importc.}` declarations.
- Wraps native pointers in `ref ModelHandle` / `ref SessionHandle` (thin). Each registers a finalizer calling the corresponding `gene_llm_free_*` proc.
- Provides public procs:
  - `proc load_model*(path: string; opts: LlmModelOpts = default): Value`
  - `proc new_session*(model: Value; opts: LlmSessionOpts = default): Value`
  - `proc infer*(session: Value; prompt: string; opts: LlmInferOpts = default): Value`
- Registers natives inside `register_io_functions()` so Gene code can access `(genex/llm/...)` without extra imports.

### Background execution
- Introduce `llm_job_queue` similar to `handler_queue` in `genex/http.nim`.
- `Session .infer` pushes a job struct `{session_ptr, prompt, opts, result_chan}` to this queue and wakes a worker thread.
- Worker thread calls `gene_llm_infer`, packages `{^text ..., ^tokens [...], ^finish_reason :stop}` as Nim `Value`, and sends over channel.
- Call site blocks by waiting on the channel (with optional timeout) so from Gene’s POV `.infer` is synchronous but does not tie up VM dispatch.

### Gene API surface
- `(genex/llm/load_model path optsMap)` → returns Model instance (class `LlmModel`).
- `(model .new_session optsMap)` → returns `LlmSession` instance with `/model` back-reference.
- `(session .infer prompt ^max_tokens 128 ^temperature 0.8)` → returns map.
- Options maps are plain Gene maps with keyword keys; Nim parses them and supplies defaults (context length, threads, seed, temperature, top_p, top_k).
- No streaming callback in v1; design leaves room for a future `^stream` handler but it’s disabled/ignored for now.

### Option reference
**`genex/llm/load_model`**
- `^context` (int, default 2048) — clamp to ≥256 tokens, capped only by what llama.cpp accepts.
- `^threads` (int, default = host CPU count) — clamp to ≥1, forwarded to llama.cpp thread pool.
- `^gpu_layers` (int, default 0) — number of layers to keep on GPU; clamp to ≥0.
- `^disable_mmap` (bool, default false) — when true, disables llama.cpp’s mmap usage for filesystems that do not support it.
- `^mlock` (bool, default false) — locks model pages into RAM to avoid swapping when supported.
- `^allow_missing` (bool, default false) — skips the upfront filesystem existence check so the mock backend can be exercised without a real file.

**`Model .new_session`**
- `^context` (int, default = model context) — cannot exceed the model’s supported context window; backend will reject invalid sizes.
- `^batch` (int, default = min(512, ^context)) — controls prompt batching; values >512 are clamped.
- `^threads` (int, default = model threads) — lets callers oversubscribe/undersubscribe relative to the load-time default.
- `^seed` (int, default 42) — sampling seed.
- `^temperature` (float, default 0.7), `^top_p` (float, default 0.9), `^top_k` (int, default 40) — stored as the session’s baseline sampling config.
- `^max_tokens` (int, default 256, clamp ≥1) — used when `.infer` is invoked without overrides.

**`Session .infer`**
- Accepts `^max_tokens`, `^temperature`, `^top_p`, `^top_k`, and `^seed` to override the session defaults for a single call.
- `^timeout`, `^timeout_ms`, and `^stream` remain **unsupported** in v1; providing them must raise a descriptive Gene exception so callers know streaming is deferred.
- Returns a completion map containing `^text`, `^tokens` (array of emitted token strings), `^finish_reason` (`:stop|:length|:cancelled|:error`), and `^latency_ms`.

### Memory & Lifetime Safety
- `LlmModel` and `LlmSession` values keep `VkExternal` handles alive; we add `.finalizer` procs that enqueue a “destroy” job to the worker thread, ensuring llama.cpp resources are freed off the VM thread.
- Reference loops avoided by storing only raw pointer ints in Gene objects, with actual Nim refs owning them.

### Error Handling
- Each shim function returns `gene_llm_error` enum + message buffer.
- Nim raises `new_exception(types.Exception, msg)` immediately; error text includes llama.cpp error code + context (e.g., “load_model: failed to mmap /tmp/foo.gguf: ENOENT”).
- `Session .infer` catches worker errors and re-raises on the caller thread, so Gene code can `catch *`.

### Build & Testing
- `tools/build_llm_runtime.sh` invoked from Nimble hook `task buildllm` to compile the shim and drop headers/libs under `build/llm/`.
- `nim c -r tests/test_llm_mock.nim` compiles with `-d:GENE_LLM_MOCK`, substituting the shim with a fake implementation that returns deterministic text (`"mock completion"`).
- Example `examples/llm_completion.gene` detects `GENE_LLM_MOCK` to skip real model loading; instructions in `docs/llm.md` explain how to download a small GGUF and run the sample.

## Follow-ups / Risks
- GPU acceleration flags differ per platform; docs must highlight how to rebuild the shim when enabling Metal/CUDA.
- Background worker introduces threading; need to audit for global state conflicts (llama.cpp contexts are not thread-safe per session—stick to one worker per session or guard with locks).
- Eventually we will revisit streaming callbacks once core API ships; design keeps queue/polling infrastructure so adding streaming later is incremental.
