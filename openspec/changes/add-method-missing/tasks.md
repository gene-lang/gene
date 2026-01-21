## 1. Type System Changes
- [x] 1.1 Uncomment and enable `method_missing` field in `ClassObj` (`src/gene/types/type_defs.nim:371`)
- [x] 1.2 Add helper proc `get_method_missing(class: Class): Value` in `src/gene/types/classes.nim` that traverses hierarchy
- [x] 1.3 Initialize `method_missing` to `NIL` in `new_class` proc

## 2. VM Method Dispatch Integration
- [x] 2.1 Add `call_method_missing` helper proc in `vm.nim`
- [x] 2.2 Modify `IkUnifiedMethodCall0` dispatch to check `method_missing`
- [x] 2.3 Modify `IkUnifiedMethodCall1` dispatch to check `method_missing`
- [x] 2.4 Modify `IkUnifiedMethodCall2` dispatch to check `method_missing`
- [x] 2.5 Modify `IkUnifiedMethodCall` (N-arg) dispatch to check `method_missing`
- [x] 2.6 Modify `IkUnifiedMethodCallKw` dispatch to check `method_missing`
- [x] 2.7 Modify `IkDynamicMethodCall` dispatch to check `method_missing`
- [x] 2.8 Wire up `method_missing` storage during method definition (`IkDefineMethod`)

## 3. Parser/Compiler (if needed)
- [x] 3.1 Verify `method_missing` is parsed as a regular method (no special syntax needed)

## 4. Testing
- [x] 4.1 Add Gene integration test `testsuite/oop/method_missing.gene`
- [x] 4.2 Test basic method_missing invocation
- [x] 4.3 Test method_missing with arguments
- [x] 4.4 Test method_missing inheritance
- [x] 4.5 Test method_missing override in child class
- [x] 4.6 Test regular methods take precedence
- [x] 4.7 Test return value propagation
- [x] 4.8 Test zero-argument method calls
- [x] 4.9 Test multiple arguments
- [x] 4.10 Run full test suite to verify no regressions

## 5. Documentation
- [ ] 5.1 Update `examples/full.gene` with method_missing example
- [ ] 5.2 Update `CLAUDE.md` if needed
