## 1. Implementation
- [x] 1.1 Update class member parsing/compilation to accept `ctor`/`ctor!` and `method`.
- [x] 1.2 Update `super` constructor handling to accept `.ctor`/`.ctor!` and reject bare `ctor`/`ctor!`.
- [x] 1.3 Add explicit compiler errors for `.ctor`, `.ctor!`, `.fn`, `.fn!` in class bodies and for `super ctor` forms.
- [x] 1.4 Update docs and examples to the new keywords.
- [x] 1.5 Update tests and add negative tests for legacy dotted forms.
- [ ] 1.6 Run `nimble test` and `./testsuite/run_tests.sh`.
