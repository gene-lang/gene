# Location Tracking Data Flow

## Overview Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                         SOURCE CODE                             │
│                     examples/test.gene                          │
│  1: (fn add [a b]                                               │
│  2:   (+ a b x))  ← Error: undefined 'x'                        │
│  3:                                                             │
│  4: (add 1 2)                                                   │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                      PARSER (parser.nim)                        │
│  • Tracks: filename, line, column via lexbase                   │
│  • Creates: SourceTrace for each Gene expression                │
│  • Maintains: trace_stack for nested expressions                │
│                                                                 │
│  Gene Expression:                                               │
│    type: fn                                                     │
│    trace: SourceTrace {                                         │
│      filename: "examples/test.gene"                             │
│      line: 1                                                    │
│      column: 1                                                  │
│    }                                                            │
│    children: [name, params, body]                               │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌───────────────────────────────────────────────────────────────────┐
│                     COMPILER (compiler.nim)                       │
│  • Receives: Gene AST with trace information                      │
│  • Maintains: trace_stack during compilation                      │
│  • Emits: Instructions with attached traces                       │
│                                                                   │
│  emit(Instruction) → CompilationUnit.add_instruction(instr, trace)│
│                                                                   │
│  CompilationUnit:                                                 │
│    instructions: [IkFunction, IkVarResolve, IkAdd, ...]           │
│    instruction_traces: [trace₁, trace₂, trace₃, ...]  (1:1)       │
└───────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                      GIR CACHE (gir.nim)                        │
│  • Serializes: CompilationUnit + instruction_traces             │
│  • Preserves: Full trace tree structure                         │
│  • Caches: build/*.gir files with location info                 │
│                                                                 │
│  Format:                                                        │
│    [instructions] [constants] [trace_tree] [trace_indices]      │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                    VIRTUAL MACHINE (vm.nim)                     │
│  • Executes: Instructions with pc (program counter)             │
│  • Tracks: cu.instruction_traces[pc] → current location         │
│  • On Error: Calls current_trace() → formats location           │
│                                                                 │
│  current_trace():                                               │
│    return cu.instruction_traces[pc]  // "test.gene:2:10"        │
│                                                                 │
│  format_runtime_exception():                                    │
│    "Gene exception at test.gene:2:10: undefined variable 'x'"   │
└─────────────────────────────────────────────────────────────────┘
```

## Detailed Flow for Single Expression

### Example: `(+ a b)`

```
┌──────────────────────────────────────────────────────────────────┐
│ Step 1: PARSING                                                  │
├──────────────────────────────────────────────────────────────────┤
│                                                                  │
│ Lexer position: line=2, col=3                                    │
│                                                                  │
│ Parser.read_gene():                                              │
│   1. Create Gene node                                            │
│   2. Call add_line_col(gene, bufpos)                             │
│   3. Create SourceTrace:                                         │
│      SourceTrace {                                               │
│        filename: "test.gene"                                     │
│        line: 2                                                   │
│        column: 3                                                 │
│        parent: <parent_trace>                                    │
│      }                                                           │
│   4. Attach to gene.trace                                        │
│   5. Push to parser.trace_stack                                  │
│                                                                  │
│ Result: Gene with embedded trace                                 │
└──────────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌──────────────────────────────────────────────────────────────────┐
│ Step 2: COMPILATION                                              │
├──────────────────────────────────────────────────────────────────┤
│                                                                  │
│ Compiler.compile(gene):                                          │
│   1. Push gene.trace to compiler.trace_stack                     │
│   2. Compile children:                                           │
│      - emit(IkVarResolve, "a")  ← trace = gene.trace             │
│      - emit(IkVarResolve, "b")  ← trace = gene.trace             │
│      - emit(IkAdd)              ← trace = gene.trace             │
│   3. Pop trace_stack                                             │
│                                                                  │
│ Compiler.emit(instr):                                            │
│   cu.add_instruction(instr, self.current_trace())                │
│                                                                  │
│ Result: CompilationUnit with parallel arrays                     │
│   instructions:       [IkVarResolve, IkVarResolve, IkAdd]        │
│   instruction_traces: [trace₁,      trace₂,       trace₃]        │
│                          ↓             ↓            ↓            │
│                    test.gene:2:3  test.gene:2:3  test.gene:2:3   │
└──────────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌──────────────────────────────────────────────────────────────────┐
│ Step 3: EXECUTION                                                │
├──────────────────────────────────────────────────────────────────┤
│                                                                  │
│ VM.exec():                                                       │
│   pc = 0: IkVarResolve "a"                                       │
│           current_trace = cu.instruction_traces[0]               │
│                         = SourceTrace{test.gene:2:3}             │
│           → resolve 'a' successfully                             │
│                                                                  │
│   pc = 1: IkVarResolve "b"                                       │
│           current_trace = cu.instruction_traces[1]               │
│           → resolve 'b' successfully                             │
│                                                                  │
│   pc = 2: IkAdd                                                  │
│           current_trace = cu.instruction_traces[2]               │
│           → compute sum                                          │
│                                                                  │
│ On Error:                                                        │
│   let trace = vm.current_trace()  // cu.instruction_traces[pc]   │
│   let location = trace_location(trace)  // "test.gene:2:3"       │
│   raise Exception("at " & location & ": " & error_msg)           │
└──────────────────────────────────────────────────────────────────┘
```

## Trace Tree Structure

For nested expressions, traces form a tree:

```
Root Trace (test.gene:1:1)
  │
  ├─ Function Definition (test.gene:1:1)
  │   │
  │   ├─ Parameter List (test.gene:1:8)
  │   │   ├─ Param 'a' (test.gene:1:9)
  │   │   └─ Param 'b' (test.gene:1:11)
  │   │
  │   └─ Function Body (test.gene:2:3)
  │       ├─ Symbol '+' (test.gene:2:4)
  │       ├─ Symbol 'a' (test.gene:2:6)
  │       ├─ Symbol 'b' (test.gene:2:8)
  │       └─ Symbol 'x' (test.gene:2:10) ← ERROR HERE
  │
  └─ Function Call (test.gene:4:1)
      ├─ Symbol 'add' (test.gene:4:2)
      ├─ Literal 1 (test.gene:4:6)
      └─ Literal 2 (test.gene:4:8)
```

## Current vs. Proposed Error Messages

### Current Implementation

```
Exception: undefined variable 'x'
```

**Information Available (but not fully used):**
- Current instruction trace: `test.gene:2:10`
- Call stack frames (in VM.frame chain)
- Each frame could theoretically track its source location

### With Stack Trace Enhancement

```
Gene exception at test.gene:2:10: undefined variable 'x'

Stack trace (most recent call first):
  at test.gene:2:10 in function 'add'
  at test.gene:4:1 in <module>
```

### With Source Context

```
Gene exception at test.gene:2:10: undefined variable 'x'

  1 | (fn add [a b]
  2 |   (+ a b x))
    |          ^

Stack trace:
  at test.gene:2:10 in function 'add'
  at test.gene:4:1 in <module>
```

## Key Data Structures

### SourceTrace

```nim
type SourceTrace* = ref object
  parent*: SourceTrace          # Parent expression
  children*: seq[SourceTrace]   # Child expressions
  filename*: string             # Source file
  line*: int                    # 1-based line number
  column*: int                  # 1-based column number
  child_index*: int             # Index in parent's children
```

**Usage:**
- Created during parsing for each Gene expression
- Attached to Gene AST nodes
- Propagated through compilation to instructions
- Preserved in GIR cache
- Accessed during runtime via `vm.cu.instruction_traces[vm.pc]`

### Gene (AST Node)

```nim
type Gene* = object
  ref_count*: int32
  type*: Value
  trace*: SourceTrace           # ← Location information
  props*: Table[Key, Value]
  children*: seq[Value]
```

### CompilationUnit

```nim
type CompilationUnit* = ref object
  id*: Id
  kind*: CompilationUnitKind
  instructions*: seq[Instruction]
  trace_root*: SourceTrace                    # ← Root of trace tree
  instruction_traces*: seq[SourceTrace]       # ← One per instruction
  labels*: Table[Label, int]
  inline_caches*: seq[InlineCache]
```

### Compiler

```nim
type Compiler* = ref object
  output*: CompilationUnit
  trace_stack*: seq[SourceTrace]              # ← Current compilation context
  last_error_trace*: SourceTrace              # ← For error reporting
  # ... other fields
```

## Missing: Call Stack Traces

**Problem:** VM doesn't track source locations for each call frame

**Current:**
```nim
type VirtualMachine* = ref object
  cu*: CompilationUnit
  pc*: int
  frame*: Frame
  # ...
```

**Proposed Addition:**
```nim
type VirtualMachine* = ref object
  cu*: CompilationUnit
  pc*: int
  frame*: Frame
  call_stack_traces*: seq[SourceTrace]  # ← NEW: Track trace per frame
  # ...
```

**Implementation:**
```nim
# When making a call (IkUnifiedCall*, etc.):
proc push_call_frame(...):
  vm.call_stack_traces.add(vm.current_trace())
  # ... create frame ...

# When returning (IkReturn):
proc return_from_call(...):
  vm.call_stack_traces.setLen(vm.call_stack_traces.len - 1)
  # ... restore frame ...
```

## Summary

Gene's location tracking system has:

✅ **Complete pipeline** from source to runtime
✅ **Efficient storage** via GIR serialization
✅ **Tree structure** for nested expressions
✅ **Per-instruction granularity**

Opportunities:

🔧 **Stack traces** - track location per call frame
🔧 **Error formatting** - consistently use location info
🔧 **Source display** - show code context with errors
🔧 **Compiler errors** - better location reporting

All improvements leverage existing infrastructure!
