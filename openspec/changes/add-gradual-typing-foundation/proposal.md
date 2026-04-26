## Why
Gene's gradual typing implementation already has descriptor IDs, runtime validation, and GIR persistence, but the coherence rules that keep those surfaces aligned are spread across current-state docs, source code, and historical proposals. Downstream milestone slices need one in-repo OpenSpec contract for verifier work, source/GIR parity, strict-nil semantics, and final validation.

## What Changes
- Add a new `gradual-typing` OpenSpec capability as an ADDED delta because no active spec currently owns the foundation contract.
- Define descriptor metadata invariants for every `TypeId` owner so invalid IDs cannot silently degrade to `Any` during source compilation or GIR loading.
- Require actionable `GENE_TYPE_METADATA_INVALID` diagnostics that identify phase, owner/path, invalid `TypeId`, descriptor-table length, and source/GIR paths.
- Specify source-compile verification, GIR-load verification, source/GIR parity, default nil compatibility, opt-in strict nil semantics, final foundation gate evidence, and deferred non-core tracks.
- Keep this change contract-only for S01; source verifier, GIR parity, strict-nil, and final-gate implementation are mapped to later slices.

## Impact
- Affected specs: `gradual-typing` (new)
- Affected docs: current gradual typing notes and status pages will link to the canonical foundation design in later S01 tasks.
- Affected implementation areas: type descriptor ownership, compiler/checker descriptor merge, runtime type validation, GIR serialization/loading, and CLI verification flows.
- Backward compatibility: default gradual typing remains permissive for existing nil-compatible code; strict nil is opt-in.
