# Adapter Field Mappings Design

## Context

Current Gene docs distinguish interfaces as the visible face and adapters as the mechanism that maps a wrapped value to that face. Interfaces can declare fields:

```gene
(interface Readable
  (field name String)
  (method read [] -> String))
```

Inline implementations can satisfy those fields naturally because the class owns storage. External adapters can currently implement methods and initialize adapter-owned state with `ctor`, but the state path uses the special `/_geneinternal` pseudo-member and there is no direct field mapping form for interface fields. That leaves four unsatisfying options:

1. require the wrapped value to expose same-name fields,
2. model fields as public methods,
3. treat interface field mappings as implicit storage,
4. expose adapter-owned state through a special pseudo-member separate from normal field access.

The chosen design separates the concepts explicitly:

- adapter field mappings implement interface-visible fields;
- adapter-owned fields are declared state on the adapter itself and accessed directly in adapter implementation bodies;
- direct `^from` mappings get a fast path to wrapped-value fields;
- accessor blocks remain available for computed mappings or mappings backed by declared adapter-owned fields.

## Goals

- Let external adapters satisfy interface-declared fields explicitly.
- Preserve the conceptual split between interface-visible properties and adapter-owned storage.
- Allow adapter fields to be renamed, computed, or backed by explicitly declared adapter-owned state.
- Optimize the common case where an interface field maps directly to a wrapped value's field.
- Replace the new-design need for `/_geneinternal` with direct adapter-owned field access.
- Rename the wrapped-value access path to `/_wrapped`.
- Keep same-name fallback for compatibility and simple adapters.
- Make read/write behavior obvious at the source level.
- Reject ambiguous owned-field/interface-field name conflicts.

## Non-Goals

- Do not make adapter field mappings allocate storage implicitly.
- Do not lower direct wrapped-field mappings to hidden getter/setter methods.
- Do not expose `get` or `set` accessors as public methods on the adapted value.
- Do not keep `/_geneinternal` as the supported adapter-owned-state API for this design.
- Do not keep `/_genevalue` as the preferred wrapped-value access API for this design.
- Do not add additional shorthand forms beyond `^from` in the first change.
- Do not add interface default fields or default method bodies.
- Do not change broader interface field type-enforcement semantics beyond the existing runtime/checker behavior.
- Do not require eager full-adapter conformance checks; partial adapter behavior remains a supported Beta boundary unless a later strict-conformance change revisits it.

## Syntax

External adapter implementations may include three field-related forms.

### Direct wrapped-field mapping

Use this when the interface field maps directly to a wrapped value field/member:

```gene
(implement Readable for DataBuffer
  (field name ^from label)

  (method read []
    (/_wrapped .get_data)))
```

`(field name ^from label)` means:

- the interface field is `name`;
- the wrapped value member is `label`;
- reads of `adapted/name` directly read `/_wrapped/label` through adapter forwarding;
- writes to `adapted/name` directly write `/_wrapped/label` when the interface field is writable;
- no implicit getter/setter method or callable wrapper is created for the mapping.

The `^from` target is a member name, not an arbitrary expression. Direct mapping is the optimized path for renames and simple wrapped-field projection.

### Accessor mapping

Use this when the interface field is computed or backed by adapter-owned state:

```gene
(implement Readable for DataBuffer
  (field cached_label String)

  (ctor [label]
    (/cached_label = label))

  (field name
    (get [] /cached_label)
    (set [v] (/cached_label = v)))

  (field closed
    (get [] /_wrapped/closed))

  (method read []
    (/_wrapped .get_data)))
```

Accessor mappings are method-like blocks with argument lists and body expressions, but they are not public methods:

- `(get [] expr...)` is required for accessor mappings.
- `(set [value] expr...)` is optional.
- `get` takes no parameters.
- `set` takes exactly one parameter.
- `get` and `set` are invoked by slash field access/assignment, not dot method dispatch.
- `get` and `set` are not visible as members named `get` or `set`.
- The adapter field mapping does not declare storage and does not declare a separate type; the interface field remains the visible contract.

