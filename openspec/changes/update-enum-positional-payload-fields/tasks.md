## 1. Implementation
- [x] 1.1 Extend enum member metadata with a payload shape kind and support anonymous positional payload slots with type descriptors.
- [x] 1.2 Update enum declaration parsing/checking to distinguish positional type-only slots from named field slots and reject mixed slots within one variant.
- [x] 1.3 Update constructor validation so positional variants reject keyword construction and named variants keep the existing positional-only or keyword-only constructor policy.
- [x] 1.4 Add ordinal payload access for positional variants and preserve declared-name access for named variants.
- [x] 1.5 Update enum case pattern checking/compilation so positional variants bind by ordinal and named variants bind by field-name shorthand or `field:local` aliases.
- [x] 1.6 Update GIR/serialization/tree-serdes metadata handling and versioning if payload shape metadata changes cache compatibility.

## 2. Tests and Docs
- [x] 2.1 Add focused type-checker and runtime tests for mixed enum-level variant shapes.
- [x] 2.2 Add negative tests for mixed positional+named fields in one variant, keyword calls to positional variants, ordinal access errors, and named-pattern field errors.
- [x] 2.3 Add case-pattern tests for `(E/X a b)`, `(E/Y r)`, and `(E/Y r:rx)`.
- [x] 2.4 Update public enum ADT docs/examples to show tuple-like and record-like variants without implying they can mix within one variant.

## 3. Validation
- [x] 3.1 Run `openspec validate update-enum-positional-payload-fields --strict`.
- [x] 3.2 Run focused enum/type-checker tests.
- [x] 3.3 Run the language testsuite subset that covers enum ADTs and pattern matching.
