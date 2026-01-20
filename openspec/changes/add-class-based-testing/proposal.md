# Proposal: add-class-based-testing

## Summary

Add a class-based unit testing framework to `genex/test` as an alternative to the functional `test!`/`suite!` macros. This framework provides xUnit-style test classes with `setUp`/`tearDown` lifecycle hooks, test discovery, and a `TestRunner` for executing test suites. This offers a more structured, object-oriented approach for developers who prefer organizing tests as classes.

## Background

Gene now has a functional testing framework (`test!`, `suite!`, `check`, `fail`) implemented as native macros in `src/genex/test.nim`. This works well for simple, procedural test cases.

However, many developers are familiar with class-based testing from frameworks like:
- **JUnit** (Java) - Test classes with `@Before`/`@After` annotations
- **unittest** (Python) - `TestCase` subclasses with `setUp`/`tearDown` methods
- **RSpec** (Ruby) - Describe blocks with `before`/`after` hooks
- **NUnit** (.NET) - Test fixtures with `[SetUp]`/`[TearDown]` attributes

A class-based approach offers:
1. **State management**: Test classes can hold instance variables for test fixtures
2. **Lifecycle hooks**: `setUp`/`tearDown` for resource management
3. **Inheritance**: Share common test utilities via base classes
4. **Discovery**: Automatically find all `test_*` methods in a class
5. **Organization**: Group related tests naturally as methods of a class

## Goals

1. **TestCase base class**: Provide `genex/test/TestCase` class with lifecycle hooks
2. **Test discovery**: Automatically identify `test_*` methods in TestCase subclasses
3. **TestRunner**: Native implementation to discover and run tests
4. **Lifecycle hooks**: Support `setUp` and `tearDown` methods
5. **Result reporting**: Clear output showing test class, method names, and results
6. **Coexistence**: Work alongside functional `test!`/`suite!` framework

## Non-Goals

1. Advanced features like `setUpClass`/`tearDownClass` (class-level fixtures)
2. Test parameterization or data-driven testing
3. Mocking/stubbing utilities
4. Asynchronous test support
5. CLI test runner with filtering (can be added later)
6. Test discovery across multiple files/modules

## Solution Overview

Extend `src/genex/test.nim` with:

### 1. TestCase Base Class
```gene
(class TestCase
  # Lifecycle hooks (override in subclasses)
  (method setUp [])     # Called before each test method
  (method tearDown [])  # Called after each test method

  # Assertion methods (delegated to existing check/fail)
  (method assert_true [expr message])
  (method assert_false [expr message])
  (method assert_equal [expected actual message])
  (method assert_raises [exception_class body])
)
```

### 2. TestRunner Class
```gene
(class TestRunner
  # Run all test_* methods in a TestCase class
  (method run_test_class [test_class])

  # Run a specific test method
  (method run_test [test_class method_name])

  # Discover all test_* methods in a class
  (method discover_tests [test_class])
)
```

### 3. Implementation Details (Native Nim)

**TestCase methods** (native):
- `setUp` / `tearDown` - No-op defaults, overridable
- `assert_*` methods - Thin wrappers around existing `check`/`fail`

**TestRunner methods** (native):
- `discover_tests(class)` - Introspect class methods, return list of `test_*` method names
- `run_test(class, name)` - Instantiate class, call setUp, call test method, call tearDown, handle exceptions
- `run_test_class(class)` - Discover all tests and run each one

### 4. Usage Example
```gene
(class MyTest < genex/test/TestCase
  # Test fixture state
  (var /counter 0)

  # Lifecycle hooks
  (method setUp []
    (/counter = 0))

  (method tearDown []
    (println "Test complete, counter:" /counter))

  # Test methods (must start with test_)
  (method test_increment []
    (/counter = (/counter + 1))
    (/assert_equal 1 /counter "Counter should be 1"))

  (method test_decrement []
    (/counter = -1)
    (/assert_equal -1 /counter))
)

# Run all tests in the class
(var runner (new genex/test/TestRunner))
(runner .run_test_class MyTest)

# Or run a specific test
(runner .run_test MyTest "test_increment")
```

## Success Criteria

1. TestCase base class is available at `genex/test/TestCase`
2. TestRunner can discover and run all `test_*` methods in a TestCase subclass
3. `setUp` and `tearDown` are called before/after each test
4. Test failures are clearly reported with class name, method name, and message
5. Multiple test classes can be defined and run independently
6. Class-based tests coexist with functional `test!`/`suite!` tests

## Dependencies

- Existing `genex/test` module with `check`, `fail`, `TestFailure`
- Gene class system with inheritance (`<` operator)
- Method introspection capabilities (list methods of a class)

## Related Changes

- `add-unit-test-framework` - Provides foundational `check`/`fail` and functional macros
- This change extends it with class-based alternative

## Implementation Notes

### Method Discovery
The `discover_tests` method needs to introspect a class to find all methods starting with `test_`. In Nim, this can be done by:
1. Iterating over `class.methods` table
2. Filtering method names that start with "test_"
3. Returning a list of method names

### Test Execution Flow
For each test method:
1. Create new instance: `let instance = new_instance_value(test_class)`
2. Call setUp: `instance.call_method("setUp", [])`
3. Call test method: `instance.call_method(method_name, [])`
4. Call tearDown: `instance.call_method("tearDown", [])` (in finally block)
5. Catch TestFailure exceptions and report

### Assertion Methods
These can be simple wrappers:
```nim
proc vm_assert_true(vm, args, arg_count, has_kw): Value =
  let expr = get_positional_arg(args, 0, has_kw)
  let message = if arg_count > 1: get_positional_arg(args, 1, has_kw) else: "Assertion failed"
  # Delegate to existing vm_check
  return vm_check(vm, args, arg_count, has_kw)
```

## Open Questions

None - design is straightforward based on established xUnit patterns.

## References

- JUnit: https://junit.org/junit5/docs/current/user-guide/
- Python unittest: https://docs.python.org/3/library/unittest.html
- Existing Gene test framework: `src/genex/test.nim`