Inside accessor bodies, `/_wrapped` is the explicit wrapped-value access path. Adapter-owned state is accessed by direct slash field syntax using declared owned field names, such as `/cached_label`. The name `wrapped` is intentionally role-based: it means "the value wrapped by this external adapter" and is not an adapter-owned field.

### Adapter-owned field declaration

Use a typed field declaration inside an external adapter implementation when the adapter needs its own supplemental state:

```gene
(implement Ageable for Int
  (field stored_birth_year Int)

  (ctor [birth_year]
    (/stored_birth_year = birth_year))

  (field birth_year
    (get [] /stored_birth_year))

  (method age []
    (/_wrapped - /stored_birth_year)))
```

A typed adapter-owned field declaration:

- declares state owned by the adapter instance;
- does not implement an interface field;
- is not visible through the adapted interface unless exposed by an explicit field mapping or method;
- is accessed directly inside adapter implementation bodies as `/field_name`;
- must not use a name declared as a field on the target interface.

A `field` form in an external `implement` body is interpreted by shape:

- `(field interface_name ^from wrapped_name)` is a direct interface-field mapping;
- `(field interface_name (get [] ...) [(set [v] ...)])` is an accessor interface-field mapping;
- `(field owned_name TypeExpr)` is an adapter-owned field declaration.

An accessor mapping is recognized by child blocks after the field name. When a `field` form contains child blocks after the name, each block head must be the literal symbol `get` or `set`; any other block head is diagnosed as an unknown accessor form rather than treated as a type expression. A valid accessor mapping still requires a `get` block, and duplicate `get` or `set` blocks are malformed. A two-child `field` form whose second child is not an accessor block is treated as the `TypeExpr` of an adapter-owned field declaration.

Typed adapter-owned fields and interface field mappings share the `field` keyword intentionally, but they have different roles. Names that would make those roles ambiguous are rejected: an owned-field declaration may not reuse an interface field name, and an interface field may not be implemented by relying on an owned field with the same name.

## Semantics

### Lookup

For an external adapter field read from the adapted interface surface:

1. If the external `implement` body defines a direct `^from` field mapping for the interface field, read the mapped member from the wrapped value using adapter member forwarding.
2. If it defines an accessor mapping, evaluate its `get` accessor.
3. Otherwise, fall back to the current same-name member behavior on the wrapped value.
4. If none of those paths exist, fail at field access with a clear adapter/interface field diagnostic.

Adapter-owned fields do not participate in interface field lookup merely because they exist. They are visible only while executing adapter implementation bodies (`ctor`, `method`, `get`, and `set`) through direct owned-field access, and become visible externally only when an explicit interface mapping or method exposes them.

Normal public slash access on an adapted value must match the implemented interface surface. Debug or introspection access to private adapter-owned fields, if needed later, should be a separate explicit debug/introspection API and is out of scope for this change.

Direct `^from` mappings should be represented in implementation as mapping descriptors or equivalent fast-path metadata, not as generated Gene functions.

### Assignment

For an external adapter field write through the adapted interface surface:

1. If the interface field is declared `^readonly true`, reject the write through the adapter.
2. If the field has a direct `^from` mapping, write the assigned value to the mapped wrapped-value member when wrapped-value member assignment is supported.
3. If the wrapped-value member cannot be assigned, reject the write with a clear adapter/interface field diagnostic. Do not silently fall back to adapter-owned state.
4. If the field has an accessor mapping with `set`, evaluate its setter.
5. If the field has an accessor mapping with only `get`, reject the write through the adapter.
6. If no explicit mapping exists, fall back to same-name write behavior on the wrapped value when that fallback is currently supported.
7. Otherwise, fail with a clear adapter/interface field diagnostic.

Inside adapter implementation bodies, assignment to a declared owned field such as `(/cached_label = v)` writes adapter-owned state directly. Assignment to undeclared owned fields should be rejected when the compiler/checker can identify the adapter-owned context, and must not implicitly create interface field mappings. Outside adapter implementation execution, owned-field names are not routed through normal adapter public member lookup.

A `set` accessor on a readonly interface field is invalid because it advertises a write path that the interface contract forbids. A direct `^from` mapping on a readonly interface field is valid for reads, but writes through the adapter are rejected.

### Adapter-Owned State

