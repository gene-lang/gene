# Design: Stable Native Extension ABI With Compatibility Loader

## Context

Current extension loading in `gene-old` is mixed:
- VM has a dynamic loader (`dlopen` + exported symbols),
- but also statically imports several `genex/*` modules as a fallback,
- and extension entrypoints are legacy (`set_globals`, `init`) without ABI version negotiation.

This produces coupling and makes binary compatibility expectations unclear.

## Goals

- Define one canonical, versioned extension host ABI.
- Preserve existing Gene-level extension usage syntax.
- Preserve existing extension functionality during migration.
- Remove VM static fallback imports once dynamic loading is complete.
- Make extension load failures deterministic and diagnosable.

## Non-Goals

- Changing Gene import syntax or adding new user syntax for extension loading.
- Reworking non-extension module/package semantics in this change.
- Forcing immediate removal of legacy extension entrypoints in one step.

## Decisions

### 1. Canonical Entry Contract

Introduce a stable host ABI module (for example `src/gene/vm/extension_abi.nim`) with:
- ABI version constant,
- host API struct,
- C-callable extension init symbol type (`gene_init`).

Loader contract:
- Attempt `gene_init` first.
- Validate ABI version.
- Register/publish extension namespace through host API callbacks/context.

### 2. Compatibility Path

To avoid functionality loss, loader also supports legacy exports:
- `set_globals(vm)` then `init(vm): Namespace`.

This path remains during migration and can be removed in a later explicit change.

### 3. No User Syntax Changes

The following remain unchanged:
- `import <symbols> from "<path>" ^^native`
- `genex/<module>/...` access
- internal/direct `load_extension(path)` usage in VM/tests

Only runtime plumbing changes.

### 4. Built-in Genex Availability Contract

Static imports in `vm.nim` are removed only when equivalent dynamic-loading behavior is guaranteed for those modules.

Guarantee:
- if an extension was available before the change, it remains available after the change under the same Gene call sites.
- failures become explicit extension-load errors instead of silent NIL fallthrough.

### 5. Diagnostics and Error Surface

Define stable extension-load diagnostics:
- `GENE.EXT.LOAD_FAILED`
- `GENE.EXT.SYMBOL_MISSING`
- `GENE.EXT.ABI_MISMATCH`
- `GENE.EXT.INIT_FAILED`

Errors include attempted path and extension/module name when known.

## Trade-offs

- Dual-path loader adds temporary complexity.
- Full migration of all statically imported `genex/*` modules may require staged updates.

This is preferable to breaking existing extension behavior.

## Migration Plan

1. Add ABI definitions and host registration context.
2. Upgrade loader to new ABI + legacy fallback path.
3. Migrate core `genex/*` modules to export `gene_init` (or adapter wrappers).
4. Remove VM static extension imports once parity is verified.
5. Update docs and tests; enforce extension regression suite.

## Open Questions

- Which core `genex/*` modules are required in phase 1 for static-import removal gate?
A: llm and ai modules should be moved to dynamic loading.
- Should legacy loader fallback be controlled by a build flag once migration is complete?
A: remove legacy fallback path.
