## Reader and Post-Read Action

Reader: a Gene type-system implementer or reviewer who was not present for M006 planning.

Post-read action: implement or review S02-S05 gradual typing foundation work without relying on downloaded research notes or historical proposal archaeology.

## Context

Gene already has a gradual-first type pipeline: source is parsed, type checked in non-strict mode, compiled with descriptor metadata, optionally serialized to GIR, and executed with runtime boundary validation when type checking is enabled. The core metadata shape is descriptor-first: `TypeId` references index a `TypeDesc` table, and those references are attached to function matchers, scope trackers, class property metadata, runtime type values, compilation units, module type registries, and GIR payloads.

The current implementation still has coherence gaps. Some invalid descriptor references can fall back to `Any`, and GIR loading restores descriptor tables before later runtime paths consume them. That behavior is acceptable as migration history but not as the foundation contract for downstream verifier and parity work.

## Goals

- Establish one canonical OpenSpec and documentation surface for the gradual typing foundation.
- Make descriptor metadata invalid states fail loudly before execution or import-time type use.
- Preserve default gradual typing compatibility, including existing nil-compatible behavior.
- Define opt-in strict nil semantics without making strict nil the default language mode.
- Give reviewers a final gate that proves source compile, cached GIR, nil modes, diagnostics, and documentation all agree.

## Non-Goals

- No runtime verifier implementation is delivered by S01.
- No historical OpenSpec proposals are edited or treated as current truth.
- No full static-only mode, generic class system, bounds/constraints, monomorphization, or deep collection element enforcement is required by this foundation.
- No public split between enum ADTs and private checker bridge machinery is introduced.

## Foundation Contract

### Descriptor metadata invariant

Every typed metadata owner that stores a `TypeId` MUST either store `NO_TYPE_ID` for an intentionally untyped slot or store an ID that indexes the descriptor table visible to that owner. Compound descriptors MUST recursively obey the same rule for applied arguments, union members, function parameters, and function returns.

The important owners are:

- Function and block matcher parameter/return metadata.
- Scope tracker and scope snapshot type expectation metadata.
- Class and interface property metadata.
- Runtime type values and type aliases.
- Compilation-unit descriptor tables, module type registries, and module type trees.
- GIR-loaded compilation units and imported module metadata.

### Verification phases

S02 owns source-compile verification. It should run after checker descriptors are merged into compiler output and before successful compilation output is accepted or saved.

S03 owns GIR verification and source/GIR parity. GIR verification should run after GIR metadata is read and before the loaded unit is exposed to import, execution, or runtime validation. Parity should prove source-compiled and GIR-loaded programs use equivalent descriptor metadata and runtime type behavior.

S04 owns opt-in strict nil. Default mode remains gradual-compatible. Strict nil should reject `nil` at typed boundaries unless the expected type is `Any`, `Nil`, or a union containing `Nil`.

S05 owns the final foundation gate. It should combine source verifier evidence, GIR verifier evidence, parity checks, strict nil checks, default nil compatibility checks, documentation links, and OpenSpec validation.

### Diagnostic contract

Invalid metadata MUST produce `GENE_TYPE_METADATA_INVALID`. The message or structured diagnostic payload MUST include:

- `phase`: at least `source-compile`, `gir-load`, or `source-gir-parity`.
- `owner/path`: the metadata owner and nested path to the bad reference.
- `invalid TypeId`: the concrete invalid ID.
- `descriptor-table length`: the table size used for validation.
- `source path`: the source file when known.
- `GIR path`: the GIR file when known or when parity is being checked.

The verifier MUST NOT silently coerce invalid metadata to `Any`; silent fallback is the failure mode this foundation removes.

## Risks and Mitigations

- Risk: stricter metadata validation exposes old cache files or migration artifacts. Mitigation: fail before execution with source/GIR paths so users can rebuild caches.
- Risk: strict nil could break existing gradual code. Mitigation: keep strict nil opt-in and preserve default nil-compatible behavior.
- Risk: diagnostics become too broad to act on. Mitigation: require phase, owner/path, invalid ID, table length, and path metadata in every invalid-metadata diagnostic.

## Reader-Test Pass

A cold reader can identify what S02, S03, S04, and S05 must implement, what S01 intentionally does not implement, which diagnostics must be observable, and which type-system tracks remain deferred. The design avoids relying on historical proposal files as the source of truth.
