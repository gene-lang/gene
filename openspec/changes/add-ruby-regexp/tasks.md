## 1. Implementation
- [x] 1.1 Implement `#/.../` literal parsing with pattern + optional replacement segment + `i`/`m` flag letters.
- [x] 1.2 Add `Regexp` class with `ctor(pattern, replacement = nil)` and methods `match`, `process`, `find`, `find_all`, `replace`, `replace_all` (flags via `^^i`/`^^m`).
- [x] 1.3 Add `RegexpMatch` type with `value`, `captures`, `start`, and `end` accessors.
- [x] 1.4 Extend `String` with `match`, `contain`, `find`, `find_all`, `replace`, `replace_all` that accept `Regexp` or string patterns (except `match`, which requires `Regexp`).
- [x] 1.5 Remove `regex_create`, `regex_match`, and `regex_find` globals from the stdlib namespace.
- [x] 1.6 Add tests for regex literal parsing (both forms), flags, match objects, replacement behavior, and String/Regexp methods.
- [x] 1.7 Document regex syntax, OOP API, and compatibility differences.

## 2. Validation
- [ ] 2.1 Run `nimble test`.
- [ ] 2.2 Run `./testsuite/run_tests.sh`.
