# CLAUDE.md - Gene Language Development Guide

This file provides comprehensive guidance for AI assistants working with the Gene programming language codebase.

## Project Overview

Gene is a Lisp-like programming language implemented in Nim with a bytecode VM for performance. The project consists of:
- **Parser**: Converts Gene source code to AST (`src/gene/parser.nim`)
- **Compiler**: Transforms AST to bytecode (`src/gene/compiler.nim`)  
- **VM**: Stack-based virtual machine that executes bytecode (`src/gene/vm.nim`)
- **Type System**: Rich type system with 100+ value types (`src/gene/types.nim`)

## Gene Language Syntax

Gene uses S-expression syntax similar to Lisp/Clojure:

```gene
# Comments start with #
(println "Hello")                    # Function call
(var x 10)                           # Variable declaration
(x = 20)                             # Variable assignment
(fn add [a b] (+ a b))              # Function definition
(if (> x 5) "big" "small")          # Conditional
(while (< i 10) (i = (+ i 1)))     # Loop
(do expr1 expr2 expr3)              # Sequence of expressions
(try ... catch * ...)               # Exception handling (use * not variable)
(async expr)                        # Create future
(await future)                      # Wait for future
[1 2 3]                             # Array literal
{:a 1 :b 2}                         # Map literal
```

## Architecture & Memory Model

### Stack-Based VM
- Instructions manipulate an operand stack
- Each frame has its own stack (256 values)
- Frames are allocated from a pool for efficiency

### Scope Management
- **Scopes** hold local variables (`ScopeObj` with `members: seq[Value]`)
- Scopes form a chain via `parent` pointers
- **Critical Issue**: Scopes are freed immediately in `IkScopeEnd` which causes use-after-free bugs with async code
- Scopes use manual memory management (`alloc0`/`dealloc`)
- `new_scope` MUST initialize `members = newSeq[Value]()` or it will be nil

### Async Implementation
- Futures complete synchronously (pseudo-async)
- `IkAsyncStart`/`IkAsyncEnd` wrap expressions in futures
- Exception handlers with `catch_pc = -2` mark async blocks
- Async blocks don't capture scopes - they execute immediately

## Critical Implementation Details

### Known Issues

1. **Scope Lifetime Bug**: When functions return async blocks that reference parameters, the scope gets freed causing crashes. The `old_scope.free()` in `IkScopeEnd` (vm.nim:419) is the culprit.

2. **Exception Handling**: Use `catch *` with `$ex` to access exception. Using `catch e` crashes on macOS.

3. **String Methods**: Implemented in `vm/core.nim` as native functions. Must handle in `IkCallMethod1` for VkString case.

### VM Instructions
Located in `types.nim` starting around line 600:
- Stack: `IkPushValue`, `IkPop`, `IkDup`
- Variables: `IkVar`, `IkVarResolve`, `IkVarUpdate`  
- Scope: `IkScopeStart`, `IkScopeEnd`
- Control: `IkJump`, `IkJumpIf`, `IkReturn`
- Async: `IkAsyncStart`, `IkAsyncEnd`, `IkAwait`

### Method Dispatch
Methods are resolved in `vm.nim` `IkCallMethod1`:
- VkInstance: Look up in class methods table
- VkString: Use App.app.string_class methods
- VkFuture: Use App.app.future_class methods

## Testing

### Test Suite Structure
```
testsuite/
├── basics/           # Literals, variables, basic types
├── control_flow/     # if, while, for, do
├── operators/        # Arithmetic, comparison
├── arrays/           # Array operations
├── maps/            # Map operations  
├── strings/         # String operations
├── functions/       # Function definitions
├── scopes/          # Variable scoping
├── async/           # Async/await tests
└── run_tests.sh     # Test runner
```

### Test Format
- Tests are numbered: `001_feature.gene`, `002_feature.gene`
- Use `# Expected: output` comments for validation
- Tests without expected output just verify successful execution
- Use `assert` for inline validation

### Running Tests
```bash
./testsuite/run_tests.sh           # Run all tests
nim c -r tests/test_vm.nim         # Run VM unit tests
nimble test                         # Run full test suite
bin/gene run file.gene              # Run single file
```

## Development Workflow

### Building
```bash
nimble build                        # Build gene executable to bin/
nim c -d:release src/gene.nim      # Direct compilation
```

### Debugging
- Add debug output in VM with `echo` statements
- Check instruction generation in compiler
- Use `when DEBUG_VM:` blocks for conditional debugging
- VM crashes often indicate scope/memory issues

### Common Patterns

**Adding a VM instruction:**
1. Add to InstructionKind enum in types.nim
2. Add compilation in compiler.nim
3. Add execution case in vm.nim

**Adding a native function:**
1. Define proc in vm/core.nim or appropriate module
2. Register in init functions
3. Add to namespace (gene_ns, global_ns, etc.)

**Adding a method to a class:**
1. Define native function proc
2. Use `add_method(class, "name", proc)` in init
3. Handle in IkCallMethod1 for the type

## Important Files

- `src/gene/types.nim`: All type definitions, Value discriminated union
- `src/gene/vm.nim`: Main VM execution loop, instruction handlers
- `src/gene/compiler.nim`: AST to bytecode compilation
- `src/gene/parser.nim`: Source code parsing
- `src/gene/vm/core.nim`: Core functions, class initialization
- `src/gene/vm/async.nim`: Future class and async support
- `src/gene/vm/io.nim`: I/O operations

## Guidelines

- Don't stop work prematurely - run tests to validate
- Use `tmp/` directory for temporary test files
- Keep test files in `testsuite/` organized by feature
- Document known issues as comments in code
- Initialize ALL fields when creating objects with alloc0
- Be careful with manual memory management (ref counting)
- Test async code carefully - scope lifetime is tricky