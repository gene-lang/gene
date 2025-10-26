# Design: Streaming Compilation Integration

## Current Architecture Analysis

### Existing Implementation
The codebase already has a `parse_and_compile` function in `src/gene/compiler.nim` that implements streaming compilation:

```nim
proc parse_and_compile*(input: string, filename = "<input>"): CompilationUnit =
  ## Parse and compile Gene code from a string with streaming compilation
  ## Parse one item -> compile immediately -> repeat

  var parser = new_parser()
  var stream = new_string_stream(input)
  parser.open(stream, filename)
  defer: parser.close()

  # Initialize compilation
  let self = Compiler(output: new_compilation_unit(), tail_position: false)

  # Streaming compilation: parse one -> compile one -> repeat
  try:
    while true:
      let node = parser.read()
      if node != PARSER_IGNORE:
        # Compile current item
        self.compile(node)
  except ParseEofError:
    # Expected end of input
    discard
```

### Current Issues
1. **Error handling ambiguity**: Parse errors and compile errors aren't clearly distinguished
2. **Inconsistent usage**: Not all commands use this streaming approach consistently
3. **Limited error context**: Error reporting doesn't provide clear location information
4. **Debugging gaps**: Trace and debugging may not work optimally with streaming

## Proposed Architecture

### Enhanced Streaming Flow
```
Initialize Parser
Initialize Compiler
┌─────────────────┐
│ Parse Next Item │
└─────────┬───────┘
          │
    Parse Error?
          │ Yes
          ▼
    Stop & Report
          │
          │ No
          ▼
┌─────────────────┐
│ Compile Item    │
└─────────┬───────┘
          │
    Compile Error?
          │ Yes
          ▼
    Stop & Report
          │
          │ No
          ▼
    More Items?
          │ Yes
          └───────┐
                  ▼
           (Loop back)
```

### Key Design Decisions

#### 1. Error Type Distinction
- **Parse Errors**: Include line/column information, show syntax context
- **Compile Errors**: Include AST node information, show compilation context
- **Unified Error Interface**: Single error type that encompasses both phases

#### 2. Immediate Failure Strategy
- Stop compilation immediately when either parsing or compilation fails
- Don't attempt to continue or recover from errors
- Preserve error context for debugging

#### 3. State Management
- Parser and compiler maintain separate state but are coordinated
- Compilation unit accumulates bytecode incrementally
- Error state is preserved across the streaming loop

#### 4. Debugging Integration
- Trace information shows both parse and compile steps
- Instruction tracing works with incremental compilation
- Error reporting integrates with existing debugging infrastructure

### Implementation Strategy

#### Phase 1: Enhanced Error Handling
- Extend `parse_and_compile` to distinguish error types
- Improve error messages with location information
- Add proper error propagation

#### Phase 2: Command Integration
- Update all commands to use consistent streaming compilation
- Ensure error handling is consistent across commands
- Validate that existing functionality is preserved

#### Phase 3: Debugging Enhancement
- Ensure trace and debugging work with streaming compilation
- Add more granular debugging for parse vs compile phases
- Improve error reporting in debug mode

### Error Handling Model

```nim
type CompilationErrorKind = enum
  CekParseError     # Syntax/lexical errors during parsing
  CekCompileError   # Semantic/code generation errors during compilation
  CekInternalError  # Unexpected internal failures

type CompilationError = ref object
  kind*: CompilationErrorKind
  message*: string
  filename*: string
  line*: int
  column*: int
  context*: string  # Surrounding code context
  astNode*: Gene   # For compile errors
```

### Integration Points

#### Commands to Update
1. **run command** - Already uses `parse_and_compile`, needs error handling improvements
2. **eval command** - Already uses `parse_and_compile`, needs error handling improvements
3. **compile command** - Needs to consistently use streaming compilation
4. **repl command** - May need updates for incremental compilation

#### Testing Strategy
- Ensure all existing tests continue to pass
- Add specific tests for parse vs compile error distinction
- Add tests for immediate failure behavior
- Test debugging and tracing with streaming compilation

## Trade-offs

### Benefits
- **Better error reporting**: Clear distinction between parse and compile errors
- **Immediate feedback**: Stop immediately on errors instead of continuing
- **Consistent behavior**: All commands use the same compilation approach
- **Improved debugging**: Better integration with tracing and debugging

### Costs
- **Implementation complexity**: Enhanced error handling adds complexity
- **Testing overhead**: Need to ensure error distinction works correctly
- **Potential performance**: Slight overhead from enhanced error tracking

### Mitigations
- Start with minimal implementation and enhance incrementally
- Leverage existing error handling infrastructure
- Focus on high-value improvements first