# Location Tracking Analysis

## Executive Summary

Gene **already has a comprehensive location tracking infrastructure** in place. The system tracks source locations from parsing through compilation to runtime, but there are opportunities to improve error reporting and stack trace generation.

## Current Implementation

### 1. Data Structures (src/gene/types/type_defs.nim)

```nim
SourceTrace* = ref object
  parent*: SourceTrace
  children*: seq[SourceTrace]
  filename*: string
  line*: int
  column*: int
  child_index*: int
```

**Key Features:**
- Tree structure with parent/child relationships
- Captures filename, line number, and column number
- Supports hierarchical trace information

### 2. Parser Integration (src/gene/parser.nim)

**What's Working:**
- Parser maintains a `trace_stack` to track nested expressions
- Every Gene expression gets a `SourceTrace` attached via `add_line_col()` (line 868)
- Trace information flows from lexer position to AST nodes

**Code Example:**
```nim
proc add_line_col(self: var Parser, gene: ptr Gene, start_pos: int) =
  let parent_trace = self.current_trace()
  var column = self.get_col_number(start_pos)
  let line = self.line_number
  let trace = new_source_trace(self.filename, line, column)

  if not parent_trace.is_nil:
    attach_child(parent_trace, trace)

  gene.trace = trace
  self.push_trace(trace)
```

### 3. Compiler Integration (src/gene/compiler.nim)

**What's Working:**
- Compiler maintains its own `trace_stack` during compilation
- When emitting instructions, current trace is attached (line 104):
  ```nim
  proc emit(self: Compiler, instr: Instruction) =
    self.output.add_instruction(instr, self.current_trace())
  ```
- Each `CompilationUnit` has `instruction_traces: seq[SourceTrace]` - one trace per instruction

### 4. Runtime Integration (src/gene/vm)

**What's Working:**
- VM can retrieve current source location via `current_trace()` (vm/runtime_helpers.nim:3)
- Runtime exceptions include location information via `format_runtime_exception()`
- GIR serialization preserves trace information for cached bytecode

**Code Example:**
```nim
proc format_runtime_exception(self: VirtualMachine, value: Value): string =
  let trace = self.current_trace()
  let location = trace_location(trace)
  if location.len > 0:
    "Gene exception at " & location & ": " & $value
  else:
    "Gene exception: " & $value
```

### 5. GIR Serialization (src/gene/gir.nim)

**What's Working:**
- Trace trees are serialized and deserialized
- Cached bytecode retains full location information
- Uses pointer-to-index mapping to handle tree structure efficiently

## What's Missing/Could Be Improved

### 1. Stack Traces for Runtime Errors

**Current State:** Only shows single location where error occurred
**Desired:** Full call stack with file:line:column for each frame

**Recommendation:**
```nim
# Add to VirtualMachine
type VirtualMachine* = ref object
  # ... existing fields ...
  call_stack_traces*: seq[SourceTrace]  # Track trace for each frame

# When creating new frame:
proc push_frame(...):
  vm.call_stack_traces.add(vm.current_trace())

# When formatting exception:
proc format_runtime_exception_with_stack(vm: VirtualMachine, value: Value): string =
  result = "Gene exception: " & $value & "\n"
  result &= "Stack trace (most recent call first):\n"
  for i in countdown(vm.call_stack_traces.len - 1, 0):
    result &= "  at " & trace_location(vm.call_stack_traces[i]) & "\n"
```

### 2. Compile-Time Error Locations

**Current State:** Compiler has `last_error_trace` but not consistently used
**Recommendation:** Enhance compiler error reporting to always include source location

```nim
proc compile_error(self: Compiler, msg: string) =
  let trace = self.current_trace()
  let location = trace_location(trace)
  raise newException(CompileError, location & ": " & msg)
```

### 3. Better Error Messages for Native Functions

**Current State:** Native function errors may not have good location context
**Recommendation:** Pass VM context to native functions for better error reporting

### 4. Column Tracking for Complex Expressions

**Current State:** Only tracks start position of Gene expressions
**Potential Enhancement:** Track start/end positions for better error highlighting

```nim
SourceTrace* = ref object
  # ... existing fields ...
  start_column*: int
  end_column*: int
  end_line*: int  # For multi-line expressions
```

