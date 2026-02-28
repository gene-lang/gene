## 1. Build Profile Plumbing
- [x] 1.1 Extend `config.nims` with `GENE_PROFILE` mapping for `native` and `wasm-emscripten` (plus optional `wasm-wasi` placeholder).
- [x] 1.2 Add `gene_wasm` compile-time define usage in affected modules.
- [x] 1.3 Add `nimble wasm` task to build `web/gene_wasm.js` and `web/gene_wasm.wasm` via Emscripten.
- [x] 1.4 Add actionable failure text when `emcc` is missing.

## 2. WASM Entrypoint and Host ABI
- [x] 2.1 Add `src/gene_wasm.nim` exporting `gene_eval(code: cstring): cstring`.
- [x] 2.2 Add output/result capture behavior for `print`/`println` in wasm evaluation path.
- [x] 2.3 Add `src/gene/wasm_host_abi.nim` with wrappers for host clock/random/file functions.
- [x] 2.4 Route wasm mode time/random/file operations through host ABI wrappers.

## 3. Runtime Guardrails for Unsupported Features
- [x] 3.1 Guard thread APIs in wasm mode with deterministic `AIR.WASM.UNSUPPORTED` errors.
- [x] 3.2 Guard dynamic native extension loading in wasm mode with deterministic `AIR.WASM.UNSUPPORTED` errors.
- [x] 3.3 Guard process/shell and server-socket APIs in wasm mode with deterministic `AIR.WASM.UNSUPPORTED` errors.

## 4. Tests
- [x] 4.1 Add wasm smoke test for `gene_eval` basic execution path.
- [x] 4.2 Add tests that unsupported wasm features fail with stable code and feature name.
- [x] 4.3 Keep native tests green (no regression in existing behavior).

## 5. Documentation
- [x] 5.1 Add `docs/wasm.md` describing profile flags, prerequisites, and build/run workflow.
- [x] 5.2 Update `README.md` with wasm support scope and limitations.

## 6. Validation
- [x] 6.1 Run `openspec validate add-wasm-runtime-target --strict`.
- [x] 6.2 Run targeted native tests to confirm no regression.
- [x] 6.3 Run wasm build smoke (`nimble wasm`) on an environment with Emscripten installed.
