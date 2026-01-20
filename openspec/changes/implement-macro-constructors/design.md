# Macro Constructor Design

## Overview

This design describes how to implement complete macro constructor support by treating macro constructors as regular methods. This simplifies the implementation by removing special VM instructions and leveraging the existing function call infrastructure.

## Architecture

### Current State Analysis

Gene already has:
- `ctor!` syntax for defining macro constructors
- `new!` syntax for calling macro constructors
- `IkNewMacro` VM instruction (to be removed)
- Partial quote-level handling for unevaluated arguments

What's missing:
- Constructor type tracking in Class metadata
- Validation to prevent mismatched usage
- Super constructor support for macro constructors
- Clear error messages

### Design Decisions

1. **Simplify Model**: Remove `IkNewMacro` instruction, use existing `IkNew` with enhanced validation
2. **Dual Validation**: Both compile-time and runtime validation for safety with dynamic instantiation
3. **Preserve Gene Wrapper**: Keep `IkGeneStart`/`IkGeneAddChild`/`IkGeneEnd` for unevaluated arguments
4. **Track Constructor Type in Class**: Add `has_macro_constructor` flag to Class
5. **Extend Super Syntax**: Add `(super .ctor!)` support alongside existing `(super .ctor)`
6. **Clear Error Messages**: Provide actionable feedback for mismatches

### Hybrid Approach

We combine compile-time and runtime approaches:

1. **Define macro constructors** with `ctor!` - creates constructor with unevaluated argument handling
2. **Call macro constructors** with `new!` - compiler handles with Gene wrapper for unevaluated args
3. **Dual validation** - compile-time checks for static cases, runtime checks for dynamic cases
4. **Unified VM path** - use existing `IkNew` with enhanced validation logic

This means `(new! MyClass arg1 arg2)` gets special treatment to pass arguments unevaluated while maintaining runtime safety.

## Implementation Details

### 1. Type System Changes

**File**: `src/gene/types.nim`

Add constructor type tracking to Class:

```nim
ClassObj* = ref object
  # ... existing fields ...
  has_macro_constructor*: bool  # NEW: Track if class has macro constructor
```

Remove `IkNewMacro` instruction from InstructionKind enum.

### 2. Compiler Changes

**File**: `src/gene/compiler.nim`

**Constructor Definition Tracking**:
- Set `has_macro_constructor = true` when processing `ctor!`
- Leave as `false` for regular `ctor`
- `ctor!` creates constructor with unevaluated argument handling

**Enhanced `compile_new` function**:
```nim
proc compile_new(self: Compiler, gene: ptr Gene) =
  # Check if this is a macro constructor call (new!)
  let is_macro_new = gene.type.kind == VkSymbol and gene.type.str == "new!"

  if is_macro_new:
    # Handle macro constructor with unevaluated arguments
    if gene.children.len == 0:
      not_allowed("new! requires at least a class name")

    # Compile the class
    self.compile(gene.children[0])

    # Wrap arguments in Gene for unevaluated passing (preserves AST)
    self.emit(Instruction(kind: IkGeneStart))

    self.quote_level.inc()
    for i in 1..<gene.children.len:
      self.compile(gene.children[i])
      self.emit(Instruction(kind: IkGeneAddChild))
    self.quote_level.dec()

    self.emit(Instruction(kind: IkGeneEnd))
    self.emit(Instruction(kind: IkNew))
  else:
    # Regular constructor compilation with validation
    # ... existing IkNew handling with added checks for macro constructor mismatches ...
```

**Super Constructor Support**:
- Add `super .ctor!` case in `compile_gene`
- Handle quote level appropriately for macro super calls

**Validation**:
- Add compile-time validation for `new`/`new!` vs constructor type mismatches
- Provide clear error messages at compile time rather than runtime

### 3. VM Changes

**File**: `src/gene/vm.nim`

**Enhanced IkNew Handler**:
- Add runtime validation in `IkNew` handler for constructor type mismatches
- Check `class.has_macro_constructor` against call type (evaluated vs unevaluated args)
- Provide clear error messages for dynamic scenarios

**Remove IkNewMacro Handler**:
- Delete the `IkNewMacro` case from the VM dispatch
- All constructor calls use unified `IkNew` path

**Super Constructor Handling**:
- Extend existing super call mechanism to handle both regular and macro cases
- Maintain proper caller context for macro super calls

### 4. Error Messages

**Clear, Actionable Messages**:
- **Compile-time**: "Constructor mismatch: Class 'Foo' has a macro constructor, use 'new!' instead of 'new'"
- **Compile-time**: "Constructor mismatch: Class 'Bar' has a regular constructor, use 'new' instead of 'new!'"
- **Runtime**: "Cannot instantiate macro constructor 'Foo' with evaluated arguments, use 'new!'"
- **Runtime**: "Cannot instantiate regular constructor 'Bar' with unevaluated arguments, use 'new'"
- "Super constructor mismatch: Parent class has a macro constructor, use '(super .ctor!)' instead of '(super .ctor)'"

## Implementation Phases

### Phase 1: Simplify Infrastructure
1. Remove `IkNewMacro` instruction from VM and types
2. Update `compile_new` to preserve Gene wrapper for unevaluated arguments
3. Enhance `IkNew` handler with runtime validation
4. Update constructor definition to handle unevaluated arguments

### Phase 2: Constructor Type Tracking
1. Add `has_macro_constructor` field to Class
2. Set flag during `ctor!` processing
3. Add compile-time validation for `new`/`new!` mismatches
4. Add runtime validation in VM for dynamic scenarios

### Phase 3: Super Constructor Support
1. Add `(super .ctor!)` syntax parsing
2. Implement macro super call handling
3. Test inheritance scenarios

### Phase 4: Testing & Documentation
1. Comprehensive test coverage
2. Update documentation
3. Verify backward compatibility

## Edge Cases & Considerations

### Inheritance Chains
When a class inherits from another with a macro constructor:
- Child constructors must explicitly call `(super .ctor!)` if needed
- Validation should work correctly through inheritance chains

### Error Context
Error messages should include:
- The class name involved
- What the user tried to do (e.g., "use 'new' with macro constructor")
- What they should do instead (e.g., "use 'new!' instead")

### GIR Compatibility
Changes must be compatible with existing GIR cache:
- New Class field needs proper serialization
- Avoid breaking cached bytecode

## Performance Considerations

- Constructor type tracking adds minimal overhead (one boolean field)
- Runtime validation adds one branch check per constructor call
- No impact on existing regular constructor performance

## Backward Compatibility

- All existing `ctor` and `new` code continues to work unchanged
- Only new validation errors are introduced for previously incorrect usage
- GIR format changes are additive only