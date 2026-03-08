## ADDED Requirements

### Requirement: UTF-8 Character Semantics for String

The runtime SHALL treat Gene `String` indexing, size, length, character access,
and slicing as UTF-8 character operations based on Unicode scalar values.
Byte-oriented behavior SHALL NOT be the default for user-facing string helpers.

#### Scenario: Size counts UTF-8 characters rather than bytes

- **WHEN** a program evaluates `("你从哪里来？" .size)`
- **THEN** it SHALL return `6`.

#### Scenario: Character access returns the expected multibyte character

- **WHEN** a program evaluates `("你从哪里来？" .char_at 1)`
- **THEN** it SHALL return `'从'`.

#### Scenario: Slicing uses character positions

- **WHEN** a program evaluates `("a你b" .substr 1 1)`
- **THEN** it SHALL return `"你"`.

### Requirement: Explicit Byte-Oriented String APIs

The runtime SHALL expose explicit byte-oriented string helpers so FFI and
protocol code can access UTF-8 byte counts and byte slices without changing the
default character semantics of `String`.

#### Scenario: Byte size differs from character size for multibyte text

- **WHEN** a program evaluates `("你" .bytesize)`
- **THEN** it SHALL return `3`.

#### Scenario: Byte helpers expose UTF-8 bytes explicitly

- **WHEN** a program evaluates `("你" .byte_at 1)`
- **THEN** it SHALL return `189`.
- **AND WHEN** a program evaluates `("a你b" .byteslice 1 3)`
- **THEN** the result SHALL contain the UTF-8 bytes for `"你"`.

### Requirement: Offset-Aware Search Helpers

The runtime SHALL provide `String.index` and `String.rindex` with UTF-8
character offsets. Both helpers SHALL accept literal strings and `Regexp`
patterns.

#### Scenario: String.index accepts a character offset

- **WHEN** a program evaluates `("a你b你" .index "你" 2)`
- **THEN** it SHALL return `3`.

#### Scenario: String.rindex accepts a Regexp and character offset

- **WHEN** a program evaluates `("a你b你" .rindex #/你/ 2)`
- **THEN** it SHALL return `1`.

### Requirement: Unicode-Aware Case Conversion

The runtime SHALL provide Unicode-aware case conversion for `String` helpers and
SHALL NOT limit standard case operations to ASCII-only behavior.

#### Scenario: Lowercasing handles non-ASCII letters

- **WHEN** a program evaluates `("ÄBC" .to_lowercase)`
- **THEN** it SHALL return `"äbc"`.

### Requirement: Trim Family Helpers

The runtime SHALL provide the common trim-family helpers needed for everyday
text processing, including full trim, left trim, and right trim.

#### Scenario: Left trim preserves trailing content

- **WHEN** a program evaluates `("  abc  " .lstrip)`
- **THEN** it SHALL return `"abc  "`.

#### Scenario: Right trim preserves leading content

- **WHEN** a program evaluates `("  abc  " .rstrip)`
- **THEN** it SHALL return `"  abc"`.

### Requirement: Ruby-Style String Convenience Helpers

The runtime SHALL provide a compact set of Ruby-style convenience helpers and
aliases for common string workflows without requiring full Ruby method parity.

#### Scenario: Ruby-style predicate aliases work with string helpers

- **WHEN** a program evaluates `("abc" .start_with? "ab")`
- **THEN** it SHALL return `true`.
- **AND WHEN** a program evaluates `("a你b" .include? #/你/)`
- **THEN** it SHALL return `true`.

#### Scenario: Ruby-style casing helpers remain Unicode-aware

- **WHEN** a program evaluates `("äBC" .capitalize)`
- **THEN** it SHALL return `"Äbc"`.
- **AND WHEN** a program evaluates `("ÄBC" .downcase)`
- **THEN** it SHALL return `"äbc"`.

### Requirement: Character Iteration Helpers

The runtime SHALL provide character-oriented helper methods that operate on
UTF-8 scalar values rather than raw bytes.

#### Scenario: Chars returns UTF-8 scalar values

- **WHEN** a program evaluates `("a你b" .chars)`
- **THEN** the result SHALL contain the three characters `['a' '你' 'b']`.

#### Scenario: Reverse preserves multibyte characters

- **WHEN** a program evaluates `("a你b" .reverse)`
- **THEN** it SHALL return `"b你a"`.
