# class-based-testing

Capability to define and run unit tests using class-based approach with TestCase base class and TestRunner.

## ADDED Requirements

### Requirement: TestCase base class

The system SHALL provide a `genex/test/TestCase` base class that users can inherit from to define test classes.

#### Scenario: Define a test class with lifecycle hooks

**Given** the Gene language has class inheritance support
**When** I define a class inheriting from `genex/test/TestCase`:
```gene
(class MyTest < genex/test/TestCase
  (var /counter 0)

  (.fn setUp []
    (/counter = 0))

  (.fn tearDown []
    (println "Test complete"))

  (.fn test_increment []
    (/counter = (/counter + 1))
    (/assert_equal 1 /counter "Counter should be 1"))
)
```
**Then** the class should be available as a valid TestCase subclass
**And** I should be able to instantiate it with `(new MyTest)`

#### Scenario: TestCase provides assertion methods

**Given** I have a class inheriting from `genex/test/TestCase`
**When** I call assertion methods in a test method:
```gene
(.fn test_assertions []
  (/assert_true true "should pass")
  (/assert_false false "should pass")
  (/assert_equal 5 5 "should pass"))
```
**Then** all assertions should pass without raising exceptions
**And** a failing assertion should raise a `TestFailure` exception

### Requirement: TestRunner discovers and executes tests

The system SHALL provide a `genex/test/TestRunner` class that automatically discovers and runs all test methods in a TestCase class.

#### Scenario: Discover test methods by name convention

**Given** I have a TestCase subclass with multiple methods:
```gene
(class MyTest < genex/test/TestCase
  (.fn setUp [] NIL)
  (.fn tearDown [] NIL)
  (.fn test_addition [] (/assert_equal 4 (2 + 2)))
  (.fn test_subtraction [] (/assert_equal 1 (3 - 2)))
  (.fn helper_method [] "not a test"))
```
**When** I create a TestRunner and call `discover_tests`:
```gene
(var runner (new genex/test/TestRunner))
(var tests (runner .discover_tests MyTest))
```
**Then** `tests` should contain `["test_addition" "test_subtraction"]`
**And** `tests` should NOT contain `"setUp"`, `"tearDown"`, or `"helper_method"`

#### Scenario: Run single test with lifecycle hooks

**Given** I have a TestCase subclass with setUp and tearDown
**When** I run a single test method:
```gene
(var runner (new genex/test/TestRunner))
(runner .run_test MyTest "test_increment")
```
**Then** the execution order should be:
1. Create new instance of MyTest
2. Call `setUp()` on the instance
3. Call `test_increment()` on the instance
4. Call `tearDown()` on the instance (even if test fails)
**And** the output should show: `TEST: MyTest.test_increment ... PASS`

#### Scenario: Run entire test suite

**Given** I have a TestCase subclass with 5 test methods (3 passing, 2 failing)
**When** I run the entire test class:
```gene
(var runner (new genex/test/TestRunner))
(runner .run_test_class MyTest)
```
**Then** all 5 tests should be executed
**And** the output should show individual results for each test
**And** the summary should show: `3 passed, 2 failed`

### Requirement: Lifecycle hooks support

The TestCase class SHALL provide `setUp` and `tearDown` lifecycle hooks that run before and after each test method.

#### Scenario: setUp initializes test state

**Given** I have a TestCase with setUp that initializes a counter:
```gene
(class CounterTest < genex/test/TestCase
  (var /counter 0)
  (.fn setUp [] (/counter = 0))
  (.fn test_increment []
    (/counter = (/counter + 1))
    (/assert_equal 1 /counter))
  (.fn test_increment_twice []
    (/counter = (/counter + 2))
    (/assert_equal 2 /counter)))
```
**When** I run both test methods
**Then** each test should see `/counter` initialized to 0
**And** both tests should pass (proving setUp ran before each test)

#### Scenario: tearDown cleans up resources

**Given** I have a TestCase with tearDown that prints cleanup message:
```gene
(class ResourceTest < genex/test/TestCase
  (.fn tearDown []
    (println "Cleaning up resources"))
  (.fn test_that_fails []
    (/assert_true false)))
```
**When** I run the test that fails
**Then** tearDown should still be called
**And** the output should show "Cleaning up resources"

### Requirement: Coexistence with functional tests

The class-based testing framework SHALL coexist with functional `test!`/`suite!` tests without conflicts.

#### Scenario: Mix functional and class-based tests in same file

**Given** I have a file with both functional and class-based tests:
```gene
# Functional test
(genex/test/test! "functional test"
  (genex/test/check true))

# Class-based test
(class MyTest < genex/test/TestCase
  (.fn test_class_based []
    (/assert_true true)))

(var runner (new genex/test/TestRunner))
(runner .run_test_class MyTest)
```
**When** I execute the file
**Then** both the functional test and class-based test should run
**And** both should report their results correctly
**And** there should be no conflicts or errors