Adapter-owned state is declared as typed fields and accessed directly:

```gene
(interface Ageable
  (field birth_year Int ^readonly true)
  (method age [] -> Int))

(implement Ageable for Int
  (field stored_birth_year Int)

  (ctor [birth_year]
    (/stored_birth_year = birth_year))

  (field birth_year
    (get [] /stored_birth_year))

  (method age []
    (/_wrapped - /stored_birth_year)))
```

This keeps adapter state explicit while avoiding a separate `/_geneinternal` pseudo-member. Adapter-owned fields are private implementation state, not an implicit implementation of same-named interface fields; a mapping is still required to expose owned state through the interface surface. Debug access to adapter-owned fields, if needed, should be designed separately rather than piggybacking on normal public slash access.

## Diagnostics

Diagnostics should distinguish:

- field mapping syntax errors, such as missing `get` in an accessor mapping, invalid `get` parameters, invalid `set` arity, unknown accessor forms, or invalid `^from` target shape;
- mappings that combine `^from` with accessor blocks;
- mappings for fields not declared by the interface;
- adapter-owned field declarations whose names conflict with interface-declared fields;
- duplicate adapter-owned field declarations;
- duplicate adapter field mappings for the same interface field;
- assignments to undeclared adapter-owned fields when statically identifiable in adapter implementation bodies;
- `set` accessors declared for readonly interface fields;
- write attempts through readonly fields;
- write attempts through direct `^from` mappings whose wrapped target cannot be assigned;
- write attempts through get-only adapter fields;
- missing field access when neither an explicit mapping nor same-name fallback exists.

Syntax-only diagnostics can be reported while parsing or lowering the external `implement` body. Diagnostics that require the resolved interface value or its field metadata should be reported by the compiler/checker when the target interface metadata is statically available and must also be enforced at implementation registration/runtime for dynamically resolved interfaces.

Exact marker names can be chosen during implementation, but tests should assert stable substrings/markers rather than whole prose lines.

## Implementation Notes From Current Runtime

The current adapter runtime already has pieces that align with this design, plus a few conflicts implementors must resolve:

- Direct `^from` mappings align with existing rename-style adapter mapping behavior. In the current runtime, `AmkRename` reads call the wrapped-value property path directly rather than invoking a Gene accessor method. This is the desired shape for the `^from` fast path.
- Accessor mappings need a representation with separate getter and optional setter slots. A distinct mapping kind such as `AmkAccessor` is preferred over overloading the existing one-function computed mapping.
- Adapter-owned state can continue to use the runtime backing table currently used for supplemental adapter data, but the public access surface should become declared direct owned fields rather than `/_geneinternal`.
- Implementation should track declared owned fields on the adapter implementation metadata, such as an `owned_fields` registry, so conflict detection and adapter-body-only routing do not depend on dynamic `own_data` contents.
- Owned-field read/write routing must be context-aware: direct `/field_name` access should resolve to adapter-owned state only while executing adapter implementation bodies, not during normal public member lookup on the adapted value.
- Explicit interface mappings must be checked before same-name fallback. Adapter-owned fields should not be consulted by interface field lookup except through explicit accessor bodies.
- Direct `^from` writes must not use adapter-owned state as a fallback if the wrapped-value write fails. Failing writes should report an adapter field diagnostic.
- The adapter wrapped-value pseudo-member should be exposed as `/_wrapped`; existing `/_genevalue` support should be removed or retired from the public adapter API as part of implementation cleanup unless another accepted spec still owns it.
- Interface `(field ... ^readonly true)` lowering must preserve the readonly flag so adapter write rejection works for the canonical field syntax, not only for any legacy `prop` syntax.
- Interface-dependent mapping validation, such as unknown interface fields, owned-field/interface-field conflicts, or setter declarations on readonly fields, belongs in static compiler/checker validation when metadata is available and must also be enforced at implementation registration/runtime.
- Existing `VkAdapterInternal`/`/_geneinternal` support should be removed or retired from the public adapter API as part of implementation cleanup unless another accepted spec still owns it.

## Current Code Touchpoints

