## 1. Spec & API
- [x] 1.1 Review llama.cpp C API surface and document supported options for v1 (model path, context length, thread count).
- [x] 1.2 Finalize `genex/llm` Gene API signatures in spec deltas (`load_model`, `new_session`, `infer`, optional streaming callback).

## 2. Implementation
- [ ] 2.1 Add llama.cpp shim build (tools script + Nimble hooks) and expose C-friendly functions for load/session/infer.
- [ ] 2.2 Add Nim bindings + VM native registrations (lifetime management + background worker integration).
- [ ] 2.3 Implement Gene stdlib helpers / docs / examples relying on the new natives.

## 3. Testing & Docs
- [ ] 3.1 Add mock-backed Nim tests that exercise success & failure cases without loading real weights.
- [ ] 3.2 Add Gene example (`examples/llm_completion.gene`) plus README/docs update for setup instructions.
