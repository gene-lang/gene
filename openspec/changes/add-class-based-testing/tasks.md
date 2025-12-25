# Tasks: add-class-based-testing

## Phase 1: TestCase Base Class (Core)

### 1.1 Define TestCase class structure
- [ ] Add `TestCase` class to `src/genex/test.nim` init
- [ ] Define empty `setUp` method (no-op default)
- [ ] Define empty `tearDown` method (no-op default)
- [ ] Register class in `genex/test` namespace
- **Validation**: `(println genex/test/TestCase)` prints `VkClass`

### 1.2 Implement assertion helper methods
- [ ] Add `assert_true(expr, message?)` native method
- [ ] Add `assert_false(expr, message?)` native method
- [ ] Add `assert_equal(expected, actual, message?)` native method
- [ ] All methods delegate to existing `vm_check`/`vm_fail`
- **Validation**: Create test class, call assertions, verify they pass/fail correctly

## Phase 2: TestRunner Implementation

### 2.1 Implement test discovery
- [ ] Add `TestRunner` class to `src/genex/test.nim`
- [ ] Implement `discover_tests(class)` native method
- [ ] Iterate over class.methods table
- [ ] Filter method names starting with "test_"
- [ ] Return array of method name strings
- **Validation**: Create test class with 3 test_ methods, discover returns 3 names

### 2.2 Implement single test execution
- [ ] Implement `run_test(test_class, method_name)` native method
- [ ] Create new instance of test_class
- [ ] Call `setUp()` on instance
- [ ] Call test method by name
- [ ] Call `tearDown()` in finally block
- [ ] Catch and report `TestFailure` exceptions
- [ ] Print result: "TEST: ClassName.method_name ... PASS/FAIL"
- **Validation**: Run single test, verify setUp/tearDown called, result printed

### 2.3 Implement test suite execution
- [ ] Implement `run_test_class(test_class)` native method
- [ ] Call `discover_tests()` to get method names
- [ ] Iterate and call `run_test()` for each method
- [ ] Track pass/fail counts
- [ ] Print summary: "X passed, Y failed"
- **Validation**: Run class with 5 tests (3 pass, 2 fail), verify counts

## Phase 3: Testing and Documentation

### 3.1 Create example test files
- [ ] Create `/tmp/test_class_based.gene` with sample TestCase
- [ ] Include setUp/tearDown usage
- [ ] Include multiple test methods
- [ ] Include both passing and failing tests
- **Validation**: Run example, verify output matches expected

### 3.2 Test coexistence with functional tests
- [ ] Create file mixing `test!` and TestCase classes
- [ ] Verify both work independently
- [ ] Verify shared counters (pass/fail) work correctly
- **Validation**: Mixed file runs without conflicts

### 3.3 Write tests for class-based framework
- [ ] Test TestCase instantiation
- [ ] Test setUp/tearDown lifecycle
- [ ] Test assertion methods
- [ ] Test discovery finds correct methods
- [ ] Test runner handles exceptions correctly
- **Validation**: All tests pass

## Phase 4: Advanced Features (Optional)

### 4.1 Add assertion variants
- [ ] Add `assert_not_equal`
- [ ] Add `assert_nil`
- [ ] Add `assert_not_nil`
- [ ] Add `assert_raises` (verify exception thrown)
- **Validation**: Tests using new assertions work correctly

### 4.2 Enhance reporting
- [ ] Add color output (PASS=green, FAIL=red)
- [ ] Add timing information per test
- [ ] Add verbose mode flag
- **Validation**: Output is readable and helpful

## Dependencies

- Must complete after `add-unit-test-framework` provides `check`/`fail`
- Requires Gene class system with inheritance
- Requires method introspection capabilities

## Notes

- Each task should take 30-60 minutes
- Tasks within a phase can be parallelized
- Validation criteria ensure incremental progress
- Phase 1-3 are core, Phase 4 is optional enhancements
