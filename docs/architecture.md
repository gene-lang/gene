# Gene VM Architecture

## Overview

Gene is a general-purpose programming language implemented in Nim using a **three-stage pipeline**: **Parser → Compiler → VM**. This document describes the architecture of the VM-based implementation.

## Architecture Flow

```
source.gene → Parser → AST → Compiler → Bytecode → VM → Result
```

## Core Components

### 1. Main Program (`src/gene.nim`)
- **Command-line interface** with `CommandManager`
- **Routes** commands: run, eval, repl, parse, compile
- **Initializes** the VM and runtime environment

### 2. Parser (`src/gene/parser.nim`)
- **Input**: Gene source code (S-expressions)
- **Output**: AST as nested `Value` objects
- **Features**: 
  - Macro expansion during parsing
  - String interpolation (`#"{expression}"`)
  - Complex symbols (namespaced like `a/b/c`)
  - Comments and metadata handling
- **Key Function**: `read_all` converts entire source to AST

### 3. Compiler (`src/gene/compiler.nim`)
- **Input**: AST from parser
- **Output**: Bytecode in `CompiledUnit`
- **Process**:
  1. Traverses AST recursively
  2. Generates stack-based VM instructions
  3. Manages constant pool and variable bindings
  4. Handles special forms (if, fn, let, etc.)
- **Key Function**: `compile` produces executable bytecode

### 4. Virtual Machine (`src/gene/vm.nim`)
- **Input**: Compiled bytecode
- **Stack-based** execution model
- **Components**:
  - Instruction pointer (PC)
  - Value stack
  - Call frames
  - Exception handlers
- **Key Function**: `exec` runs bytecode

## Type System (`src/gene/types.nim`)

Gene uses a **discriminated union** approach for values:

```nim
type
  ValueKind* = enum
    VkNil, VkBool, VkInt, VkFloat, VkChar, VkString,
    VkSymbol, VkArray, VkMap, VkSet, VkTuple, VkRecord,
    VkFunction, VkMacro, VkClass, VkInstance, VkNamespace,
    VkFuture, VkChannel, VkError, ...
    
  Value* = object
    case kind*: ValueKind
    of VkInt: int_val: int64
    of VkString: str_val: string
    of VkArray: arr_val: seq[Value]
    # ... etc
```

### NaN-Boxing Optimization
The VM is designed to support NaN-boxing where all values fit in 64 bits:
- Immediate values: nil, bool, int (up to 52 bits)
- Pointer values: strings, arrays, objects (48-bit pointers)

## VM Instruction Set

The VM uses ~100 instructions categorized as:

### Stack Operations
- `IkPush` - Push constant
- `IkPop` - Pop and discard
- `IkDup` - Duplicate top

### Arithmetic
- `IkAdd`, `IkSub`, `IkMul`, `IkDiv`
- `IkMod`, `IkPow`

### Comparison
- `IkEq`, `IkNe`, `IkLt`, `IkGt`, `IkLe`, `IkGe`

### Control Flow
- `IkJump` - Unconditional jump
- `IkJumpIfFalse` - Conditional jump
- `IkCall` - Function call
- `IkReturn` - Return from function

### Data Structure Operations
- `IkCreateArray`, `IkArrayGet`, `IkArraySet`
- `IkCreateMap`, `IkMapGet`, `IkMapSet`
- `IkCreateClass`, `IkCreateInstance`

### Variable Management
- `IkVarDefine` - Define new variable
- `IkVarGet` - Load variable
- `IkVarSet` - Store to variable

## Memory Management

Currently uses Nim's reference counting (ARC/ORC) for automatic memory management. Future optimizations may include:
- Object pooling for common types
- Arena allocation for short-lived values
- Custom allocator for better cache locality

## Extension System

Gene supports dynamic loading of extensions written in C/Nim:
- Extensions export initialization functions
- Share symbol table with main VM
- Can define new functions and types

## Compilation Process

### 1. Symbol Resolution
- Maintains symbol table during compilation
- Resolves variable references to stack indices
- Handles lexical scoping

### 2. Instruction Selection
- Maps AST nodes to VM instructions
- Optimizes simple patterns (constant folding)
- Generates efficient instruction sequences

### 3. Code Generation
```nim
# Example: (+ 1 2) generates:
IkPushConst 0  # Push 1
IkPushConst 1  # Push 2
IkAdd          # Add top two values
```

## Execution Model

### Stack Machine
- All operations work on an operand stack
- Function calls create new frames
- Local variables stored in frame slots

### Example Execution
```gene
(fn add [a b] (+ a b))
(add 1 2)
```

Generates:
```
IkFunction 0      # Create function
IkVarDefine 0     # Define 'add'
IkVarGet 0        # Load 'add' 
IkPushConst 1     # Push 1
IkPushConst 2     # Push 2
IkCall 2          # Call with 2 args
```

## Performance Characteristics

### Current Performance
- ~600K function calls/second (recursive fibonacci)
- Primary bottlenecks:
  - Memory allocation (15% in newSeq)
  - Function call overhead (11% in exec)
  - Type checking (8% in kind checks)

### Optimization Opportunities
1. **Inline caching** - Cache method lookups
2. **Specialized instructions** - Common patterns
3. **Frame pooling** - Reuse call frames
4. **Better value representation** - Full NaN-boxing

## Future Enhancements

### Planned Features
- Just-In-Time (JIT) compilation
- Tail call optimization
- Coroutines and green threads
- Better debugging support

### Long-term Goals
- Self-hosting compiler
- Native code generation