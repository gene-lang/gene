# Tasks: add-unit-test-framework

## Implementation Tasks

### Phase 1: Foundation (Native Extension Setup)

- [ ] **Task 1**: Create `src/genex/test.nim` file with extension boilerplate
  - Include extension/boilerplate.nim
  - Import required modules (vm, types, tables)
  - Define `register_test_module()` entry point
  - Validation: Extension compiles without errors

- [ ] **Task 2**: Register `genex/test` namespace in VM
  - Create namespace during module registration
  - Ensure it's accessible via `App.app.genex_ns`
  - Validation: `(import genex/test/*)` doesn't error

### Phase 2: Core Primitives (TestFailure, fail, check)

- [ ] **Task 3**: Define `TestFailure` class
  - Create class extending `gene/Exception`
  - Register with VM's class system
  - Validation: `(throw TestFailure "msg")` works

- [ ] **Task 4**: Implement `fail` function
  - Native function taking optional message argument
  - Default message: "Test failed."
  - Throws `TestFailure` exception
  - Validation: `(try (fail) catch TestFailure (assert true))`

- [ ] **Task 5**: Implement `check` macro
  - Macro taking expression and optional message
  - Uses `$caller_eval` to evaluate expression
  - Calls `fail` if result is falsy
  - Default message generation with expression context
  - Validation: `(check true)` passes, `(check false)` fails

### Phase 3: Test Organization (test, skip_test)

- [ ] **Task 6**: Implement `test` macro
  - Macro taking name (string) and body (gene)
  - Wraps body in try/catch for `TestFailure`
  - Prints "TEST: <name> ... PASS" on success
  - Prints "TEST: <name> ... FAIL" + message on failure
  - Validation: Running a test produces formatted output

- [ ] **Task 7**: Implement `skip_test` macro
  - Macro taking name (string) and body (gene)
  - Prints "TEST: <name> ... SKIP" without executing body
  - Validation: Skipped test doesn't execute body

### Phase 4: Test Grouping (suite)

- [ ] **Task 8**: Implement `suite` macro
  - Macro taking name (string) and body (gene)
  - Prints "SUITE: <name>" header
  - Executes body (contains `test` calls)
  - Validation: Suite header appears before test output

### Phase 5: Build Integration

- [ ] **Task 9**: Add to build system
  - Update `gene.nimble` to include `src/genex/test.nim` in build
  - Ensure compilation produces `build/libtest.{dylib|so|dll}`
  - Validation: `nimble build` produces test extension

### Phase 6: Documentation and Examples

- [ ] **Task 10**: Create example test file
  - Add `examples/test_framework.gene` demonstrating all features
  - Include passing, failing, and skipped tests
  - Include suite examples
  - Validation: `bin/gene run examples/test_framework.gene` works

- [ ] **Task 11**: Update documentation
  - Add section to `docs/` or `README.md` about testing
  - Document API (test, check, fail, skip_test, suite, TestFailure)
  - Provide usage examples
  - Validation: Documentation is accurate and complete

### Phase 7: Testing and Validation

- [ ] **Task 12**: Create comprehensive test suite
  - Write tests covering all spec scenarios
  - Use the framework to test itself where possible
  - Validation: All tests pass

- [ ] **Task 13**: Update example projects
  - Ensure `example-projects/my_lib/tests/test_index.gene` works with new framework
  - Update if needed for API changes
  - Validation: Example project tests run successfully

- [ ] **Task 14**: Integration testing
  - Run full `nimble test` suite
  - Run `./testsuite/run_tests.sh`
  - Ensure no regressions
  - Validation: All existing tests still pass

## Task Dependencies

```
Phase 1:
  Task 1 ──► Task 2

Phase 2 (depends on Phase 1):
  Task 3 ──► Task 4 ──► Task 5

Phase 3 (depends on Phase 2):
  Task 6 (parallel with Task 7)

Phase 4 (depends on Phase 3):
  Task 8

Phase 5 (depends on Phase 4):
  Task 9

Phase 6 (depends on Phase 5):
  Task 10 (parallel with Task 11)

Phase 7 (depends on Phase 6):
  Task 12 ──► Task 13 ──► Task 14
```

## Parallelizable Work

- Tasks 6 and 7 can be developed in parallel
- Tasks 10 and 11 can be done in parallel

## Validation Checklist

Before marking this change complete:

- [ ] All spec scenarios pass
- [ ] `nimble build` produces the test extension
- [ ] `bin/gene run examples/test_framework.gene` works
- [ ] Example project tests run with new framework
- [ ] No regressions in existing tests
- [ ] Documentation is complete
