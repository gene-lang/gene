## Context

Gene's runtime serializer already owns the canonical Gene-native text payload format through `gene/serdes/serialize` and `gene/serdes/deserialize`. Earlier filesystem-tree proposals added `write_tree` / `read_tree`, exploded directory markers, selector-driven separation, and lazy tree-backed values as a second public filesystem persistence model. That prior work is useful implementation prior art, but D072-D079 now supersede it as public contract: M012 must expose one filesystem serialization model and remove the old tree-serdes surface.

The fresh reader for this design is a Gene runtime/documentation contributor implementing S02-S06 after OpenSpec approval. After reading, they should know which public APIs are allowed, how serialized file references behave, which old APIs must be removed, and which failure modes must be tested.

This change is contract-first. S01 writes the OpenSpec contract and public documentation/gate artifacts only; runtime implementation is blocked until this proposal is approved.

## Goals / Non-Goals

- Goals:
  - Define the exact public filesystem serialization surface as `gene/serdes/write`, `read`, `read_file`, and `read_dir`.
  - Preserve `serialize` / `deserialize` as text payload APIs rather than filesystem persistence APIs.
  - Make nested file and directory references explicit in serialized text and dispatched by the deserializer with containing-file context.
  - Replace the old exploded tree abstraction with explicit file refs, directory refs, writer externalization, deterministic child names, and `read_dir` collection options.
  - Require fail-closed handling for unsafe paths, missing or invalid targets, malformed options, invalid directory targets, and cycles.
  - Require public cleanup and full implementation verification before M012 is complete.
- Non-Goals:
  - Implement runtime behavior in S01.
  - Preserve `read_tree` / `write_tree` as compatibility aliases.
  - Add binary serialization, global identity caching, automatic stale-file garbage collection, or cyclic/shared graph identity semantics.
  - Evaluate arbitrary Gene code found in serialized files while resolving file refs.

## Accepted Constraints

- D072: `read_tree` and `write_tree` are removed as supported public APIs and replaced by one filesystem model.
- D073: Serialized files refer to externalized sub-values with explicit `(gene/serdes/read_file ...)` and `(gene/serdes/read_dir ...)` forms.
- D074: The filesystem API surface is exactly `write`, `read`, `read_file`, and `read_dir`; `read` aliases `read_file`.
- D075: `write` supports selector-driven externalization and writes deterministic child files/directories, replacing selected sub-values with explicit refs.
- D076: Nested relative refs resolve against the containing serialized file; path escapes are rejected by default and deterministic child naming is required.
- D077: File refs deserialize eagerly by default; `^lazy true` returns a transparent cached lazy value.
- D078: `read_dir` supports configurable return shape and ordering for ordered arrays and keyed maps.
- D079: M012 must pass focused filesystem-serdes tests, old API removal assertions, GeneClaw storage smoke tests, OpenSpec strict validation, `nimble build`, and the full language testsuite before completion.

## Interface Alternatives Considered

### Alternative A: Keep tree-serdes and add wrappers

The public surface would keep `write_tree` and `read_tree`, then add `write`, `read`, `read_file`, and `read_dir` as wrappers or aliases. This maximizes short-term compatibility but leaves two names and two mental models in public docs. It violates D072 and R135 because users would still see tree-serdes as supported behavior.

### Alternative B: Manifest-backed filesystem bundles

The writer would store a top-level manifest that maps logical paths to payload files, while deserialization consults the manifest instead of embedding refs in parent files. This can centralize metadata but makes parent files less human-inspectable, creates another authoritative registry that can drift, and conflicts with R136's out-of-scope anti-registry constraint.

### Alternative C: Explicit refs in serialized Gene text

The writer stores normal serialized text in each `.gene` payload and represents externalized children in parent files as explicit `gene/serdes/read_file` or `gene/serdes/read_dir` forms. The deserializer recognizes those forms as serializer-owned refs and resolves them relative to the containing file. This keeps files inspectable, makes boundaries durable, and narrows the public API to the four accepted filesystem functions.

Recommendation: Alternative C is the accepted M012 direction. It preserves the useful tree-serdes ideas—selector-driven externalization, deterministic child names, lazy reads, and directory-backed collections—without preserving the old API or hidden exploded-tree abstraction.

## Decisions

### Decision: `serialize` and `deserialize` remain text payload APIs

