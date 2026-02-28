# Proposal: Add WASM Runtime Target for Gene VM

## Why

Goal: compile Gene itself to WebAssembly so the VM can run inside browser-hosted and other WASM environments.

Current `gene-old` runtime is tightly coupled to native OS facilities (threads, dynamic libraries, filesystem, process execution, native networking). That prevents a direct WASM build and requires a profile-driven runtime boundary.

## What Changes

- Add profile-based build configuration for native vs WASM targets (`GENE_PROFILE`, `gene_wasm` defines).
- Add a dedicated WASM build task (`nimble wasm`) using Emscripten with a stable exported ABI.
- Add a WASM entrypoint module that exports `gene_eval(code: cstring): cstring`.
- Add a WASM host ABI shim module for host-provided effects (`now`, `rand`, file existence/read/write/free).
- Route effectful runtime paths through host ABI when `gene_wasm` is enabled.
- Disable unsupported subsystems on WASM with deterministic runtime failures (threads, native extension loading, process/shell, server-side socket APIs).
- Add WASM smoke tests and docs for local build/run workflow.

## Impact

- Affected specs: `wasm-runtime-target`
- Affected code (expected):
  - `config.nims`
  - `gene.nimble`
  - `src/gene_wasm.nim` (new)
  - `src/gene/wasm_host_abi.nim` (new)
  - runtime/stdlib modules that currently call OS-only APIs directly
  - docs (`README.md`, `docs/wasm.md`)
  - test coverage for wasm smoke and unsupported-feature guards

- Platform/tooling impact:
  - Requires Emscripten (`emcc`) for `nimble wasm`
  - Native build/test workflow must remain unchanged
