# Implementation Tasks

## Phase 1: Simplify Infrastructure

### 1.1 Remove IkNewMacro instruction
- [ ] Remove `IkNewMacro` from `InstructionKind` enum in `src/gene/types.nim`
- [ ] Remove `IkNewMacro` case from VM dispatch in `src/gene/vm.nim`
- [ ] Remove `IkNewMacro` from any listing/trace utilities
- [ ] Update GIR serialization if needed

### 1.2 Update compile_new for macro constructors
- [ ] Modify `compile_new` to detect `new!` calls
- [ ] Handle unevaluated argument compilation with quote level
- [ ] Use existing constructor infrastructure (no special VM instruction)
- [ ] Ensure quote level handling works for unevaluated arguments

### 1.3 Update constructor definitions
- [ ] Ensure `.ctor!` creates constructor with unevaluated argument handling
- [ ] Verify constructor logic is properly integrated with class
- [ ] Test constructor works with `new!` syntax

## Phase 2: Constructor Type Tracking

### 2.1 Add constructor type field to Class
- [ ] Add `has_macro_constructor*: bool` field to `ClassObj` in `src/gene/types.nim`
- [ ] Initialize field to `false` in class creation
- [ ] Update GIR serialization if needed for the new field

### 2.2 Track constructor type during compilation
- [ ] Modify `compile_constructor_definition` to set `has_macro_constructor = true` for `.ctor!`
- [ ] Ensure `.ctor` leaves field as `false`
- [ ] Test that field is set correctly for both constructor types

### 2.3 Add compile-time validation
- [ ] Add validation in `compile_new` to check `new` vs regular constructor
- [ ] Add validation in `compile_new` to check `new!` vs macro constructor
- [ ] Implement clear error messages for compile-time mismatches
- [ ] Test compile-time validation scenarios

## Phase 3: Super Constructor Support

### 3.1 Add super .ctor! syntax parsing
- [ ] Add `.ctor!` case to `compile_gene` method call handling
- [ ] Implement quote level management for macro super calls
- [ ] Ensure proper argument passing (unevaluated)

### 3.2 Super constructor validation
- [ ] Add validation for super constructor calls in VM
- [ ] Check parent class constructor type compatibility
- [ ] Implement super constructor mismatch error messages
- [ ] Test inheritance scenarios

### 3.3 Super call implementation
- [ ] Extend existing super call mechanism for macro constructors
- [ ] Ensure proper caller context is maintained
- [ ] Handle argument passing correctly for both types
- [ ] Test multi-level inheritance

## Phase 4: Testing

### 4.1 Basic constructor validation tests
- [ ] Test regular constructor with regular instantiation (success)
- [ ] Test macro constructor with macro instantiation (success)
- [ ] Test regular constructor with macro instantiation (compile-time error)
- [ ] Test macro constructor with regular instantiation (compile-time error)
- [ ] Test compile-time error message content and clarity
- [ ] Test `new!` unevaluated argument handling

### 4.2 Inheritance validation tests
- [ ] Test child class inherits parent constructor type correctly
- [ ] Test mixed constructor types in inheritance
- [ ] Test super constructor call validation
- [ ] Test multi-level inheritance chains
- [ ] Test super constructor error messages

### 4.3 Edge case tests
- [ ] Test classes without constructors
- [ ] Test constructor type tracking accuracy
- [ ] Test GIR serialization/deserialization with new field
- [ ] Test performance impact of validation

### 4.4 Backward compatibility tests
- [ ] Verify all existing tests continue to pass
- [ ] Test existing constructor patterns work unchanged
- [ ] Test existing inheritance patterns work unchanged
- [ ] Run full test suite to ensure no regressions

## Phase 5: Documentation

### 5.1 Update language documentation
- [ ] Update constructor syntax documentation
- [ ] Add macro constructor examples
- [ ] Document super constructor syntax for both types
- [ ] Add error handling guide

### 5.2 Update examples
- [ ] Add macro constructor examples to `examples/oop.gene`
- [ ] Create standalone constructor example files
- [ ] Update section 2.18 (macro constructor) to reflect implementation
- [ ] Add best practices documentation

## Validation

### Success Criteria Verification
- [ ] All constructor validation scenarios work as specified
- [ ] All super constructor scenarios work as specified
- [ ] Error messages are clear and actionable
- [ ] Backward compatibility is maintained
- [ ] Performance impact is minimal
- [ ] Documentation is complete and accurate

### Final Testing
- [ ] Run `nimble test` - all Nim tests pass
- [ ] Run `./testsuite/run_tests.sh` - all language tests pass
- [ ] Run `openspec validate implement-macro-constructors --strict` - all validations pass
- [ ] Manual testing of edge cases and error conditions