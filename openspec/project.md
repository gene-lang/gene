# Project Context

## Purpose
Gene is a Lisp-like programming language with S-expression syntax, implemented in Nim with a high-performance bytecode VM. The project aims to provide a flexible, extensible language with rich metaprogramming capabilities and async support.

## Tech Stack
- **Language**: Nim (implementation language)
- **Build System**: Nimble
- **VM Architecture**: Stack-based bytecode VM with frame pool
- **Type System**: Discriminated union (Value) with 100+ value types
- **Extensions**: HTTP, SQLite, PostgreSQL (buildext target)

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
- **Async Model**: Real async I/O with event loop integration using `IkAsyncStart`/`IkAsyncEnd` with exception handlers

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
{^a 1 ^b 2}                    # Map literal
```

### Critical Implementation Details
- **Scope Lifetime**: Properly managed with ref-counting; async blocks safely capture scopes
- **Exception Handling**: Use `catch *` with `$ex` (not `catch e`—crashes on macOS)
- **Method Dispatch**: Handled in `IkCallMethod1` per type (VkInstance, VkString, VkFuture)
- **Memory Model**: Manual ref counting; scopes use `alloc0`/`dealloc`

## Important Constraints
- **Manual Memory Management**: Be careful with scope lifetime and ref counting
- **Async**: Real async I/O with event loop; VM polls asyncdispatch every 100 instructions
- **Platform**: Primary development on macOS; cross-platform Nim limitations apply
- **Performance**: VM instruction dispatch is hot path; optimize carefully

## External Dependencies
- **Nim Standard Library**: core, os, strutils, tables, etc.
- **Database**: db_connector >= 0.1.0 (includes db_sqlite, db_postgres)
- **PostgreSQL**: libpq (system library - install via package manager)
- **Optional Extensions**: HTTP client, SQLite, PostgreSQL (built separately via `nimble buildext`)
- **Build Requirements**: Nim compiler, Nimble package manager

## CLI & Tooling

- **Primary binary**: `bin/gene`
- **Common commands**:
  - `nimble build` (debug build in `bin/`)
  - `nimble speedy` (release, native flags)
  - `bin/gene run <file.gene>` (exec with GIR cache)
  - `bin/gene eval "(println \"hi\")"` (inline eval)
  - `bin/gene repl` (interactive shell)
  - `bin/gene compile --emit-debug <file.gene>` (inspect bytecode/GIR)
- **Caching**: Compiled GIR artifacts under `build/` are reused unless `--no-gir-cache` is passed

## Repository Layout

```
src/gene/
  compiler.nim          # AST → bytecode
  parser.nim            # S-expression reader
  vm.nim                # Main dispatch loop
  types.nim             # Value + InstructionKind
  gir.nim               # Bytecode serializer
  vm/                   # Native fns, async, core types
  stdlib/               # Standard library impls
docs/                   # Architecture and design notes
tests/                  # Nim tests
testsuite/              # Gene language tests
openspec/               # Specs and change proposals
```

## Additional Coding Conventions

- Prefer early returns over deep nesting in Nim procs
- Avoid broad try/except; handle only expected exceptions
- Keep hot-path procs small; avoid allocations in instruction dispatch
- Name instructions with `Ik*` prefix and values with `Vk*`
- Exported procs/types use `*` and clear doc comments when non-obvious

## Versioning & Releases

- **Version file**: `gene.nimble`
- **Channel**: Cut releases from `master` after green tests
- **Artifacts**: `bin/gene` (macOS primary); extensions in `build/`

## Commit & PR Workflow

- Small, focused commits aligned with a single behavior change
- Include/adjust tests in the same commit when behavior changes
- Reference OpenSpec change IDs in commit messages when applicable (e.g., `add-module-system:` prefix)

## Continuous Validation

- Run `nimble test` locally before PRs
- Run `./testsuite/run_tests.sh` for language-level validation
- For spec-driven work, run `openspec validate <change-id> --strict`

## Performance Targets

- Dispatch loop is a hotspot; track regressions via `nimble bench`
- Target: maintain or improve current fib(24) baseline referenced in `docs/performance.md`

## Known Hazards & Caveats

- Exception handling: prefer `catch *` with `$ex`; `catch ex` may crash on macOS
- Scope lifetime: ensure `IkScopeEnd` retains scopes captured by async blocks
- String methods: ensure `IkCallMethod1` routes through `App.app.string_class`
- Manual memory: initialize all `ScopeObj` members and manage ref counts carefully

## Development Environment

- Recommended: macOS with Nim `>= 2.0.0`
- Optional extensions: build via `nimble buildext` (HTTP, SQLite)
