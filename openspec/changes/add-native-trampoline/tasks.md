## 1. Implementation
- [x] 1.1 Define `CallDescriptor` and `NativeContext` types and descriptor lifetime rules
- [x] 1.2 Implement `native_trampoline` and integrate descriptor ref-counting
- [x] 1.3 Extend native compile result storage to keep descriptors on the Function
- [x] 1.4 Add `HokCallVM` and emit it for non-self calls in bytecode_to_hir
- [x] 1.5 Update `isNativeEligible` to require typed, resolvable call targets
- [x] 1.6 Update x86-64 codegen (hidden ctx param, `genCallVM`, arg register shift)
- [x] 1.7 Update ARM64 codegen (hidden ctx param, `genCallVM`, arg register shift)

## 2. Tests
- [x] 2.1 Add a native-call test: typed function calling another typed function runs via trampoline
- [x] 2.2 Add a negative test: untyped callee makes caller ineligible for native compilation

## 3. Validation
- [x] 3.1 Run `nimble test`
- [x] 3.2 Run `./testsuite/run_tests.sh`
