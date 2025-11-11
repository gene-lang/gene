# Complex Symbol Access Implementation Design

## Architecture Overview

The complex symbol access system uses a **compile-time stack-based approach** that leverages existing Gene VM infrastructure. Instead of complex container expression evaluation, the compiler transforms complex symbols into sequences of existing VM instructions.

## Core Components

### 1. Symbol Rewriter (Compiler Layer)

**Location**: `src/gene/compiler.nim` - `rewrite_complex_symbol()` function

The rewriter processes definition targets before bytecode generation using stack-based compilation:

```nim
proc rewrite_complex_symbol(self: Compiler, gene: ptr Gene): ptr Gene =
  # Input: (class A/B/C ...)
  # Process: Compile A → push to stack
  #          Compile B → as member of stack top → push result
  #          Compile C → as member of stack top (which is B)
  # Output: C class definition
```

**Compilation Strategy**:
1. **Segment analysis**: Split complex symbol into segments
2. **Stack compilation**: Compile prefix segments left-to-right, pushing results to stack
3. **Member creation**: Compile final segment as member of stack top
4. **Leading slash handling**: `/x` → compile `self` and push to stack

### 2. Stack Management System

**Location**: `src/gene/compiler.nim` - enhanced compilation logic

The system manages stack ordering for multi-segment symbols:
- Each prefix segment is compiled and pushed to stack
- Stack maintains proper nesting for deep hierarchies
- Final definition uses stack top as container
- Stack is properly managed after compilation

### 2. VM Instruction Enhancement

**Location**: `src/gene/vm.nim` - Enhanced class creation and member handling

The system leverages existing VM instructions with potential minor enhancements:

- **IkClass**: Standard class creation
- **IkClassAsMember**: Create class as member of existing object (or extend IkClass)
- **IkSetMember**: Set property on object (used for final assignment)
- **IkSetChild**: Set child element in array/gene (used for numeric segments)

**Required Enhancements**:
- **IkClassAsMember**: Implement if not exists, or extend IkClass with member flag
- **Stack Context**: Ensure member creation works with current stack state

### 3. Enhanced Parser Integration

**Location**: `src/gene/parser.nim` - Complex symbol recognition

Parser already supports `VkComplexSymbol` but needs integration with definition contexts:
- Class definitions: `(class namespace/ClassName ...)`
- Variable declarations: `(var container/variable value)`
- Assignment targets: `(container/property = value)`

## Implementation Strategy

### Phase 1: Core Symbol Parser and Rewriter
1. Create `parse_complex_symbol()` function to split symbols into segments
2. Implement `rewrite_complex_symbol()` using stack-based compilation
3. Add logic for leading slash detection and handling
4. Create comprehensive unit tests for parser and rewriter

### Phase 2: VM Instruction Enhancement
1. Implement `IkClassAsMember` or extend `IkClass` with member flag
2. Ensure proper stack context handling for member creation
3. Add integration tests for class-as-member functionality
4. Validate member creation with different container types

### Phase 3: Compiler Integration
1. Integrate rewriter with `compile_class()` for class definitions
2. Add support for variable declarations with complex targets
3. Enhance assignment compilation for complex symbol targets
4. Ensure proper stack management throughout compilation

### Phase 4: Multi-segment and Numeric Handling
1. Implement proper stack management for multi-segment symbols
2. Add numeric segment detection and child access integration
3. Test complex scenarios like `A/B/C` and `arr/0/1`
4. Validate stack ordering and proper container resolution

### Phase 5: Testing and Validation
1. Create comprehensive test suite covering all rewrite scenarios
2. Test integration with existing namespace and property access systems
3. Validate performance with deeply nested symbols
4. Ensure backward compatibility with existing codebase
5. Add integration tests for edge cases and error conditions

## Technical Details

### Stack-Based Compilation

Complex symbols are compiled using stack-based resolution before bytecode generation:

```gene
(var /x value)
; Compilation:
; 1. Compile self and push to stack
; 2. Compile x as member of stack top
; 3. Result: x property set on current instance
```

```gene
(class A/B/C ...)
; Compilation:
; 1. Compile A → push to stack
; 2. Compile B as member of A → push result to stack
; 3. Compile C as member of stack top (which is B)
; 4. Result: C class stored as member of B
```

### Numeric Segment Handling

Numeric trailing segments use child access instead of member access:

```gene
(arr/0 = 10)
; Compiles to IkSetChild with index 0
; Not IkSetMember with string key "0"
```

### Backward Compatibility

All existing symbol access patterns remain unchanged:
- Simple symbols: `x`, `className`
- Property access: `obj/property`
- Array indexing: `array[index]`
- Basic namespaces: `(ns name)`

The rewriter only processes complex symbols in definition contexts:
- Class definition targets: `(class complex/symbol ...)`
- Variable declaration targets: `(var complex/symbol value)`
- Assignment targets: `(complex/symbol = value)`

### Stack Management Protocol

The stack-based compilation follows this protocol:

1. **Container Compilation**: Compile the container expression and push result to stack
2. **Member Creation**: Compile the final segment as member of stack top
3. **Stack Cleanup**: Ensure proper stack management after compilation
4. **Error Handling**: Validate container types and provide clear error messages

### Multi-Segment Resolution

For symbols with more than two segments (A/B/C/D):
1. Compile A → push to stack
2. Compile B as member of A → push result to stack
3. Compile C as member of stack top (which is B) → push result to stack
4. Compile D as member of stack top (which is C)
5. Stack maintains proper nesting for deep hierarchies

## Error Handling

**Compile-time Errors**:
- Invalid complex symbol syntax (empty segments, invalid characters)
- Malformed symbol paths
- Invalid container expressions (detected during compilation)

**Runtime Errors**:
- Container doesn't support member setting
- Invalid numeric index for child access
- Stack overflow in deeply nested symbols
- Container type validation failures

## Performance Considerations

- **Zero Runtime Overhead**: Complex symbols resolved at compile time using existing VM instructions
- **Stack Efficiency**: Minimal stack operations for container resolution
- **Instruction Optimization**: Use existing IkClassAsMember, IkSetMember, IkSetChild
- **No Dynamic Evaluation**: No runtime container expression evaluation needed
- **Optimization**: Simple symbols bypass rewriting entirely for fast compilation

## Testing Strategy

Test suite will cover:
1. **Stack-based compilation**: Simple two-segment symbols with proper stack management
2. **Multi-segment**: Deep nesting with 3+ segments and stack validation
3. **VM instruction generation**: Correct IkClassAsMember, IkSetMember, IkSetChild usage
4. **Container types**: Namespaces, instances, maps, arrays with compile-time resolution
5. **Edge cases**: Empty segments, invalid characters, stack overflow protection
6. **Integration**: Existing code compatibility, performance benchmarks vs current approach
7. **Leading slash handling**: Proper self container compilation in different contexts

## Future Extensions

The design accommodates future enhancements:
- Module system integration with namespace-aware compilation
- Global namespace support with context-aware symbol resolution
- Import/export functionality for complex symbols across modules
- Advanced error reporting with source locations and suggestions
- IDE integration with symbol navigation and refactoring support