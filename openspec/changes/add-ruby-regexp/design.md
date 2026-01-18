## Context
Gene currently exposes `regex_create`, `regex_match`, and `regex_find` in the stdlib, but the regex literal reader (`#/.../`) is unimplemented. The proposal is to remove the legacy globals and replace them with a Ruby-style `Regexp` object model plus a `#/` literal that avoids collisions with `/` member access.

## Goals / Non-Goals
- Goals:
  - Provide `#/pattern/flags` and `#/pattern/replacement/flags` literals that yield `Regexp` instances.
  - Add a `gene/Regexp` class with property flags (`^^i`, `^^m`) and optional replacement strings.
  - Add `Regexp` instance methods: `match`, `process`, `find`, `find_all`, `replace`, `replace_all`.
  - Add `String` instance methods: `match`, `contain`, `find`, `find_all`, `replace`, `replace_all`.
  - Keep behavior close to Ruby where the underlying engine allows, and document differences from Ruby/Python/JS.
- Non-Goals:
  - Full Ruby Oniguruma parity (atomic groups, callouts, encoding modes).
  - Global match variables like Ruby `$1`, `$~`.
  - Block-based replacements in the first iteration.

## Decisions
- Literal syntax:
  - `#/pattern/flags` compiles into a `Regexp` with the given pattern and flags.
  - `#/pattern/replacement/flags` compiles into a `Regexp` with a stored replacement string.
  - Escape `\/` for a literal slash and `\\` for a literal backslash in both pattern and replacement segments.
- API surface:
  - `Regexp` is a core class exposed as `gene/Regexp` with `.ctor(pattern, replacement = nil)`.
  - Flags are passed as properties: `(new gene/Regexp ^^i ^^m "pattern" "replacement")`.
  - Regex literals compile into `Regexp` instances and store the original pattern, flags, and optional replacement.
  - `RegexpMatch` is returned by `Regexp.process` and exposes `value`, `captures`, `start`, and `end` fields.
  - `String.match` requires a `Regexp` instance; other String methods accept `Regexp` or string patterns.
  - `Regexp.replace` and `Regexp.replace_all` use an explicit replacement argument when provided; otherwise they use the stored replacement. If neither is present, they raise an error.
- Return shapes:
  - `Regexp.match` and `String.match` return a boolean.
  - `Regexp.process` returns a `RegexpMatch` object or `nil`.
  - `find` returns the first matched substring or `nil`.
  - `find_all` returns an array of matched substrings (empty if none).
  - `replace` replaces the first occurrence; `replace_all` replaces all occurrences.
- Flags:
  - Support Ruby-style flag letters `i` (ignore case) and `m` (dot matches newline).
  - Unknown flags produce an error.
- Replacement backrefs:
  - Replacement strings (from literals or arguments) support Ruby-style numeric backrefs (`\1`, `\2`, ...).

## Ruby / Python / JavaScript Differences (Summary)
- Engines:
  - Ruby: Oniguruma (rich regex features, named groups with `(?<name>...)`).
  - Python: `re` (backtracking, named groups `(?P<name>...)`).
  - JavaScript: ECMAScript (feature set varies by runtime; named groups `(?<name>...)`, lookbehind not universal).
- Multiline vs dotall:
  - Ruby `m` makes `.` match newlines; `^/$` are line anchors by default (use `\A`/`\z` for string boundaries).
  - Python `re.M` controls `^/$` line anchors; `re.S` makes `.` match newlines.
  - JavaScript `m` controls `^/$` line anchors; `s` makes `.` match newlines.
- Replacement backrefs:
  - Ruby: `\1`, `\k<name>`.
  - Python: `\1`, `\g<name>`.
  - JavaScript: `$1`, `$<name>`.

## Risks / Trade-offs
- Removing `regex_*` globals is a breaking change for existing code.
- Underlying engine differences may prevent exact Ruby semantics (anchors, lookbehind limits, Unicode classes).
- Adding `RegexpMatch` introduces a new value type and API surface.

## Migration Plan
- Implement `#/.../` literal parsing for both forms and route to `Regexp` instances.
- Add `Regexp`/`RegexpMatch` types and String regex-aware methods.
- Remove `regex_create`, `regex_match`, and `regex_find` from the stdlib namespace.
- Add tests covering literals, flags, replacement behavior, and new method behaviors.
- Document known compatibility differences.

## Open Questions
- Should `RegexpMatch` support named capture access by key?
A: deferred
- Do we want named capture groups and backrefs in v1, or only numeric groups?
A: numeric only for v1
- Should `replace`/`replace_all` accept function callbacks for computed replacements?
A: deferred
- Should `#/pattern/replacement/flags` be allowed only for replacement APIs, or also for matching APIs?
A: only for replacement APIs
