## Why
Gene has minimal regex support today (`regex_create`/`regex_match`/`regex_find`) and an unimplemented regex literal reader. App developers want Ruby-style regular expressions with an OOP surface area, a literal form that avoids conflicts with `/` path syntax, and standard operations like find and replace.

## What Changes
- Add regex literals using `#/pattern/flags` and `#/pattern/replacement/flags` that produce instances of `gene/Regexp`.
- Add a `gene/Regexp` class with constructor `(new gene/Regexp ^^i ^^m "pattern" "replacement")` and instance methods `match`, `process`, `find`, `find_all`, `replace`, and `replace_all`.
- Add `String` instance methods: `match`, `contain`, `find`, `find_all`, `replace`, and `replace_all` that accept `Regexp` or string patterns (except `match`, which requires a `Regexp`).
- **BREAKING**: remove legacy `regex_create`, `regex_match`, and `regex_find` globals from the stdlib.
- Document and codify compatibility differences versus Ruby, Python, and JavaScript regex behavior.

## Impact
- Affected specs: `regex` (new capability).
- Affected code: `src/gene/parser.nim` (regex literal parsing), `src/gene/stdlib.nim` (Regexp/String methods), `src/gene/types/value_core.nim` (string formatting), tests in `tests/` and `testsuite/`.
