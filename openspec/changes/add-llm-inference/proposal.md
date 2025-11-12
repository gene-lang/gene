# add-llm-inference Proposal

## Why
Gene currently lacks any built-in access to large language model inference. Examples and future automation features will need a first-class API to load a local model (e.g., GGUF via llama.cpp), create inference sessions, and stream completions. Without a clear spec we cannot align VM, native extensions, and Gene stdlib on an API surface or test plan.

## What Changes
- Introduce a `genex/llm` capability that wraps a proven C backend (llama.cpp) for offline inference.
- Provide Gene-facing primitives to load a model, create sessions/contexts, and run inference synchronously or via async helpers.
- Ensure the VM can manage the lifetime of native model/session handles (finalizers, ref-count integration).
- Document build/runtime requirements (model formats, GPU flags, env vars) so contributors can reproduce results.
- Provide coverage (unit + Gene example) that exercises the new API with a mock backend so CI does not require a giant model.

## Scope / Guardrails
- Target llama.cpp C API initially; future engines can extend this capability but are out of scope.
- Focus on local inference (no network calls) and a single completion-style interface; fine-grained features like tool calling or JSON mode are follow-ups.
- Keep the spec small enough to implement without reworking the VM dispatcher (no instruction changes expected).

## Success Metrics
- `examples/llm_completion.gene` can load a small GGUF, prompt, and print a completion without crashes.
- Mocked Nim tests cover happy path + failure cases (bad path, unloaded session, timeout) without relying on real models.
- Build docs specify how to compile/link the llama.cpp shim for macOS (and note Linux steps if trivial).

## Risks / Mitigations
- **Large binaries**: mitigate via optional build flag and documentation for fetching weights.
- **Long-running inference**: use background worker / Async to keep VM responsive.
- **API churn**: spec the core primitives up front (`load_model`, `new_session`, `infer`) to keep signatures stable.

## Open Questions
1. Do we need streaming tokens in v1? (default assumption: optional, provide simple callback hook.)
A: not in v1
2. Should the shim live under `tools/llama_runtime/` or reuse an external install? (leaning toward vendoring a minimal subset.)
A: vendor as a git submodule under tools/llama_cpp or other runtime
3. How should errors propagate—Gene exceptions wrapping llama error codes vs string statuses?
A: Gene exceptions
