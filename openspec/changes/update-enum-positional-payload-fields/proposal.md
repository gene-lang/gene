## Why
Enum ADTs currently model payload metadata as declared fields with names. That works for record-like variants, but tuple-like variants should be expressible without inventing field names, while preserving named variants for keyword construction and field access.

## What Changes
- Allow an enum declaration to contain both tuple-like positional payload variants and record-like named payload variants.
- Require each individual variant to choose exactly one payload shape: positional-only or named-only; mixed positional and named fields in one variant are rejected with a targeted diagnostic.
- Support positional variant construction and access by ordinal, such as `(E/X 1 2)`, `x/0`, and `x/1`.
- Preserve named variant construction and access by declared field name, such as `(E/Y ^r 3)` and `y/r`.
- Extend enum `case` patterns so positional variants bind by ordinal and named variants bind by field name, including same-name shorthand and alias syntax such as `(E/Y r:rx)`.

## Impact
- Affected specs: `enum-adts`, `pattern-matching`
- Affected code: enum declaration parsing/checking, enum member metadata, constructor validation, member field/index access, enum case pattern validation/binding, GIR/serialization metadata for payload shape, enum tests and testsuite fixtures
