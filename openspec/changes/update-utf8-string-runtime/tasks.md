## 1. Implementation

- [x] 1.1 Add shared UTF-8 string helpers for character counting, character
      indexing, character-span slicing, and byte-size queries.
- [x] 1.2 Update core string/symbol `Value` operations and stdlib `String`
      methods so `length`, `size`, `char_at`, and slicing use character
      semantics consistently.
- [x] 1.3 Add explicit byte-oriented `String` helpers and conversions needed for
      FFI and protocol code.
- [x] 1.4 Upgrade case conversion and related string helpers to stop depending
      on ASCII-only behavior.
- [x] 1.5 Change regex match APIs so `match` returns `RegexpMatch | nil`, add a
      boolean predicate API, and convert `RegexpMatch` offsets to character
      positions.
- [x] 1.6 Expand `RegexpMatch` with named captures and additional high-value
      metadata (`pre_match`, `post_match`, etc.).
- [x] 1.7 Add regex-aware `split`, `scan`, `sub`, and `gsub` behavior, while
      preserving or documenting compatibility aliases for existing helper names.
- [x] 1.8 Add `CString`-aware native extension / FFI helpers, including
      length-aware string creation and explicit lifetime/ownership rules.
- [x] 1.9 Update the C extension header, docs, examples, and regression tests to
      cover `CString` interop and UTF-8 strings.
- [x] 1.10 Add Nim tests and Gene tests for multibyte strings, regex captures,
      regex offsets, and extension ABI behavior.

## 2. Validation

- [ ] 2.1 Run `nimble test`.
- [ ] 2.2 Run `./testsuite/run_tests.sh`.
- [x] 2.3 Build and run native extension regression tests, including the C
      extension examples.
