## 1. Spec And Design
- [x] 1.1 Add OpenSpec delta for explicit adapter field mappings in external `implement` bodies.
- [x] 1.2 Document direct wrapped-field mapping syntax, lookup precedence, assignment semantics, readonly behavior, method-like accessor behavior, and adapter-owned state access.
- [x] 1.3 Document typed adapter-owned field declarations, direct owned-field access inside adapter bodies, the rule that owned field names must not conflict with target interface fields, and the boundary that normal public slash access exposes only the implemented interface surface.
- [x] 1.4 Document the wrapped-value pseudo-member rename from `/_genevalue` to `/_wrapped`, including that `wrapped` means the value wrapped by the external adapter.
- [x] 1.5 Document current-runtime implementation constraints: `^from` uses rename/field-forwarding metadata, accessor mappings need separate getter/setter representation, interface-dependent checks occur at implementation registration when static metadata is unavailable, failed direct writes must not fall back to adapter-owned state, `/_geneinternal` should be retired from the public adapter-owned-state API, and `/_genevalue` should be retired from the public wrapped-value API.
- [x] 1.6 Validate the OpenSpec change with `openspec validate add-adapter-field-mappings --strict`.
- [x] 1.7 Review and approve the OpenSpec proposal before implementation begins.

Implementation gate: do not start section 2 until the OpenSpec proposal is reviewed and approved. The remaining tasks are intentionally left unchecked until runtime behavior, tests, and docs provide direct evidence.

## 2. Implementation
Suggested order after approval: land metadata and readonly foundations first (`2.7`, `2.9`, `2.10`), then compile/register field forms and diagnostics (`2.1`-`2.6`), then runtime lookup/write/pseudo-member behavior (`2.11`-`2.17`), and finally compatibility preservation (`2.18`).

- [x] 2.1 Extend external `implement` body parsing/lowering to accept direct `(field name ^from wrapped_field)` mappings, accessor `(field name (get [] ...) [(set [v] ...)])` mappings, and typed adapter-owned field declarations `(field owned_name TypeExpr)`.
- [x] 2.2 Reject malformed adapter field mappings with targeted diagnostics, including missing accessor getter, invalid accessor arity, invalid `^from` target shape, mixed `^from` plus accessor forms, and unknown accessor forms.
- [x] 2.3 Reject mappings for fields not declared by the target interface during implementation registration, and earlier in compiler/checker validation when interface metadata is statically available.
- [x] 2.4 Reject adapter-owned field declarations whose names conflict with fields declared by the target interface, using compiler/checker diagnostics when possible and fail-closed implementation-registration diagnostics otherwise.
- [x] 2.5 Reject duplicate adapter-owned field declarations and duplicate mappings for the same interface field.
- [x] 2.6 Reject `set` accessors for readonly interface fields during implementation registration, and earlier in compiler/checker validation when possible.
- [x] 2.7 Fix interface `(field ... ^readonly true)` lowering so field declarations preserve readonly metadata.
- [x] 2.8 Represent direct `^from` mappings as adapter field-forwarding metadata or equivalent fast-path descriptors, not as generated Gene getter/setter methods.
- [x] 2.9 Add an accessor mapping representation with separate getter and optional setter slots; use a distinct mapping kind such as `AmkAccessor`, or document an equivalent non-overloaded representation during implementation.
- [x] 2.10 Add adapter-owned field metadata, such as an `owned_fields` registry on implementations, and direct owned-field read/write support only while executing adapter ctor, method, getter, and setter bodies.
- [x] 2.11 Add `/_wrapped` as the adapter pseudo-member for the wrapped value inside adapter implementation bodies.
- [x] 2.12 Remove or retire the public `/_genevalue` adapter pseudo-member unless another accepted spec still owns it.
- [x] 2.13 Ensure adapter-owned fields are not exposed through normal public member lookup on the adapted interface surface unless an explicit mapping or method exposes them.
- [x] 2.14 Wire adapter field reads to direct `^from` mappings first, accessor `get` mappings second, then same-name wrapped-value fallback.
- [x] 2.15 Wire adapter field writes to readonly/direct-forward/accessor-set/accessor-get-only/fallback behavior.
- [x] 2.16 Reject failed direct `^from` writes with an adapter field diagnostic instead of silently falling back to adapter-owned state.
- [x] 2.17 Remove or retire the public `/_geneinternal` adapter state pseudo-member and related `VkAdapterInternal` surface unless another accepted spec still owns it.
- [x] 2.18 Preserve existing method adapter behavior, partial external adapter registration, and same-name fallback behavior for unmapped interface fields.

## 3. Tests And Docs
Run tests as behavior lands, not only at the end: add focused failing coverage for each implementation slice before marking its corresponding task complete, then run the focused adapter/interface suite and project-level gate in `3.14`.

- [x] 3.1 Add tests for direct `^from` adapter field reads and writes, including renamed wrapped fields.
- [x] 3.2 Add tests proving direct `^from` mappings do not expose or require implicit `get`/`set` methods.
- [x] 3.3 Add tests for computed accessor field reads and writes through `get`/`set`.
- [x] 3.4 Add tests for declared adapter-owned fields initialized by constructors and accessed directly in adapter methods/accessors.
- [x] 3.5 Add tests proving adapter-owned fields are not visible through normal public slash access on the adapted interface unless explicitly exposed.
- [x] 3.6 Add tests for adapter-owned field/interface-field name conflicts and duplicate adapter-owned fields.
- [x] 3.7 Add tests for readonly interface fields, direct readonly mappings, and get-only accessor fields rejecting writes.
- [x] 3.8 Add tests proving `(field ... ^readonly true)` preserves readonly metadata.
- [x] 3.9 Add tests for malformed mapping diagnostics, duplicate adapter field mappings, unknown interface fields, readonly setter registration diagnostics, and failed direct write diagnostics.
- [x] 3.10 Update existing `_geneinternal` tests to the new direct owned-field surface or remove them if no accepted spec still covers `_geneinternal`.
- [x] 3.11 Update existing `_genevalue` tests and docs to use `/_wrapped`, or remove legacy coverage if no accepted spec still covers `_genevalue`.
- [x] 3.12 Update `spec/07-oop.md` and `docs/adapter-design.md` with the accepted direct/accessor/owned-field adapter surface.
- [x] 3.13 Add or preserve coverage for partial external adapter registration, including unmapped interface fields using same-name fallback or failing at access when unavailable.
- [x] 3.14 Run focused interface/adapter verification (`nim c -r tests/test_adapter.nim`, `nim c -r tests/integration/test_adapter.nim`, and `./testsuite/run_tests.sh`) plus `nimble test` before marking implementation complete.
