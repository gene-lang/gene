## 1. Class Aspect Definition
- [x] 1.1 Implement `(aspect ...)` compilation + VM execution path to create Aspect values.
- [x] 1.2 Build advice function creation with implicit self and matcher parsing.

## 2. Aspect Application
- [x] 2.1 Implement `Aspect.apply` to map placeholders to method names and replace method callables with interceptions.
- [x] 2.2 Validate method existence and argument counts at apply-time.

## 3. VM Interception Runtime
- [x] 3.1 Intercept method calls across all arities and keyword/dynamic call paths.
- [x] 3.2 Execute before_filter/before/after/around advices with correct argument passing and return value handling.
- [x] 3.3 Execute invariant advices around the around/original call with correct ordering and skip semantics.
- [x] 3.4 Support callable-based advices (Gene/native functions) with method-style argument passing.

## 4. Tests
- [x] 4.1 Add Gene-level tests for before/after/before_filter/around on class methods.
- [x] 4.2 Add coverage for method name mapping and implicit self.
- [x] 4.3 Add Gene-level tests for invariant ordering and before_filter/exception skip behavior.
- [x] 4.4 Add tests for callable-based advices using Gene and native functions.

## 5. Validation
- [ ] 5.1 Run `nimble test`.
- [ ] 5.2 Run `./testsuite/run_tests.sh`.
