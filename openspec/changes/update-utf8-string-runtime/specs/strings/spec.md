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

### Requirement: Unicode-Aware Case Conversion

The runtime SHALL provide Unicode-aware case conversion for `String` helpers and
SHALL NOT limit standard case operations to ASCII-only behavior.

#### Scenario: Lowercasing handles non-ASCII letters

- **WHEN** a program evaluates `("ÄBC" .to_lowercase)`
- **THEN** it SHALL return `"äbc"`.
