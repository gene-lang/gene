## MODIFIED Requirements

### Requirement: Regexp match predicate

The system SHALL provide both object-returning match APIs and boolean predicate
APIs. `Regexp.match` and `String.match` SHALL return a `RegexpMatch` on success
or `nil` on failure. `Regexp.match?` and `String.match?` SHALL return a boolean
indicating whether any match exists. `String.match` and `String.match?` SHALL
require a `Regexp` instance.

#### Scenario: Regexp.match returns match data

- **WHEN** a program evaluates:
  `(var m (#/(a)(b)/ .match "zabz"))`
- **THEN** `(m/captures/0)` SHALL be `"a"`.

#### Scenario: Regexp.match? returns boolean

- **WHEN** a program evaluates `(#/ab/ .match? "zabz")`
- **THEN** it SHALL return `true`.

#### Scenario: String.match requires Regexp

- **WHEN** a program evaluates `("ab" .match "a")`
- **THEN** it SHALL report an error indicating `match` requires a `Regexp`.

### Requirement: Regexp match objects

`RegexpMatch` SHALL expose `value`, `captures`, `named_captures`, `start`,
`end`, `pre_match`, and `post_match`. `start` and `end` SHALL use UTF-8
character positions, and `end` SHALL be exclusive.

#### Scenario: RegexpMatch exposes named captures

- **WHEN** a program evaluates:
  `(var m (#/(?<word>ab)/ .match "zabz"))`
- **THEN** `(m/named_captures/word)` SHALL be `"ab"`.

#### Scenario: RegexpMatch offsets use character positions

- **WHEN** a program evaluates:
  `(var m (#/你/ .match "a你b"))`
- **THEN** `(m/start)` SHALL be `1`
- **AND** `(m/end)` SHALL be `2`.

### Requirement: Regexp methods

`Regexp` SHALL provide `find`, `find_all`, `split`, `scan`, `sub`, `gsub`,
`replace`, and `replace_all` methods that operate on input strings. Replacement
strings SHALL support numeric backrefs and named backrefs when named captures
are present.

#### Scenario: Regexp.scan returns all non-overlapping matches

- **WHEN** a program evaluates `(#/\d/ .scan "a1b2")`
- **THEN** it SHALL return `["1" "2"]`.

#### Scenario: Regexp.gsub applies replacement across the whole input

- **WHEN** a program evaluates `(#/(\d+)/ .gsub "a12b3" "[\\1]")`
- **THEN** it SHALL return `"a[12]b[3]"`.

### Requirement: String regex helpers

`String` SHALL provide regex helpers aligned with the `Regexp` API. `split`,
`find`, `find_all`, `scan`, `sub`, `gsub`, `replace`, and `replace_all` SHALL
accept a `Regexp`. Methods that also accept string input SHALL document and
preserve literal-string behavior.

#### Scenario: String.split accepts a Regexp separator

- **WHEN** a program evaluates `("foo  bar\tbaz" .split #/\s+/)`
- **THEN** it SHALL return `["foo" "bar" "baz"]`.

#### Scenario: String.gsub accepts a Regexp

- **WHEN** a program evaluates `("a1b2" .gsub #/(\d)/ "[\\1]")`
- **THEN** it SHALL return `"a[1]b[2]"`.
