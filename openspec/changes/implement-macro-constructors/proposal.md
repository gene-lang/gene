# Implement Macro Constructors

## Summary

Implement complete macro constructor support in Gene following the design in `docs/constructor_design.md`. This includes validation, error handling, and super constructor calls to provide a clean, consistent syntax for constructors that receive unevaluated arguments.

## Why

Gene currently has partial macro constructor support but lacks proper validation and super constructor support. Users can define macro constructors with `.ctor!` and call them with `new!`, but:

1. **No Validation**: `new` can be used with macro constructors and `new!` with regular constructors, leading to runtime errors that are hard to debug
2. **No Super Support**: Inherited classes cannot properly call parent macro constructors with `(super .ctor!)`
3. **Poor Error Messages**: When something goes wrong, errors are cryptic and don't guide users to the solution
4. **Incomplete Feature**: The feature is half-implemented, making it unreliable for production use

This change completes the macro constructor feature to make it a first-class, reliable part of the language that follows the same `!` convention used throughout Gene for indicating unevaluated arguments.

## Problem Statement

Currently Gene has partial support for macro constructors (`.ctor!` and `new!`) but lacks proper validation and super constructor support. Users can:

1. Define macro constructors with `.ctor!`
2. Call them with `new!`

But the system lacks:
- Validation to prevent mismatched constructor/instance pairs
- Super constructor support `(super .ctor!)`
- Clear error messages for incorrect usage

## Goals

1. **Validation**: Ensure `new` is only used with regular constructors and `new!` only with macro constructors
2. **Super Support**: Add `(super .ctor!)` syntax for macro super constructor calls
3. **Error Messages**: Provide clear, helpful error messages for mismatches
4. **Backward Compatibility**: Maintain full compatibility with existing code

## Scope

The implementation spans multiple systems:

1. **Type System** (`src/gene/types.nim`): Track constructor type in Class metadata
2. **Compiler** (`src/gene/compiler.nim`): Add validation for constructor calls and super calls
3. **VM** (`src/gene/vm.nim`): Runtime validation and error throwing
4. **Testing**: Comprehensive test coverage for all scenarios

## Success Criteria

- [ ] `new Class` works with regular constructors, throws clear error with macro constructors
- [ ] `new! Class` works with macro constructors, throws clear error with regular constructors
- [ ] `(super .ctor!)` works in inherited classes with macro constructors
- [ ] All error messages are clear and actionable
- [ ] Existing tests continue to pass
- [ ] New tests cover all constructor patterns
- [ ] Documentation is updated with examples

## Out of Scope

- Constructor overloading (multiple constructors per class)
- Constructor attributes/decorators
- Automatic default constructor generation
- Advanced metaprogramming with constructors

## Dependencies

- Existing macro-like function infrastructure
- Current `.ctor!` and `new!` partial implementation
- VM instruction set (`IkNew`, `IkNewMacro`)