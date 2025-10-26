# Ideas from Wren for Gene Optimization

This document analyzes how Wren's design philosophy and implementation patterns could be applied to make Gene smaller, faster, and more maintainable.

## Overview

Wren is a small, fast, class-based concurrent scripting language that demonstrates excellent design principles for embedding languages. Gene could benefit significantly from adopting several of Wren's core ideas.

## Current State Analysis

### Gene's Current Complexity
- **Code Size**: ~19,712 lines of Nim code (vs Wren's ~3,400 semicolons)
- **Type System**: 324+ ValueKind variants (vs Wren's ~10 core types)
- **File Structure**: Large monolithic files (`vm.nim` is 216KB, `types.nim` is 109KB)
- **Instruction Set**: Complex with many specialized instructions
- **Memory Model**: Manual memory management with complex scope tracking

### Wren's Approach
- **Compact Implementation**: Under 4,000 semicolons, highly readable
- **Efficient Value Representation**: NaN tagging for numbers and objects
- **Simple Object Model**: Clean class-based system with unified dispatch
- **Optimized Bytecode**: Compact encoding with efficient instruction dispatch
- **X-Macro Pattern**: Single source of truth for opcodes and dispatch

## Key Wren Patterns for Gene

### 1. Value Representation Optimization

#### Current Gene Implementation
```nim
type Value* {.bycopy, shallow.} = distinct int64
type ValueKind* {.size: sizeof(int16)} = enum
  VkNil = 0, VkVoid, VkPlaceholder, VkPointer, VkAny, VkCustom
  VkBool, VkInt, VkRatio, VkFloat, VkBin, VkBin64, VkByte, VkBytes
  VkChar, VkString, VkSymbol, VkComplexSymbol
  # ... 300+ more variants
```

#### Wren-Style NaN Tagging
```nim
type Value* = distinct uint64

const
  QNAN: uint64 = 0x7ffc000000000000
  TAG_NIL: uint64 = QNAN or 1
  TAG_FALSE: uint64 = QNAN or 2
  TAG_TRUE: uint64 = QNAN or 3
  TAG_OBJECT: uint64 = QNAN or 4

template isNumber*(v: Value): bool = (v.uint64 and 0xFFF0000000000000) != QNAN
template isObj*(v: Value): bool = not v.isNumber()

template asNumber*(v: Value): float = cast[float](v.uint64)
template asObj*(v: Value): pointer = cast[pointer](v.uint64 and 0x0000ffffffffffff)

template numberValue*(n: float): Value = cast[Value](n)
template objValue*(obj: pointer): Value = Value(QNAN or cast[uint64](obj))
```

**Benefits:**
- Eliminate most ValueKind variants (reduce from 324+ to ~10)
- Faster type checking (bit operations vs enum comparisons)
- Memory-efficient representation
- Direct number storage without boxing

### 2. Simplified Object Model

#### Current Gene Complexity
Gene has dozens of specialized object types with complex inheritance hierarchies.

#### Wren-Style Unified Model
```nim
type
  ObjKind* = enum
    ObjString, ObjList, ObjMap, ObjClass, ObjFn, ObjClosure, ObjFiber

  Obj* = ref object
    kind*: ObjKind
    next*: Obj        # For GC linked list
    isDark*: bool     # GC mark bit
    case kind*: ObjKind
    of ObjString:
      strValue*: string
      hash*: uint32
    of ObjList:
      elements*: seq[Value]
    of ObjMap:
      entries*: seq[MapEntry]
    of ObjClass:
      name*: string
      superClass*: ObjClass
      methods*: Table[string, Value]
    # ... other cases

  MapEntry* = object
    key*: Value
    value*: Value
```

**Benefits:**
- Single allocation path for all objects
- Unified garbage collection
- Simplified method dispatch
- Easier to understand and maintain

### 3. Instruction Set Optimization

#### Current Gene Approach
Large instruction enum with complex argument encoding:
```nim
type InstructionKind* = enum
  IkNoop, IkPushValue, IkPop, IkDup, IkSwap, IkAdd, IkSub, IkMul, IkDiv
  # ... 100+ more instructions
```

#### Wren-Style X-Macro Pattern
```nim
# instruction_defines.nim - Single source of truth
template defineInstructions*() =
  const INSTRUCTIONS = [
    ("CONSTANT", 1),      # arg: constant index
    ("NULL", 1),          # pushes null
    ("FALSE", 1),         # pushes false
    ("TRUE", 1),          # pushes true
    ("LOAD_LOCAL_0", 1),  # optimized local access
    ("LOAD_LOCAL_1", 1),
    # ... up to LOAD_LOCAL_8
    ("LOAD_LOCAL", 1),    # arg: local index
    ("STORE_LOCAL", 0),   # arg: local index
    ("CALL_0", 0),        # call with 0 args
    ("CALL_1", -1),       # call with 1 arg
    # ... up to CALL_16
    ("RETURN", 0),
    ("JUMP", 0),          # arg: jump offset
    ("JUMP_IF", -1),      # arg: jump offset
  ]

# Auto-generate enum
macro generateInstructionEnum*(): untyped =
  result = newTree(nnkTypeSection)
  let enumDef = newNimNode(nnkEnumTy)
  enumDef.add(newEmptyNode())

  for (name, _) in INSTRUCTIONS:
    enumDef.add(ident(name))

  result.add(newNimNode(nnkTypeDef).add(
    ident("InstructionKind"),
    newEmptyNode(),
    enumDef
  ))

# Auto-generate dispatch table
macro generateDispatch*(): untyped =
  result = newTree(nnkStmtList)
  let caseStmt = newNimNode(nnkCaseStmt).add(newDotExpr(ident("inst"), ident("kind")))

  for (name, stackEffect) in INSTRUCTIONS:
    let branch = newTree(nnkOfBranch, ident(name))
    # Add instruction handling code here
    branch.add(newCommentStmtNode(stackEffect))
    caseStmt.add(branch)

  result.add(caseStmt)
```

**Benefits:**
- Single source of truth for instructions
- Automatic consistency between enum and dispatch
- Easy to add new instructions
- Reduced boilerplate code
- Stack effect tracking for validation

### 4. Memory Management Simplification

#### Current Gene Approach
Manual memory management with complex scope tracking and reference counting.

#### Wren-Style Mark-and-Sweep GC
```nim
type
  GC* = ref object
    bytesAllocated*: size_t
    nextGC*: size_t
    firstObj*: Obj
    grayStack*: ptr Obj
    grayCount*: int
    grayCapacity*: int

proc collectGarbage*(gc: GC) =
  # Mark phase
  gc.markRoots()

  # Sweep phase
  var obj = gc.firstObj
  while obj != nil:
    let next = obj.next
    if not obj.isDark:
      dealloc(cast[pointer](obj))
    else:
      obj.isDark = false
      obj = next

  gc.bytesAllocated = 0
```

**Benefits:**
- Simpler memory management
- No manual reference counting
- Easier to reason about
- Automatic cleanup of cycles

### 5. Error Handling Simplification

#### Current Gene Approach
Multiple exception types and complex error propagation paths.

#### Wren-Style Simple Error Model
```nim
type
  RuntimeError* = object of CatchableError
    line*: int
    column*: int
    message*: string

  ParseError* = object of CatchableError
    line*: int
    column*: int
    message*: string

proc error*(line, column: int, message: string) {.noreturn.} =
  raise RuntimeError(line: line, column: column, message: message)
```

**Benefits:**
- Consistent error handling
- Clear error messages
- Easier debugging
- Reduced code complexity

### 6. Compiler-VM Integration

#### Wren's Single-Pass Compilation
Wren uses a single-pass compiler that directly emits bytecode without building an AST.

```nim
proc compile*(compiler: Compiler, source: string) =
  var parser = Parser(source: source)

  while not parser.isAtEnd():
    let expr = parser.expression()
    compiler.emitExpression(expr)
    if not parser.isAtEnd():
      compiler.emitByte(OP_POP)  # Discard expression result
```

**Benefits:**
- Faster compilation
- Lower memory usage
- Simpler implementation
- Immediate error detection

## Implementation Strategy

### Phase 1: Low-Hanging Fruit (Quick Wins)

1. **Implement X-Macro Pattern for Instructions**
   - Create instruction definition macros
   - Auto-generate dispatch table
   - Maintain backward compatibility
   - Expected impact: 10-20% performance improvement

2. **Optimize Hot Instruction Paths**
   - Profile VM to find most used instructions
   - Implement superinstructions for common patterns
   - Optimize instruction dispatch
   - Expected impact: 15-25% performance improvement

3. **Consolidate Similar ValueKind Variants**
   - Group related types (e.g., all number types)
   - Reduce enum complexity
   - Maintain API compatibility
   - Expected impact: Simplified codebase

### Phase 2: Medium Impact Changes

1. **Implement NaN Tagging for Values**
   - Replace Value type implementation
   - Update all value operations
   - Maintain compatibility layer
   - Expected impact: 20-40% performance improvement

2. **Simplify Error Handling**
   - Consolidate exception types
   - Improve error messages
   - Standardize error propagation
   - Expected impact: Reduced complexity

### Phase 3: High Impact, High Risk

1. **Unified Object Model**
   - Consolidate object types
   - Implement unified dispatch
   - Simplify inheritance hierarchies
   - Expected impact: 30-50% performance improvement

2. **Memory Management Optimization**
   - Simplify scope management
   - Implement object pooling
   - Optimize garbage collection
   - Expected impact: Better memory efficiency

## Expected Benefits

### Performance Improvements
- **VM Execution**: 20-50% faster (better instruction dispatch, value operations)
- **Compilation**: 30-60% faster (single-pass, direct bytecode emission)
- **Memory Usage**: 20-40% reduction (compact value representation, efficient GC)
- **Garbage Collection**: 50-70% faster (simplified object model)

### Code Quality Improvements
- **Code Size**: 30-50% reduction (eliminate redundancy, consolidate functionality)
- **Complexity**: Significant reduction in cognitive load
- **Maintainability**: Easier to understand and modify
- **Testing**: Simpler to test and debug

### Developer Experience
- **Faster Development**: Easier to add new features
- **Better Debugging**: Clearer error messages and simpler execution model
- **Documentation**: Easier to document complex interactions
- **Contributions**: Lower barrier for new contributors

## Trade-offs and Considerations

### Breaking Changes
- Some ValueKind variants will be consolidated
- Certain internal APIs will change
- Some edge cases may behave differently
- Migration path needed for existing code

### Feature Compatibility
- Most language features can be preserved
- API compatibility layers can be maintained
- Gradual migration approach possible
- Backward compatibility for user code

### Development Effort
- Significant refactoring required
- Thorough testing needed
- Performance benchmarking
- Documentation updates

## Conclusion

Wren demonstrates that a powerful, fast scripting language can be implemented with remarkable simplicity. By adopting Wren's core design principles, Gene could achieve:

1. **Significant performance improvements** through optimized value representation and instruction dispatch
2. **Dramatic code size reduction** through consolidation and simplification
3. **Better maintainability** through cleaner architecture
4. **Enhanced developer experience** through simpler debugging and development

The key is to implement these changes gradually, starting with the highest-impact, lowest-risk changes and working toward more significant architectural improvements. The result would be a Gene that retains its Lisp-like character and advanced features while being much more like Wren in terms of simplicity, performance, and elegance.

## References

- [Wren Programming Language](https://wren.io/)
- [Wren Source Code](https://github.com/wren-lang/wren)
- [Wren Virtual Machine](https://wren.io/vm.html)
- [Wren Bytecode Design](https://wren.io/vm.html#bytecode)