Implementation should start from these observed runtime/compiler surfaces. Line references are current-code evidence captured while drafting this change and should be rechecked if nearby code moves before implementation:

- `src/gene/compiler/interfaces.nim:193`-`204` currently lowers external `implement` bodies with only `method` and `ctor` members; any `field` member is rejected as unsupported. The field-mapping forms in this change need a new external-implement lowering path alongside method and ctor lowering.
- `src/gene/compiler/interfaces.nim:37`-`58` preserves `^readonly true` for legacy `prop` declarations, but canonical interface `field` declarations currently emit `IkInterfaceProp` with readonly disabled. This is the direct code path for task 2.7.
- `src/gene/types/type_defs.nim:919`-`925` currently has `IkImplementMethod` and `IkImplementCtor`, but no instruction for external adapter field mappings or adapter-owned field declarations. The implementation can either add explicit adapter-field instructions or lower field forms through a new existing-instruction-compatible registration path.
- `src/gene/types/type_defs.nim:602`-`616` currently has `AdapterMappingKind` variants for rename, computed, and hidden only. Accessor mappings need a representation with separate getter and optional setter fields instead of using the existing one-function computed mapping.
- `src/gene/types/type_defs.nim:618`-`638` and `src/gene/types/interfaces.nim:56`-`118` store `Implementation.prop_mappings` and runtime `Adapter.own_data`, but there is no declared owned-field registry. Add metadata to `Implementation` so conflict detection and adapter-body-only owned-field routing do not depend on dynamic `own_data` contents.
- `src/gene/vm/adapter.nim:281`-`285` already uses `AmkRename` as a direct wrapped-property forwarding path for reads, so direct `^from` can reuse that fast-path concept. Its write path at `src/gene/vm/adapter.nim:332`-`337` currently falls back to `adapter.own_data` when the wrapped write fails; this change requires a diagnostic instead.
- `src/gene/vm/adapter.nim:272`-`279` currently checks `adapter.own_data` before explicit prop mappings during field reads. The new lookup precedence must check explicit direct/accessor mappings first, then same-name wrapped fallback, and must not treat adapter-owned fields as public interface fields.
- `src/gene/vm/adapter.nim:264`-`270` exposes `/_genevalue` and `/_geneinternal` as public adapter pseudo-members. The new public wrapped-value pseudo-member is `/_wrapped`; adapter-owned state should be direct and declared rather than exposed through `/_geneinternal`.
- `src/gene/vm/adapter.nim:409`-`419` implements `VkAdapterInternal` reads/writes through `own_data`. `src/gene/vm/exec.nim:1260`-`1263`, `src/gene/vm/exec.nim:1284`-`1309`, and `src/gene/vm/exec.nim:1422`-`1430` route normal and dynamic member assignment/access for `VkAdapter` and `VkAdapterInternal` directly to adapter helper procs. Removing or retiring `VkAdapterInternal` requires updating both static and dynamic member access paths.
- Existing coverage in `tests/integration/test_adapter.nim:47`-`62`, `tests/integration/test_adapter.nim:97`-`110`, `tests/integration/test_adapter.nim:188`-`210`, `tests/test_adapter.nim:57`-`88`, and `testsuite/07-oop/interfaces/` still exercises `_genevalue`, `_geneinternal`, computed prop write rejection, rename prop metadata, and same-name fallback behavior. The implementation milestone should update that coverage rather than only adding new tests.

## Cross-Change Notes

- `update-interface-field-method-syntax` is the related canonical source-level member syntax change. This change assumes its interface field surface, especially `(field name Type)`, and only defines how external adapter implementations satisfy those already-declared interface fields.
- `update-interface-field-method-syntax` rejects body-level `implement` forms inside class bodies and moves inline conformance to class headers. This change does not reopen that decision; it targets standalone external `(implement Interface for Class ...)` adapter bodies only.
- The `field` keyword has three roles depending on context: class/interface field declarations from `update-interface-field-method-syntax`, external adapter interface-field mappings, and external adapter-owned field declarations. Implementations should keep those contexts explicit in lowering and diagnostics so a typed adapter-owned field is not confused with interface storage.
- `update-unified-oop-model` explicitly excludes interfaces/protocols from its object-model scope. This change should integrate with the existing class/instance runtime shape without trying to revise the broader unified object model.
- `add-hashmap` only mentions possible future shared collection interfaces. It does not currently constrain this adapter-field mapping design, but future collection-interface work should use this change's explicit adapter field mapping surface rather than inventing a parallel adapter-property mechanism.
- `openspec list --specs` currently reports no accepted specs, so no accepted spec currently preserves the public `_genevalue`, `_geneinternal`, or `VkAdapterInternal` surfaces. If that changes before implementation, rerun the ownership check before removing compatibility paths.

