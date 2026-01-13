## 1. Implementation
- [ ] 1.1 Align the parser/compiler keyword table with the reserved keyword list (including `nil`, `void`, `true`, `false`).
- [ ] 1.2 Ensure global variables are accessed only via `$name`, and remove or deprecate any `global/` handling.
- [ ] 1.3 Implement namespace import aliasing for `(import genex/llm)` and `(import genex/llm:llm2)` in the current namespace.
- [ ] 1.4 Add `global_set` built-in and compile global assignments to `global_set` with read-only validation for `$ex` and `$env`.
- [ ] 1.5 Make `$ex` thread-local in the runtime. **Blocked by:** `add-thread-support`.
- [ ] 1.6 Implement the `synchronized` form with optional `^on` property for global locking. **Blocked by:** `add-thread-support`.
- [ ] 1.7 Add direct-child global lock management for `^on` targets (using `$` prefix, e.g., `"$shared_data"`), and treat omitted `^on` as a global lock. **Blocked by:** `add-thread-support`.

## 2. Tests
- [ ] 2.1 Add Gene tests for unprefixed symbol resolution order (local, enclosing, namespace, parent).
- [ ] 2.2 Add Gene tests for `$` globals, `self`, `$ex`, `$ex/message`, and `$env` resolution.
- [ ] 2.3 Add Gene tests for namespace import aliasing (default segment and explicit alias).
- [ ] 2.4 Add Gene tests for `global_set` rejection of `$ex`/`$env` assignment.
- [ ] 2.5 Add concurrent tests to verify `synchronized` blocks access to the locked global child and allows other globals, including the omitted `^on` global lock behavior. **Blocked by:** `add-thread-support`.

## 3. Validation
- [ ] 3.1 Run `nimble test` and `./testsuite/run_tests.sh`.
- [ ] 3.2 Run `openspec validate add-symbol-resolution-spec --strict`.
