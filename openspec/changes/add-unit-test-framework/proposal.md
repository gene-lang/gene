# Proposal: add-unit-test-framework

## Summary

Introduce a built-in unit testing framework in the `genex/test` namespace that provides idiomatic Gene testing primitives (`test`, `suite`, `check`, `fail`, `skip_test`) and a custom `TestFailure` exception type. This will enable Gene developers to write and run tests using Gene code rather than external shell scripts, while borrowing best practices from other languages (Python's pytest/unittest, Rust's built-in test framework, Clojure's test.is).

## Background

Gene currently has two testing approaches:
1. **Integration tests** (`testsuite/`) - Shell-driven execution with `# Expected:` output comments
2. **Unit tests** (`tests/*.nim`) - Nim-level tests for VM internals

What's missing is a **Gene-level test framework** - the ability to write tests in Gene code itself that can assert expectations and report results. This is a gap compared to most modern languages which have built-in testing facilities.

The reference implementation in `gene-new` provides a minimal `genex/test` module with `TestFailure`, `fail`, and `check`, but lacks `test`, `suite`, and `skip_test` functions that would provide a complete testing experience.

## Goals

1. **Core assertion primitives**: `check`, `fail`, and `TestFailure` exception for test failures
2. **Test organization**: `test` macro for defining individual tests, `suite` macro for grouping related tests
3. **Test filtering**: `skip_test` for temporarily disabling tests
4. **Reporting**: Clear pass/fail output with test names and failure messages
5. **Composability**: Tests work with existing `try/catch` exception handling

## Non-Goals

1. Test discovery/runner CLI in this change (tests are run by executing test files)
2. Advanced features like setup/teardown hooks, parameterized tests, or mocking
3. Integration with external test runners or CI systems
4. Performance benchmarking or profiling tools

## Solution Overview

Create a `src/genex/test.nim` native extension that provides:

1. **`TestFailure` class**: Extends `gene/Exception` for identifying test failures
2. **`fail(message)` function**: Throws `TestFailure` with optional message
3. **`check(expr, message)` macro**: Evaluates expression, calls `fail` if falsy
4. **`test(name, body)` macro**: Wraps a test body in exception handling and reports results
5. **`skip_test(name, body)` macro**: Similar to `test` but prints "[SKIPPED]" and doesn't execute body
6. **`suite(name, body)` macro**: Groups multiple `test` calls with a header

The framework will be implemented as a native extension (`.dylib`/`.so`/`.dll`) loaded via the existing `genex` namespace mechanism.

## Success Criteria

- Tests can be written and run entirely in Gene code
- Test failures are clearly reported with test names and messages
- Skipped tests are clearly indicated
- The framework works with existing Gene exception handling (`try/catch`)
- Example test files demonstrate usage patterns

## Dependencies

- Existing `genex` namespace loading mechanism in `vm/module.nim`
- Existing class and exception system in `gene/`
- Existing macro/caller_eval system

## Related Changes

- None (new feature)

## References

- Reference implementation: `gene-new/src/gene/libs.nim` (lines 785-796)
- Example usage: `example-projects/my_lib/tests/test_index.gene`
- Best practices: Python pytest, Rust `#[test]`, Clojure `test.is`
