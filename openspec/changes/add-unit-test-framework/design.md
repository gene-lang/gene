# Design: add-unit-test-framework

## Architectural Overview

The test framework will be implemented as a native extension (`src/genex/test.nim`) that exposes test primitives to Gene code. This follows the pattern used by existing `genex` modules like `http`, `sqlite`, and `llm`.

## Key Design Decisions

### 1. Native Extension vs. Pure Gene Implementation

**Decision**: Implement as a native Nim extension (`test.nim` compiled to `.dylib`/`.so`).

**Rationale**:
- Consistency with existing `genex` modules (http, sqlite, llm, html)
- Better performance for frequently-called primitives like `check`
- Easier integration with VM internals for reporting
- Can leverage existing `extension/boilerplate.nim` infrastructure

**Alternatives considered**:
- Pure Gene source module: Would be simpler but doesn't match `genex` convention
- Inline in stdlib.nim: Doesn't scale and complicates the stdlib

### 2. Exception-Based Failure Reporting

**Decision**: Use a `TestFailure` exception class that extends `gene/Exception`.

**Rationale**:
- Consistent with Gene's existing exception handling (`try/catch`)
- Allows test frameworks to catch and report failures cleanly
- Matches the reference implementation in `gene-new`
- Enables users to wrap tests in custom `try/catch` blocks if needed

**Code pattern**:
```gene
(fn fail [message = "Test failed."]
  (throw TestFailure message)
)

(macro check [expr message = ("Check " expr " failed.")]
  (if not ($caller_eval expr)
    (fail message)
  )
)
```

### 3. Test Macros vs. Functions

**Decision**: Use macros for `test`, `skip_test`, and `suite`.

**Rationale**:
- `test` and `skip_test` need to capture test names at compile time
- `suite` needs to group tests without executing them immediately
- Macros allow for compile-time test registration and reporting hooks

**Alternatives considered**:
- Functions: Would require users to pass names as strings, less ergonomic

### 4. Reporting Strategy

**Decision**: Simple console output with test name, status (PASS/FAIL/SKIP), and optional failure message.

**Rationale**:
- Matches the simplicity of the existing `testsuite/` approach
- No dependency on external libraries
- Easy to parse for both humans and CI systems
- Can be extended later with formatters (JSON, TAP, etc.)

**Output format**:
```
TEST: A basic test ... PASS
TEST: Another test ... FAIL
  Check (1 == 2) failed.
TEST: Skipped test ... SKIP
```

### 5. Test Execution Model

**Decision**: Tests execute immediately when encountered (no delayed registration).

**Rationale**:
- Simpler implementation, no global test registry needed
- Matches the behavior of running `gene run test_file.gene`
- Allows mixing test code with regular Gene code

**Alternatives considered**:
- Deferred execution with registry: More complex, adds global state

## Best Practices from Other Languages

### Python (pytest/unittest)

**Inspired features**:
- `check(expr)` as a more readable alternative to `assert`
- Exception-based failure reporting
- Skip mechanism (`@pytest.mark.skip`)

**Not adopting**:
- Fixtures (too complex for MVP)
- Parametrized tests (future enhancement)
- Discovery/runner CLI (out of scope)

### Rust (`#[test]`)

**Inspired features**:
- Simple test attribute/macro syntax
- Tests are just functions
- Panic/exception on failure

**Not adopting**:
- Test binary compilation (Gene uses interpreted execution)
- Doc tests (not applicable)

### Clojure (test.is)

**Inspired features**:
- `deftest` macro for test definition
- `is` macro for assertions
- `testing` macro for grouping related assertions

**Not adopting**:
- `are` for parametrized tests (future enhancement)
- Complex assertion helpers (keep it simple)

## Module Structure

```
src/genex/test.nim           # Native extension
  - register_test_module()   # Entry point
  - define TestFailure class
  - implement fail()
  - implement check macro
  - implement test macro
  - implement skip_test macro
  - implement suite macro
  - helper: report_pass()
  - helper: report_fail()
  - helper: report_skip()
```

## Gene API

```gene
# Import specific symbols
(import genex/test/[test skip_test check fail TestFailure])

# Or import all
(import genex/test/*)

# Basic test
(test "addition works"
  (check ((+ 2 3) == 5))
)

# Test with custom failure message
(test "subtraction"
  (check ((- 5 3) == 2) "5 - 3 should equal 2")
)

# Skip a test
(skip_test "not implemented yet"
  (check false)
)

# Group tests in a suite
(suite "Math operations"
  (test "addition" (check ((+ 1 2) == 3)))
  (test "multiplication" (check ((* 2 3) == 6)))
)

# Manual failure
(test "error case"
  (if (some_condition)
    (fail "Expected condition to be false")
  )
)

# Catch TestFailure explicitly
(try
  (check false)
catch TestFailure
  (println "Caught test failure: " $ex/.message)
)
```

## Implementation Notes

1. **Class registration**: `TestFailure` must be registered with `vm/core.nim`'s class system
2. **Macro expansion**: `check` uses `$caller_eval` to evaluate expressions in the caller's scope
3. **Counters**: Track pass/fail/skip counts for potential summary reporting
4. **Thread safety**: Not required (tests run synchronously)

## Future Enhancements (Out of Scope)

- Test discovery runner CLI (`gene test`)
- Setup/teardown hooks
- Parametrized tests
- Test fixtures
- Async test support
- Coverage reporting
- Alternative output formats (JSON, TAP, JUnit)
- Benchmarking integration
