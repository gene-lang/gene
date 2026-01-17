## 1. Implementation
- [x] 1.1 Update function parsing/compilation to require array argument lists for `fn`.
- [x] 1.2 Remove `fnx`, `fnx!`, and `fnxx` as function-definition forms in parser/compiler.
- [x] 1.3 Update arg matcher validation errors to mention bracketed argument lists.
- [x] 1.4 Update reserved keywords list and syntax highlighting to remove `fnx`.
- [x] 1.5 Update docs and examples to use `(fn [args] ...)` and `(fn name [args] ...)`.
- [x] 1.6 Update tests/testsuite for new syntax and add coverage for legacy-form rejection.

## 2. Validation
- [x] 2.1 Run `nimble build`.
- [x] 2.2 Run `./testsuite/run_tests.sh`.