## Proposed Implementation Sequence After Approval

1. Preserve interface field readonly metadata first. This is a small isolated compiler/runtime metadata fix for canonical `(field ... ^readonly true)` declarations and gives the adapter write-boundary tests a reliable base.
2. Add adapter mapping and owned-field metadata before changing lookup behavior. Extend `AdapterMappingKind` and `Implementation` so direct mappings, accessors, and declared owned fields can be represented without relying on `own_data` shape.
3. Add external `implement` field lowering and registration diagnostics. The lowering should classify `field` forms by source shape, compile accessor bodies as adapter-callable functions, and register mappings or owned fields through explicit implementation helper procs.
4. Update adapter-body member resolution for `/_wrapped` and declared owned fields. Keep this scoped to adapter ctor/method/getter/setter execution contexts so normal public adapter slash access remains interface-surface-only.
5. Rewire adapter field reads. Check direct `^from` mappings first, accessor getters second, then same-name wrapped fallback. Do not consult adapter-owned state except through explicit accessor or method bodies.
6. Rewire adapter field writes. Apply readonly rejection first, then direct wrapped writes, accessor setters, get-only rejection, and same-name fallback. Failed direct wrapped writes must raise diagnostics rather than storing into adapter-owned state.
7. Retire legacy public pseudo-members. Replace new docs and tests with `/_wrapped` and direct owned fields, then remove or fail the public `/_genevalue`, `/_geneinternal`, and `VkAdapterInternal` surfaces unless another accepted spec claims them.
8. Update user-facing docs after behavior and tests are passing. `spec/07-oop.md` and `docs/adapter-design.md` should reflect the implemented direct/accessor/owned-field surface, not an intermediate state.

## Verification Matrix

| Requirement area | Primary evidence |
| --- | --- |
| Direct `^from` mapping reads/writes and rename behavior | Focused integration fixtures under `testsuite/07-oop/interfaces/` plus Nim runtime assertions for `AmkRename`/field-forward metadata |
| Accessor `get`/`set` mapping behavior | Gene tests that read/write through adapted fields and prove no public `get`/`set` methods are exposed |
| Adapter-owned fields | Constructor-backed tests showing direct `/owned_field` access inside adapter bodies and rejection through normal public adapter slash access |
| Conflict and duplicate diagnostics | Negative Gene tests for unknown interface fields, owned-field/interface-field conflicts, duplicate owned fields, duplicate mappings, malformed accessors, invalid `^from`, and mixed direct/accessor forms |
| Readonly write boundaries | Tests for canonical `(field ... ^readonly true)` metadata, readonly direct mappings, readonly accessor setters, and get-only accessors |
| Legacy pseudo-member retirement | Updated or removed `_genevalue` and `_geneinternal` coverage in `tests/integration/test_adapter.nim`, `tests/test_adapter.nim`, and `testsuite/07-oop/interfaces/` |
| Compatibility | Existing adapter method behavior, stacked adapter behavior, same-name field fallback, `IkAdapter` legacy GIR execution, and dynamic interface calls continue to pass; final implementation verification should include `nim c -r tests/test_adapter.nim`, `nim c -r tests/integration/test_adapter.nim`, `./testsuite/run_tests.sh`, and `nimble test` |

## Deferred Additional Shorthands

This change includes `^from` because it is the optimized direct wrapped-field mapping, not mere sugar for `get`/`set`.

Additional convenience forms remain deferred until direct wrapped-field mappings, accessor mappings, and owned adapter fields are implemented and covered. Examples of deferred surfaces include default-value mappings, multi-segment path mappings, or shorthand computed mappings.
