## Why

Gene currently has a split and inconsistent string model: low-level `Value`
indexing and `size` already behave like UTF-8 character operations, while
stdlib `String` methods such as `length`, `substr`, and `char_at` still use raw
byte semantics. The regex API is usable but still phase-1, and the native
extension ABI currently conflates managed Gene strings with borrowed C string
pointers.

To make Gene string handling powerful in the way Ruby is powerful, the runtime
needs one coherent text model, a dedicated `CString` FFI boundary, and a
compact but strong string/regex surface that covers real text-processing
workflows without requiring full Ruby method-for-method parity.

## What Changes

- Define UTF-8 character semantics as the default for Gene `String` indexing,
  sizing, slicing, and regex offsets.
- Add explicit byte-oriented string APIs so binary/protocol work and FFI do not
  depend on accidental byte behavior in text helpers.
- Add `CString`-aware native extension / FFI support with explicit ownership,
  lifetime, UTF-8 validation, and length-aware conversion helpers.
- Upgrade the regex API from phase-1 helpers toward Ruby-inspired workflows:
  `match` returns match data, a separate predicate handles boolean checks,
  `RegexpMatch` grows named captures and character offsets, and high-value
  operations like regex-aware `split`, `scan`, `sub`, and `gsub` become
  available.
- Preserve Gene ergonomics where useful, including aliases for existing helper
  names when that improves migration or readability.
- **BREAKING**: `String.length`/`size`, `char_at`, slicing behavior, regex
  offsets, and `Regexp.match` / `String.match` return shapes will change to
  match the new UTF-8 and match-data semantics.

## Impact

- Affected specs:
  - `strings` (new)
  - `regex` (modified)
  - `native-extensions` (modified)
- Affected code:
  - `src/gene/types/core/value_ops.nim`
  - `src/gene/types/core/constructors.nim`
  - `src/gene/stdlib/strings.nim`
  - `src/gene/stdlib/regex.nim`
  - `src/gene/extension/c_api.nim`
  - `src/gene/extension/gene_extension.h`
  - string/regex/native-extension docs and tests
- Risk: high
- Key risks:
  - breaking existing byte-oriented string code
  - regex API migration from boolean `match` to match-data `match`
  - extension ABI confusion if borrowed vs owned string lifetimes are not
    explicit
