## ADDED Requirements

### Requirement: Regexp literal syntax
The language SHALL parse regex literals written as `#/pattern/flags` or `#/pattern/replacement/flags` into instances of `Regexp`. Supported flag letters are `i` and `m`; unknown flags SHALL raise an error. The replacement segment, when present, SHALL be stored on the `Regexp` instance.

#### Scenario: Parse regex literal with flags
- **WHEN** a program evaluates `#/ab/i`
- **THEN** it SHALL produce a `Regexp` value configured for case-insensitive matching.

#### Scenario: Parse regex literal with replacement
- **WHEN** a program evaluates `(#/(\d)/[\\1]/ .replace_all "a1b2")`
- **THEN** it SHALL return `"a[1]b[2]"`.

#### Scenario: Escape delimiter in regex literal
- **WHEN** a program evaluates `#/a\/b/`
- **THEN** it SHALL produce a `Regexp` value that matches the literal string `a/b`.

#### Scenario: Reject unknown flag
- **WHEN** a program evaluates `#/ab/z`
- **THEN** the compiler or runtime SHALL report an invalid regex flag error.

### Requirement: Regexp construction
The system SHALL provide a `Regexp` class with a constructor that accepts a pattern string and an optional replacement string. Flags SHALL be provided as properties (`^^i`, `^^m`).

#### Scenario: Construct regexp with ignore-case flag
- **WHEN** a program evaluates:
  `(var r (new gene/Regexp ^^i "ab"))`
- **THEN** `(r .match "AB")` SHALL return `true`.

#### Scenario: Construct regexp with multiline flag
- **WHEN** a program evaluates:
  `(var r (new gene/Regexp ^^m "a.b"))`
- **THEN** `(r .match "a\nb")` SHALL return `true`.

### Requirement: Regexp match predicate
`Regexp.match` and `String.match` SHALL return a boolean indicating whether the input contains any match for the pattern. `String.match` SHALL require a `Regexp` instance.

#### Scenario: Regexp.match returns boolean
- **WHEN** a program evaluates `(#/ab/ .match "zabz")`
- **THEN** it SHALL return `true`.

#### Scenario: String.match requires Regexp
- **WHEN** a program evaluates `("ab" .match "a")`
- **THEN** it SHALL report an error indicating `match` requires a `Regexp`.

### Requirement: Regexp match objects
`Regexp.process` SHALL return a `RegexpMatch` object on success or `nil` when no match exists. `RegexpMatch` SHALL expose `value`, `captures`, `start`, and `end` fields.

#### Scenario: Regexp.process returns match object
- **WHEN** a program evaluates:
  `(var m (#/ab/ .process "zabz"))`
- **THEN** `(m/value)` SHALL be `"ab"`.

#### Scenario: RegexpMatch exposes captures
- **WHEN** a program evaluates:
  `(var m (#/(a)(b)/ .process "ab"))`
- **THEN** `(m/captures/0)` SHALL be `"a"`.

### Requirement: Regexp methods
`Regexp` SHALL provide `find`, `find_all`, `replace`, and `replace_all` methods that operate on input strings. `find` SHALL return the first matched substring or `nil`. `find_all` SHALL return all non-overlapping matches in order. `replace` SHALL replace the first match and `replace_all` SHALL replace all matches. Replacement strings SHALL support Ruby-style numeric backrefs (`\1`, `\2`, ...). If no replacement argument is provided, the stored replacement SHALL be used; if neither is available, the method SHALL report an error.

#### Scenario: Regexp.find returns first match
- **WHEN** a program evaluates `(#/\d/ .find "a1b2")`
- **THEN** it SHALL return `"1"`.

#### Scenario: Regexp.replace_all uses stored replacement
- **WHEN** a program evaluates `(#/(\d)/[\\1]/ .replace_all "a1b2")`
- **THEN** it SHALL return `"a[1]b[2]"`.

#### Scenario: Regexp.replace requires replacement when none stored
- **WHEN** a program evaluates `(#/\d/ .replace "a1b2")`
- **THEN** it SHALL report an error indicating a replacement string is required.

### Requirement: String regex helpers
`String` SHALL provide `match`, `contain`, `find`, `find_all`, `replace`, and `replace_all`. `String.match` SHALL require a `Regexp` instance. The other methods SHALL accept either a `Regexp` or a string pattern; string patterns SHALL be treated as literal substrings.

#### Scenario: String.contain accepts string pattern
- **WHEN** a program evaluates `("Hello" .contain "ell")`
- **THEN** it SHALL return `true`.

#### Scenario: String.contain accepts Regexp
- **WHEN** a program evaluates `("Hello" .contain #/ELL/i)`
- **THEN** it SHALL return `true`.

#### Scenario: String.find_all with literal pattern
- **WHEN** a program evaluates `("ababa" .find_all "a")`
- **THEN** it SHALL return `["a" "a" "a"]`.

#### Scenario: String.replace_all with Regexp
- **WHEN** a program evaluates `("a1b2" .replace_all #/(\d)/[\\1]/)`
- **THEN** it SHALL return `"a[1]b[2]"`.

### Requirement: Legacy regex globals removed
The system SHALL NOT expose `regex_create`, `regex_match`, or `regex_find` in the standard library.

#### Scenario: Legacy regex globals are unavailable
- **WHEN** a program evaluates `(regex_match "a" "a")`
- **THEN** it SHALL report an error indicating the symbol is undefined.
