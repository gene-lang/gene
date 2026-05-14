## Why

Gene interfaces can declare fields, but external adapter implementations currently cannot explicitly provide those fields. This makes interface fields much less useful than interface methods: an adapter can bridge behavior, but not shape, unless the wrapped value already happens to expose same-name fields.

External adapters need a first-class way to satisfy interface field requirements without pretending that adapter field mappings are class storage declarations or forcing every simple field rename through an implicit method call. When adapters need their own supplemental state, that state should be declared and accessed directly instead of routed through a special `/_geneinternal` pseudo-member.

## What Changes

- Add explicit field mapping forms inside external `implement` bodies.
- Define adapter field mappings as interface-property implementations, not adapter storage declarations.
- Support two interface-field mapping kinds:
  - optimized direct wrapped-field mappings such as `(field name ^from label)`;
  - method-like accessor mappings such as `(field name (get [] ...) [(set [v] ...)])`.
- Support explicit adapter-owned field declarations for supplemental adapter state, such as `(field stored_birth_year Int)`, accessed directly in adapter implementation bodies as `/stored_birth_year`.
- **BREAKING** Rename the adapter wrapped-value access path from `/_genevalue` to `/_wrapped` so adapter bodies can refer to the wrapped value by role instead of implementation detail.
- Require adapter-owned field names to be disjoint from fields declared by the target interface; conflicts are compile/check diagnostics when statically known and fail-closed implementation-registration diagnostics otherwise.
- Require direct wrapped-field mappings to use direct adapter member forwarding rather than hidden getter/setter methods.
- Add an accessor mapping representation with separate getter and optional setter slots.
- Preserve current same-name fallback when no explicit adapter field mapping exists.
- Preserve interface `^readonly true` as an adapter-write rejection boundary, including for canonical `(field ...)` interface declarations.
- Clarify that interface-resolution-dependent failures are implementation-registration/runtime diagnostics when the compiler/checker cannot statically resolve the interface metadata.
- Reject failed direct `^from` writes with a clear diagnostic instead of silently falling back to adapter-owned state.
- **BREAKING** Remove `/_geneinternal` from the new adapter-owned-state design; owned adapter fields are the direct state surface.
- Defer additional convenience shorthands beyond `^from` until the direct, accessor, and owned-field forms are implemented and tested.

## Review Focus

Please review and approve these decisions before implementation:

- The external adapter `field` keyword is intentionally shape-based: `^from` for direct interface-field mappings, `get`/`set` blocks for accessor mappings, and typed second operands for adapter-owned state declarations.
- Direct `^from` mappings are semantic fast paths, not shorthand for generated accessor methods.
- Adapter-owned state is private implementation state and is not exposed through normal public slash access unless a mapping or method exposes it.
- `/_wrapped` replaces the public wrapped-value pseudo-member role; `/_genevalue` and `/_geneinternal` are retired from the new public adapter API unless another accepted spec explicitly keeps them.
- Current OpenSpec state has no accepted specs (`openspec list --specs` reports none), so reviewers should treat `_genevalue`/`_geneinternal` preservation as requiring an explicit counter-spec before implementation.
- Interface-dependent validation is fail-closed at implementation registration/runtime when static interface metadata is unavailable.
- Partial external adapter conformance remains allowed; this change only adds explicit field-mapping behavior and diagnostics for declared mappings/owned fields.

## Migration Notes

- Replace adapter-body reads and method calls through `/_genevalue` with `/_wrapped`.
- Replace `/_geneinternal/foo` supplemental state with declared adapter-owned fields such as `(field foo Type)` and direct adapter-body access through `/foo`.
- Expose adapter-owned state to consumers only through an explicit interface field mapping or method; normal public slash access remains limited to the implemented interface surface.
- Update existing `_genevalue` and `_geneinternal` tests to assert the new `/_wrapped` and declared owned-field behavior, or remove legacy coverage if no accepted spec still owns those pseudo-members.

## Completion Criteria

- OpenSpec validation passes for `add-adapter-field-mappings`.
- Runtime supports direct, accessor, and owned-field forms with the lookup/write precedence described in the spec delta.
- Readonly interface field metadata is preserved for canonical `(field ... ^readonly true)` declarations.
- Legacy adapter method behavior and same-name wrapped-field fallback continue to pass.
- Partial external adapter registration remains allowed for unmapped interface fields; unresolved fields fail when accessed if same-name fallback cannot resolve them.
- Focused tests cover positive behavior, malformed/duplicate/conflict diagnostics, readonly/write failures, pseudo-member retirement, and docs examples.
- `spec/07-oop.md` and `docs/adapter-design.md` are updated to match the implemented adapter field surface.

## Pre-Implementation Baseline

The current adapter baseline passed before implementation work began:

- `nim c -r tests/test_adapter.nim`
- `nim c -r tests/integration/test_adapter.nim`
- `./testsuite/run_tests.sh 07-oop/interfaces/1_interfaces_and_adapters.gene 07-oop/interfaces/2_adapter.gene`

## Impact

- Affected specs: `object-model`
- Affected docs: `spec/07-oop.md`, `docs/adapter-design.md`
- Affected code:
  - interface/adapter parser and compiler handling for `implement ... for ...` bodies
  - interface field declaration lowering for `^readonly`
  - adapter-owned field declaration metadata and direct field access inside adapter implementation bodies
  - wrapped-value access path rename from `/_genevalue` to `/_wrapped`
  - adapter member lookup and assignment dispatch
  - optimized adapter field-forwarding descriptors for wrapped-value fields
  - adapter accessor execution for computed/owned-state mappings
  - removal or retirement of the public `/_geneinternal` adapter state surface
  - adapter mapping representation, likely adding an accessor mapping kind separate from one-function computed mappings
  - interface/adapter tests under `testsuite/07-oop/interfaces/`