`gene/serdes/serialize` SHALL continue to produce a Gene-native serialized text payload, and `gene/serdes/deserialize` SHALL continue to consume such text. They SHALL NOT become filesystem readers or writers. Filesystem persistence lives under `write`, `read`, `read_file`, and `read_dir`.

Rationale: This keeps the existing runtime serdes contract intact and avoids overloading text payload conversion with filesystem effects.

### Decision: Use explicit serializer-dispatched refs, not runtime evaluation

A serialized form whose head is `gene/serdes/read_file` or `gene/serdes/read_dir` SHALL be handled by the deserializer as a serializer-owned ref form when it appears in serialized payload input. Resolution uses the containing file's directory as context. The deserializer SHALL NOT evaluate arbitrary Gene runtime code or dispatch user-defined functions while resolving those refs.

Rationale: The durable format remains human-readable while keeping untrusted files from becoming code-execution inputs.

### Decision: Use `^externalize` for writer selectors

`gene/serdes/write` SHOULD use a selector option named `^externalize` for the set of sub-values to store outside the parent payload. The old `^separate` term belongs to tree-serdes prior art and should not be carried into the new public model unless implementation approval deliberately revisits the name.

Rationale: `externalize` describes the visible result: the selected value moves to a child file or directory and the parent contains an explicit ref. It also avoids making the new API look like a compatibility layer for `write_tree`.

### Decision: `read` is a convenience alias for `read_file`

`gene/serdes/read path` SHALL behave as `gene/serdes/read_file path` for a single root serialized file. Directory-backed collection reads remain explicit through `read_dir` so callers can choose shape and ordering.

Rationale: The common one-file read stays short while directory semantics remain visible.

### Decision: fail closed with path/context diagnostics

Unsafe paths, missing files, invalid serialized text, malformed ref options, invalid directory targets, and cycles SHALL fail with diagnostics that include the relevant path and containing-file/ref context. They SHALL NOT silently return `nil`.

Rationale: Durable storage bugs should be visible and actionable, especially for future agents debugging persisted state.

## Prior Art and Supersession

`add-filesystem-tree-serdes` and `add-filesystem-tree-lazy-loading` define useful mechanisms: selector-controlled child storage, deterministic array child IDs, marker-based directory decoding, lazy materialization, and metadata-only navigation. M012 may mine those implementations and tests, especially the unsafe child-ID gotcha around `_genearray.gene`, but their public `read_tree` / `write_tree` API and exploded-tree abstraction are superseded.

`update-runtime-serdes-hooks` remains relevant for the text payload serializer. The filesystem model must preserve its canonical text behavior, typed refs, and hook semantics unless a later accepted change explicitly modifies them.

## Risks / Trade-offs

- Breaking old public APIs simplifies the long-term model but requires public docs and tests to remove old examples rather than preserve compatibility snippets.
- Explicit refs make files inspectable and portable, but the deserializer must distinguish serializer-owned refs from normal data safely and predictably.
- Container-relative path resolution improves portability and safety, but implementations must carry containing-file context through nested deserialization.
- Lazy file refs improve large-state performance, but transparent lazy values can leak complexity into runtime access paths; S03 must verify caching, error timing, and normal-access behavior for file refs. Directory refs remain eager in the delivered contract unless a future change implements and tests directory-lazy behavior.
- Deterministic child naming improves diffs and keyed storage, but generated names must treat selector/key-derived IDs as untrusted and reject separator, absolute, traversal, and empty child IDs before joining paths.

## Migration Plan

1. S01: approve this OpenSpec contract and public spec/gate artifacts.
2. S02: implement `read_file` refs, `read` alias behavior, containing-file context, and fail-closed path/target validation.
3. S03: implement `read_dir`, `^shape array|map`, `^order name`, eager directory defaults, and `^lazy true` transparent lazy refs for `read_file` / `read`.
4. S04: implement `write` externalization with deterministic child naming and explicit refs in parent files.
5. S05: remove `read_tree` / `write_tree` public API and old tree-serdes implementation paths while preserving canonical text serdes behavior.
6. S06: migrate GeneClaw storage helpers, public docs, examples, and full verification gates.

## Open Questions

- Exact diagnostic names/messages may be refined during implementation, but they must include path and containing-file/ref context.
- Exact deterministic child-name algorithms may be refined during implementation, but they must be stable, safe before path joining, and covered by focused tests.
- `read_dir` currently guarantees deterministic name ordering only. Creation-time ordering and directory-lazy materialization need a separate future proposal plus focused implementation tests before they can become public contract.
