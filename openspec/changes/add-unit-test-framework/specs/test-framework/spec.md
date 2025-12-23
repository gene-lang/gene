# Spec: Test Framework

## ADDED Requirements

### Requirement: TestFailure Exception Class

The `genex/test` module MUST provide a `TestFailure` exception class that extends `gene/Exception`.

#### Scenario: TestFailure is a distinct exception type
```gene
(import genex/test/[TestFailure fail])

(try
  (fail "test failure")
catch TestFailure
  (println "Caught TestFailure: " $ex/.message)
)
```
Expected: The `TestFailure` exception is caught and the message is printed.

#### Scenario: TestFailure can be thrown explicitly
```gene
(import genex/test/[TestFailure])

(try
  (throw TestFailure "explicit failure")
catch TestFailure
  (assert ($ex/.message == "explicit failure"))
)
```
Expected: The explicitly thrown `TestFailure` is caught with the correct message.

---

### Requirement: fail Function

The `genex/test` module MUST provide a `fail` function that throws a `TestFailure` exception with an optional message parameter.

#### Scenario: fail with default message
```gene
(import genex/test/[fail])

(try
  (fail)
catch TestFailure
  (assert ($ex/.message == "Test failed."))
)
```
Expected: `fail` without arguments throws `TestFailure` with default message "Test failed.".

#### Scenario: fail with custom message
```gene
(import genex/test/[fail])

(try
  (fail "custom error message")
catch TestFailure
  (assert ($ex/.message == "custom error message"))
)
```
Expected: `fail` with a message argument throws `TestFailure` with the provided message.

---

### Requirement: check Macro

The `genex/test` module MUST provide a `check` macro that evaluates an expression and calls `fail` if the result is falsy.

#### Scenario: check passes when expression is truthy
```gene
(import genex/test/[check])

(check (1 == 1))
(println "check passed")
```
Expected: No exception is thrown and "check passed" is printed.

#### Scenario: check fails when expression is falsy
```gene
(import genex/test/[check])

(try
  (check false)
catch TestFailure
  (println "check failed as expected")
)
```
Expected: `check` throws `TestFailure` when the expression is false.

#### Scenario: check with custom failure message
```gene
(import genex/test/[check])

(try
  (check (1 == 2) "one should equal two")
catch TestFailure
  (assert ($ex/.message == "one should equal two"))
)
```
Expected: `check` throws `TestFailure` with the custom message when the expression is false.

#### Scenario: check default message includes expression
```gene
(import genex/test/[check])

(try
  (check (1 == 2))
catch TestFailure
  (assert ($ex/.message .contains "Check"))
  (assert ($ex/.message .contains "failed"))
)
```
Expected: `check` generates a default message containing "Check" and "failed".

---

### Requirement: test Macro

The `genex/test` module MUST provide a `test` macro that wraps a test body in exception handling and reports pass/fail status.

#### Scenario: test prints PASS for successful test
```gene
(import genex/test/[test])

(test "successful test"
  (check true)
)
```
Expected Output: Contains "PASS" and the test name "successful test".

#### Scenario: test prints FAIL for failing test
```gene
(import genex/test/[test])

(test "failing test"
  (check false)
)
```
Expected Output: Contains "FAIL" and the test name "failing test", plus a failure message.

#### Scenario: test with multiple assertions
```gene
(import genex/test/[test])

(test "multiple checks"
  (check (1 == 1))
  (check (2 == 2))
  (check (3 == 3))
)
```
Expected: Test passes with "PASS" status if all checks succeed.

---

### Requirement: skip_test Macro

The `genex/test` module MUST provide a `skip_test` macro that marks a test as skipped and does not execute the test body.

#### Scenario: skip_test prints SKIP status
```gene
(import genex/test/[skip_test])

(skip_test "not implemented"
  (fail "this should not run")
)
```
Expected Output: Contains "SKIP" and the test name "not implemented". No failure exception is thrown.

#### Scenario: skip_test does not execute body
```gene
(import genex/test/[skip_test])

(var counter 0)
(skip_test "increment test"
  (counter = (+ counter 1))
)
(assert (counter == 0))
```
Expected: The test body is not executed and `counter` remains 0.

---

### Requirement: suite Macro

The `genex/test` module MUST provide a `suite` macro that groups related tests and prints a suite header.

#### Scenario: suite prints header for test group
```gene
(import genex/test/[suite test])

(suite "Math operations"
  (test "addition" (check ((+ 1 2) == 3)))
  (test "subtraction" (check ((- 5 2) == 3)))
)
```
Expected Output: Contains a header with "Math operations" or "SUITE" indicator.

#### Scenario: suite contains multiple tests
```gene
(import genex/test/[suite test skip_test])

(suite "Comprehensive tests"
  (test "test 1" (check true))
  (test "test 2" (check true))
  (skip_test "test 3" (check false))
)
```
Expected: All tests are executed and their statuses are reported within the suite context.

---

### Requirement: Module Namespace

The test framework MUST be available under the `genex/test` namespace.

#### Scenario: Import specific symbols
```gene
(import genex/test/[test check])
```
Expected: Only `test` and `check` are imported into the current namespace.

#### Scenario: Wildcard import
```gene
(import genex/test/*)
```
Expected: All public symbols (`test`, `check`, `fail`, `skip_test`, `suite`, `TestFailure`) are imported.

---

### Requirement: Integration with Exception Handling

The test framework MUST work with Gene's existing `try/catch` exception handling.

#### Scenario: TestFailure can be caught with catch *
```gene
(import genex/test/[fail])

(try
  (fail "test error")
catch *
  (assert ($ex/.message == "test error"))
)
```
Expected: `TestFailure` is caught by the catch-all clause and `$ex` contains the exception.

#### Scenario: check can be used outside test macro
```gene
(import genex/test/[check])

(try
  (check (1 == 2))
catch *
  (println "caught: " $ex/.message)
)
```
Expected: `check` works standalone and throws `TestFailure` that can be caught.

---

### Requirement: Backward Compatibility

The test framework MUST NOT break existing Gene code.

#### Scenario: Existing code runs without importing genex/test
```gene
(var x 10)
(println (+ x 5))
```
Expected: Code runs normally without any test framework symbols polluting the global namespace.

#### Scenario: Existing exception handling still works
```gene
(class MyError < gene/Exception)

(try
  (throw MyError "custom error")
catch MyError
  (println "caught MyError")
)
```
Expected: Custom exception classes continue to work as before.
