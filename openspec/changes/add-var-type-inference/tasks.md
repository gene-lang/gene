## 1. OpenSpec
- [x] 1.1 Define `var` inference behavior and assignment compatibility requirements.
- [x] 1.2 Validate proposal with `openspec validate add-var-type-inference --strict`.

## 2. Implementation
- [ ] 2.1 Update `src/gene/type_checker.nim` to infer `Nil` for `nil` literals.
- [ ] 2.2 Update map literal inference to produce `(Map Symbol <value-type>)` when possible.
- [ ] 2.3 Preserve explicit annotation behavior (`Any` opt-out and explicit concrete annotations).
- [ ] 2.4 Ensure inferred `var` types participate in assignment checks.
- [ ] 2.5 Confirm unannotated function parameters still default to `Any`.

## 3. Tests
- [ ] 3.1 Add tests in `testsuite/types/` covering literal, collection, call-result, explicit Any, and reassignment mismatch cases.
- [ ] 3.2 Run targeted types tests.
- [ ] 3.3 Run full `./testsuite/run_tests.sh`.
