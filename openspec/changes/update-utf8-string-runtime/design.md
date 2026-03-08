## Context

Gene currently exposes contradictory string semantics:

- `Value[i]` and `Value.size` already walk UTF-8 runes for strings and symbols.
- stdlib `String.length`, `String.substr`, and `String.char_at` still use raw
  Nim string byte operations.
- regex matching returns byte offsets and splits its API between boolean
  `match` and object-returning `process`.
- the C API exposes only `gene_to_value_string(const char*)` and
  `gene_to_string(Value)`, which is insufficient for explicit `CString`
  interop, length-aware text conversion, or clear ownership rules.

This creates a runtime where text behavior depends on which layer a caller hits.
That is a poor foundation for both user ergonomics and FFI correctness.

## Goals

- Make `String` a coherent UTF-8 text type across core `Value` operations and
  stdlib methods.
- Keep byte-oriented operations available, but explicit.
- Introduce `CString` as an FFI boundary type rather than overloading managed
  `String`.
- Provide Ruby-inspired regex and string power for common text workflows.
- Improve match-data ergonomics without requiring full Ruby parity.

## Non-Goals

- Full Ruby or Onigmo compatibility.
- Grapheme-cluster-aware editing in phase 1.
- Support for arbitrary non-UTF-8 encodings in phase 1.
- Replacing `String` with `CString` in userland code.
- Adding every Ruby `String` convenience method before shipping.

## Decisions

### 1. `String` Stays UTF-8 Internally, Character-Oriented Externally

Strings continue to store UTF-8 bytes internally, but user-facing indexing,
size, length, slicing, and regex offsets are defined in Unicode scalar value
positions.

Phase 1 unit of text:

- Unicode scalar values (`Rune` / Gene `Char`)

Not phase 1:

- grapheme-cluster-aware cursor/edit semantics

### 2. Core and Stdlib Must Agree

The current rune-aware `Value[i]` and `Value.size` behavior becomes the baseline
that stdlib `String` methods must match.

This change updates:

- `String.length`
- `String.size`
- `String.char_at`
- existing slice/substr helpers
- regex match offsets stored in `RegexpMatch`

### 3. Byte APIs Are Explicit

Byte behavior remains available, but it is no longer the default semantic path
for `String`.

Planned explicit byte-oriented helpers include:

- `bytesize`
- byte iteration helpers
- byte slicing helpers
- explicit conversion to/from `Bytes`

### 4. `CString` Is an Interop Type, Not a Replacement Text Type

`CString` exists to bridge native and FFI boundaries:

- NUL-terminated C string expectations
- borrowed string-pointer views
- copied/owned buffers when native code must retain data

It is not the general-purpose Gene text type.

### 5. Native Extension ABI Adds Length-Aware String Helpers

The C API is extended so native code can distinguish:

- borrowed NUL-terminated pointer access
- byte length queries
- explicit creation of Gene strings from `(ptr, len)` input

Representative helpers:

- `gene_to_value_string_n(ptr, len)`
- `gene_string_len(value)`
- borrowed `CString` access helper(s)

The exact helper names may vary, but the ABI must expose the capabilities.

### 6. Invalid UTF-8 and Embedded NUL Policy

Managed `String` assumes valid UTF-8.

Policy:

- `CString -> String` validates UTF-8 before creating managed `String`
- invalid text fails deterministically or requires an explicit bytes/lossy path
- embedded NUL is not silently accepted when marshalling to `CString`
- arbitrary binary data belongs in `Bytes`

### 7. Regex API Moves to Match Data First

The regex API shifts toward Ruby-inspired behavior:

- `match` returns `RegexpMatch | nil`
- a separate predicate method handles boolean checks
- `RegexpMatch` grows named captures and character-based offsets

The existing `process` helper may remain as an alias during migration, but the
primary public model is match-data-first.

### 8. High-Value Regex and String Surface Wins Over Exhaustiveness

The target is workflow parity for common tasks:

- regex matching
- captures
- split
- scan
- sub/gsub style replacement
- trimming and case conversion
- prefix/suffix checks
- character/byte iteration

This change intentionally does not require every Ruby string or regexp method.

## Trade-offs

- Character-based APIs require extra UTF-8 traversal work compared with raw byte
  indexing.
- Regex offsets may be more expensive when converted from engine byte positions
  to character positions.
- Supporting both Gene aliases and Ruby-style names adds API surface, but it may
  reduce migration friction.

## Migration Plan

1. Add shared UTF-8 helpers used by both core `Value` and stdlib `String`
   methods.
2. Convert stdlib methods to character semantics and add explicit byte APIs.
3. Extend `RegexpMatch` and migrate regex offsets and match return shapes.
4. Add `CString` ABI helpers and update C extension docs/tests.
5. Expand regex/string helpers (`split`, `scan`, `sub`, `gsub`) and document
   supported semantics and differences.

## Open Questions

- Should the boolean predicate be spelled `match?`, `matches?`, or documented as
  an alias set?
  - Recommendation: prefer `match?` and allow compatibility aliases if needed.
  A: just use `match`. We will not use `?` in function/method names until we have a better understanding of the needs.
- Should the existing `substr` name remain as an alias after adding `slice`?
  - Recommendation: yes, at least through migration.
  A: we'll use substr instead of slice.
- Should case conversion and normalization depend only on Nim stdlib facilities,
  or should this change permit an additional Unicode-focused dependency?
  - Recommendation: start with the best built-in coverage available and revisit
    dependency choices only if functionality is insufficient.
