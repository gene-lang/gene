# Proposal: Stabilize Native Extension ABI Without User-Facing Syntax Changes

## Why

`gene-old` currently has partial dynamic extension loading, but extension contracts are not stable and VM startup still statically imports multiple `genex/*` modules as a fallback. This keeps extension behavior coupled to the main binary and blocks a clean third-party extension story.

We need a stable, versioned ABI for native extensions while preserving current language usage and existing extension functionality.

## What Changes

- Define a versioned native extension host ABI for `gene-old` with a single C-callable entrypoint (`gene_init`).
- Keep extension loading syntax unchanged for Gene users:
  - `import ... ^^native`
  - `genex/<module>/...` resolution
  - VM/internal `load_extension(path)` behavior
- Keep extension author ergonomics unchanged for existing modules by migrating them to the new ABI without changing user-facing load syntax.
- Remove VM-level static genex fallback imports once corresponding modules are dynamic-load ready.
- Strengthen extension load diagnostics (missing library, missing entrypoint, ABI mismatch, init failure) with deterministic error codes/messages.
- Update extension docs/tests/build flow so dynamic extension behavior is verified end-to-end.

## Impact

- Affected specs: `native-extensions` (new)
- Affected code:
  - `src/gene/vm/extension.nim`
  - `src/gene/vm.nim`
  - `src/gene/vm/module.nim`
  - `src/gene/extension/*` (boilerplate/header/C API where applicable)
  - `src/genex/*` modules currently relying on static registration
  - `gene.nimble` extension build tasks
  - extension-related tests/docs
- Risk: medium (cross-cutting runtime/bootstrap behavior)
- Mitigation:
  - compatibility loader path for legacy extensions
  - explicit ABI version checks
  - regression tests for existing `genex/*` usage and native import forms
