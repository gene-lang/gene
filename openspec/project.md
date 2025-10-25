# Project Context

## Purpose
Gene is a Lisp-like programming language with S-expression syntax, implemented in Nim with a high-performance bytecode VM. The project aims to provide a flexible, extensible language with rich metaprogramming capabilities and async support.

## Tech Stack
- **Language**: Nim (implementation language)
- **Build System**: Nimble
- **VM Architecture**: Stack-based bytecode VM with frame pool
- **Type System**: Discriminated union (Value) with 100+ value types
- **Extensions**: HTTP, SQLite (buildext target)

## Project Conventions

### Code Style
- Follow Nim naming conventions: `snake_case` for procs/vars, `PascalCase` for types
- Use `when DEBUG_VM:` blocks for conditional debugging output
- Initialize ALL fields when creating objects with `alloc0` (critical for manual memory management)
- Document known issues inline with comments

### Architecture Patterns
- **Parser** (`src/gene/parser.nim`): Converts Gene source → AST
- **Compiler** (`src/gene/compiler.nim`): Transforms AST → bytecode
- **VM** (`src/gene/vm.nim`): Stack-based execution engine with instruction loop
- **Type System** (`src/gene/types.nim`): All type definitions and InstructionKind enum
- **Scope Management**: Scopes form parent-chain for variable lookup; use manual memory management
- **Async Model**: Pseudo-async (synchronous futures) using `IkAsyncStart`/`IkAsyncEnd` with exception handlers

### Testing Strategy
- **Test Location**: `testsuite/` organized by feature (basics/, control_flow/, async/, etc.)
- **Test Format**: Numbered files (`001_feature.gene`) with `# Expected: output` comments
- **Validation**: Use `assert` for inline validation
- **Running Tests**: `./testsuite/run_tests.sh` or `nimble test`
- **Coverage**: Always run tests to validate changes; don't stop work prematurely

### Git Workflow
- **Main Branch**: `master`
- **Feature Branches**: Use descriptive names (e.g., `feature/stdlib`)
- **Testing**: Validate all tests pass before committing
- **Commits**: Keep focused and atomic; include test updates with changes

## Domain Context

### Gene Language Syntax
```gene
# Comments with #
(println "Hello")              # Function call
(var x 10)                     # Variable declaration
(fn add [a b] (+ a b))        # Function definition
(if condition then else)       # Conditional
(async expr)                   # Create future
(await future)                 # Wait for future
[1 2 3]                        # Array literal
{:a 1 :b 2}                    # Map literal
```

### Critical Implementation Details
- **Scope Lifetime**: Known issue with scope being freed in `IkScopeEnd` causing use-after-free with async blocks
- **Exception Handling**: Use `catch *` with `$ex` (not `catch e`—crashes on macOS)
- **Method Dispatch**: Handled in `IkCallMethod1` per type (VkInstance, VkString, VkFuture)
- **Memory Model**: Manual ref counting; scopes use `alloc0`/`dealloc`

## Important Constraints
- **Manual Memory Management**: Be careful with scope lifetime and ref counting
- **Async Limitations**: Futures complete synchronously; async blocks don't capture scopes
- **Platform**: Primary development on macOS; cross-platform Nim limitations apply
- **Performance**: VM instruction dispatch is hot path; optimize carefully

## External Dependencies
- **Nim Standard Library**: core, os, strutils, tables, etc.
- **Optional Extensions**: HTTP client, SQLite (built separately via `nimble buildext`)
- **Build Requirements**: Nim compiler, Nimble package manager
