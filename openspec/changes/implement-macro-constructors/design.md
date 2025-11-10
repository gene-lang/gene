# Macro Constructor Design

## Overview

This design describes how to implement complete macro constructor support by treating macro constructors as regular methods. This simplifies the implementation by removing special VM instructions and leveraging the existing function call infrastructure.

## Architecture

### Current State Analysis

Gene already has:
- `.ctor!` syntax for defining macro constructors
- `new!` syntax for calling macro constructors
- `IkNewMacro` VM instruction (to be removed)
- Partial quote-level handling for unevaluated arguments

What's missing:
- Constructor type tracking in Class metadata
- Validation to prevent mismatched usage
- Super constructor support for macro constructors
- Clear error messages

### Design Decisions

1. **Simplify Model**: Remove `IkNewMacro` instruction, treat macro constructors as regular methods
2. **Compile-Time Transformation**: `compile_new` transforms `(new! Class ...)` to regular method calls
3. **Track Constructor Type in Class**: Add `has_macro_constructor` flag to Class
4. **Extend Super Syntax**: Add `(super .ctor!)` support alongside existing `(super .ctor)`
5. **Clear Error Messages**: Provide actionable feedback for mismatches

### Simplified Approach

Instead of having special VM instructions for macro constructors, we:

1. **Define macro constructors** with `.ctor!` - creates constructor logic with unevaluated argument handling
2. **Call macro constructors** with `new!` - compiler handles this with dedicated logic
3. **Remove special VM handling** - no need for `IkNewMacro`, use existing constructor infrastructure

This means `(new! MyClass arg1 arg2)` is handled specially at compile time to pass arguments unevaluated.

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
- Set `has_macro_constructor = true` when processing `.ctor!`
- Leave as `false` for regular `.ctor`
- `.ctor!` creates constructor with unevaluated argument handling

**Simplified `compile_new` function**:
```nim
proc compile_new(self: Compiler, gene: ptr Gene) =
  # Check if this is a macro constructor call (new!)
  let is_macro_new = gene.type.kind == VkSymbol and gene.type.str == "new!"

  if is_macro_new:
    # Handle macro constructor with unevaluated arguments
    if gene.children.len == 0:
      not_allowed("new! requires at least a class name")

    # Validate class has macro constructor
    let class_expr = gene.children[0]
    # ... validation logic ...

    # Compile class and arguments with quote level for unevaluated args
    self.compile(class_expr)

    self.quote_level.inc()
    for i in 1..<gene.children.len:
      self.compile(gene.children[i])
    self.quote_level.dec()

    # Use existing constructor infrastructure (no special VM instruction needed)
    self.emit(Instruction(kind: IkNew))
  else:
    # Regular constructor compilation (existing logic)
    # ... existing IkNew handling ...
```

**Super Constructor Support**:
- Add `super .ctor!` case in `compile_gene`
- Handle quote level appropriately for macro super calls

**Validation**:
- Add compile-time validation for `new`/`new!` vs constructor type mismatches
- Provide clear error messages at compile time rather than runtime

### 3. VM Changes

**File**: `src/gene/vm.nim`

**Remove IkNewMacro Handler**:
- Delete the `IkNewMacro` case from the VM dispatch
- No special runtime handling needed - uses regular method dispatch

**Super Constructor Handling**:
- Extend existing super call mechanism to handle both regular and macro cases
- Maintain proper caller context for macro super calls

### 4. Error Messages

**Clear, Actionable Messages**:
- "Constructor mismatch: Class 'Foo' has a macro constructor, use 'new!' instead of 'new'"
- "Constructor mismatch: Class 'Bar' has a regular constructor, use 'new' instead of 'new!'"
- "Super constructor mismatch: Parent class has a macro constructor, use '(super .ctor!)' instead of '(super .ctor)'"

## Implementation Phases

### Phase 1: Simplify Infrastructure
1. Remove `IkNewMacro` instruction from VM and types
2. Update `compile_new` to transform `new!` calls to method calls
3. Update constructor definition to create regular methods

### Phase 2: Constructor Type Tracking
1. Add `has_macro_constructor` field to Class
2. Set flag during `.ctor!` processing
3. Add compile-time validation for `new`/`new!` mismatches

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

- All existing `.ctor` and `new` code continues to work unchanged
- Only new validation errors are introduced for previously incorrect usage
- GIR format changes are additive only