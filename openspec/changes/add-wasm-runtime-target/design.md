# Design: WASM Runtime Target for Gene VM

## Context

A sibling Gene implementation already compiles to WASM by combining:

- compile-time profile defines (`gene_wasm`, `gene_wasm_emscripten`, `gene_wasm_wasi`),
- a dedicated wasm entrypoint (`gene_eval` export),
- host ABI shims for effectful operations,
- explicit runtime guards for unsupported native-only features.

`gene-old` currently lacks this boundary and assumes native OS/runtime services in core paths.

## Goals

- Compile the Gene VM/runtime to WASM (Emscripten first) without rewriting core language semantics.
- Keep native build behavior unchanged.
- Make unsupported operations deterministic and explicit in WASM mode.
- Provide a minimal stable host ABI and exported evaluation entrypoint.

## Non-Goals

- Full stdlib parity in WASM on first milestone.
- Native extensions (`dlopen`) support in WASM.
- OS thread pool semantics in WASM.
- Replacing the existing native CLI with a browser CLI.

## Decisions

### 1. Build Profiles and Defines

Use `GENE_PROFILE` in `config.nims` to define runtime mode:

- `native` -> `gene_native`
- `wasm-emscripten` -> `gene_wasm`, `gene_wasm_emscripten`
- optional future `wasm-wasi` -> `gene_wasm`, `gene_wasm_wasi`

Threads are disabled in WASM profiles.

### 2. Emscripten Build Contract

Add `nimble wasm` task that compiles a dedicated wasm entrypoint module using:

- `--cpu:wasm32`
- `--os:linux`
- `-d:emscripten`
- `--threads:off`
- `--cc:clang --clang.exe:emcc --clang.linkerexe:emcc`

Decision rationale: local Nim toolchains do not expose `--os:emscripten`; this route is proven in sibling implementation.

### 3. WASM Entrypoint ABI

Add `src/gene_wasm.nim` exporting:

- `gene_eval(code: cstring): cstring`

The entrypoint parses, compiles, executes, and returns output/result text. It is the minimal host-facing ABI for browser integration.

### 4. Host Effect Boundary

Add `src/gene/wasm_host_abi.nim` with host-imported functions (and non-wasm fallbacks):

- `gene_host_now`
- `gene_host_rand`
- `gene_host_file_exists`
- `gene_host_read_file`
- `gene_host_write_file`
- `gene_host_free`

Runtime and stdlib effect paths (time/random/file operations) are routed through these wrappers under `gene_wasm`.

### 5. Unsupported Feature Contract

In `gene_wasm` mode, runtime features with no valid WASM mapping SHALL fail deterministically with a stable code (`AIR.WASM.UNSUPPORTED`) and feature identifier:

- thread spawning/thread messaging APIs
- native extension loading (`native/load`, dynamic import extensions)
- process/shell execution
- server-side socket APIs (e.g., HTTP server)

### 6. Native Non-Regression

All `gene_wasm` guards are compile-time isolated so native builds continue to include current functionality.

## Risks / Trade-offs

- WASM functionality is intentionally reduced at first milestone.
- Some existing tests will need mode-aware behavior.
- Host ABI introduces integration coupling that must be versioned carefully.

Mitigations:

- explicit unsupported diagnostics,
- wasm-specific smoke tests,
- clear documentation of supported/unsupported surface.

## Migration Plan

1. Add profile/build plumbing and wasm entrypoint scaffolding.
2. Add host ABI wrappers and route effectful operations.
3. Add unsupported-feature guards with stable diagnostics.
4. Add wasm smoke tests and docs.
5. Validate native tests remain unchanged.

## Open Questions

- Should initial scope include WASI build artifacts, or defer to Emscripten-first only?
A: defer to Emscripten-first only.
- What subset of module/package loading is guaranteed in wasm mode (host-fed only vs file-backed via ABI)?
A: host-fed only.