### 5. Inline Cache Debugging

**Current State:** Inline caches don't track where they were created
**Enhancement:** Add trace info to inline caches for debugging cache invalidation

## Recommendations

### High Priority (Easy Wins)

1. **Add Stack Trace Building**
   - Track trace for each frame push/pop
   - Format multi-level stack traces in exceptions
   - Estimated effort: 2-4 hours

2. **Standardize Error Formatting**
   - Create helper functions that always include location
   - Use consistently across VM operations
   - Estimated effort: 1-2 hours

### Medium Priority

3. **Enhanced Compiler Errors**
   - Always include source location in compile errors
   - Add helpful context (show source line)
   - Estimated effort: 4-6 hours

4. **Native Function Error Context**
   - Pass VM to more native functions
   - Include location in native function errors
   - Estimated effort: 4-8 hours

### Low Priority (Nice to Have)

5. **Source Line Display**
   - Cache source file content
   - Show relevant line(s) with error markers
   - Estimated effort: 8-12 hours

6. **Range Tracking**
   - Track start and end positions
   - Enable better error highlighting
   - Estimated effort: 12-16 hours

## Example: Improved Error Output

### Current
```
Gene exception: undefined variable 'x'
```

### With Stack Traces
```
Gene exception at examples/test.gene:15:8: undefined variable 'x'
Stack trace (most recent call first):
  at examples/test.gene:15:8 in function 'calculate'
  at examples/test.gene:23:3 in function 'main'
  at examples/test.gene:28:1 in <module>
```

### With Source Context
```
Gene exception at examples/test.gene:15:8: undefined variable 'x'

  13 | (fn calculate [a b]
  14 |   (var result (+ a b))
  15 |   (println x)
     |            ^
  16 |   result)

Stack trace:
  at examples/test.gene:15:8 in function 'calculate'
  at examples/test.gene:23:3 in function 'main'
```

## Implementation Guide

### Phase 1: Stack Traces (Recommended First Step)

1. Add `call_stack_traces: seq[SourceTrace]` to `VirtualMachine`
2. In VM execution, track traces when creating frames:
   - `IkUnifiedCall*` instructions: push current trace
   - `IkReturn`: pop trace from stack
3. Update `format_runtime_exception` to include full stack
4. Test with nested function calls

### Phase 2: Standardized Error Handling

1. Create error helper module:
   ```nim
   # src/gene/vm/errors.nim
   proc runtime_error*(vm: VirtualMachine, msg: string)
   proc compile_error*(compiler: Compiler, msg: string)
   ```
2. Replace ad-hoc error raising with helpers
3. Ensure all paths use location information

### Phase 3: Enhanced Display

1. Add source caching mechanism
2. Implement line extraction and formatting
3. Add caret/underline positioning
4. Integrate with error messages

## Files to Modify

### For Stack Traces
- `src/gene/types/type_defs.nim` - Add call_stack_traces field
- `src/gene/vm.nim` - Track traces on call/return
- `src/gene/vm/runtime_helpers.nim` - Enhanced exception formatting

### For Better Compile Errors
- `src/gene/compiler.nim` - Use trace in error messages
- Create `src/gene/errors.nim` - Centralized error formatting

### For Source Display
- Create `src/gene/source_cache.nim` - Cache and retrieve source lines
- `src/gene/vm/runtime_helpers.nim` - Format with source context

## Testing Strategy

1. **Unit Tests**
   - Test trace creation during parsing
   - Test trace propagation through compilation
   - Test trace retrieval at runtime

2. **Integration Tests**
   - Nested function calls with errors at different levels
   - Errors in different file contexts
   - Macro expansion with location tracking

3. **Error Message Tests**
   - Verify location appears in all error types
   - Check stack trace accuracy
   - Validate source line extraction

## Conclusion

Gene's location tracking infrastructure is **already well-designed and implemented**. The main opportunity is to **leverage this existing system more fully** for better error messages and stack traces. The recommended changes are mostly additive - using the trace information that's already being collected.

The highest value improvements are:
1. Building proper stack traces from existing trace data
2. Standardizing error formatting to always include locations
3. Adding source context display for better developer experience

All of these can be implemented without changing the core data structures or parsing logic.
