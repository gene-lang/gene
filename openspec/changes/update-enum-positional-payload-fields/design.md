## Context
The completed unified enum ADT work records payload fields in declaration order and uses that metadata for construction, access, type validation, persistence, and case pattern binding. The current contract is record-oriented: every payload slot has a field name, optionally with a type descriptor.

The desired syntax distinguishes tuple-like and record-like variants inside the same enum:

```gene
(enum E
  (X Int Int)
  (Y r: Int))

(var x (E/X 1 2))
(var y (E/Y ^r 3))

x/0 # 1
x/1 # 2
y/r # 3
```

## Goals / Non-Goals
- Goals:
  - Add a per-variant payload shape kind: positional or named.
  - Preserve enum-level mixing of positional and named variants.
  - Reject shape mixing inside a single variant, such as `(Bad Int r: Int)`.
  - Keep constructor, access, case pattern, type metadata, GIR, and serialization behavior driven by one enum member metadata source.
- Non-Goals:
  - Add enum methods or generalized product types.
  - Allow mixed constructor calls for named variants; the existing positional-only vs keyword-only call policy remains.
  - Add partial named-pattern matching or guard/or/as patterns.
  - Reintroduce legacy Gene-expression ADT declarations.

## Decisions
- Decision: payload shape is stored per enum member.
  - `positional` variants store ordered payload slots with optional type descriptors and no field names.
  - `named` variants store ordered field names plus optional type descriptors.
  - Rationale: constructor validation, field/index access, pattern binding, and persistence need deterministic shape semantics without reparsing declaration syntax.

- Decision: enum declarations may mix variant shapes, but variants may not.
  - Example allowed: `(enum E (X Int Int) (Y r: Int))`.
  - Example rejected: `(enum E (Bad Int r: Int))`.
  - Rationale: ADTs commonly mix tuple-like and record-like variants, but intra-variant mixing creates ambiguous construction and pattern rules.

- Decision: positional variants expose ordinal access; named variants expose declared-name access.
  - `x/0` and `x/1` address positional payload slots.
  - `y/r` addresses the named payload field.
  - Rationale: tuple-like variants should not require synthetic public field names.

- Decision: enum case patterns follow the variant's payload shape.
  - Positional variants use ordinal binders: `when (E/X a b)`.
  - Named variants use field binders: `when (E/Y r)` binds field `r` to local `r`; `when (E/Y r:rx)` binds field `r` to local `rx`.
  - Rationale: pattern syntax mirrors the declaration and field access semantics.

## Risks / Trade-offs
- Existing untyped named-field syntax such as `(Circle radius)` is syntactically close to positional type-only syntax. Implementation should preserve existing behavior where a payload item is not recognized as a type descriptor, and diagnostics should guide users to `name: Type` for named typed fields.
- GIR and serialization payload metadata may need a version bump or compatibility guard if old cached enum metadata assumes every payload slot has a field name.
- Named variant patterns with alias syntax add parsing/validation surface; keeping this limited to full-field matching avoids a broader pattern-language expansion.

## Migration Plan
- Existing named variants such as `(Circle radius: Int)` keep working.
- Tuple-like variants can migrate from synthetic names to type-only slots and ordinal access.
- Diagnostics for mixed variant declarations should include the qualified variant name and point users to either all type-only slots or all named fields.
