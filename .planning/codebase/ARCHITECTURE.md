# Architecture

**Analysis Date:** 2026-02-26

## Pattern Overview

**Overall:** Monolithic native CLI runtime implementing a bytecode virtual machine and compiler pipeline for the Gene language.

**Key Characteristics:**
- Single executable entry point (`src/gene.nim`) dispatching subcommands
- Parser -> compiler -> VM execution pipeline with optional GIR cache
- Layered runtime: core language (`src/gene/*`) plus extension namespaces (`src/genex/*`)
- Optional native compilation tiers and optional local LLM runtime integration

## Layers

**Command Layer:**
- Purpose: Parse CLI args and route command execution
- Contains: command handlers (`src/commands/*.nim`) and command registration (`src/gene.nim`)
- Depends on: parser/compiler/VM/GIR modules
- Used by: end-user CLI invocation (`bin/gene`)

**Front-End Parsing Layer:**
- Purpose: Parse Gene source into internal AST/value forms
- Contains: parser/tokenization and macro dispatch (`src/gene/parser.nim`)
- Depends on: core value/type system (`src/gene/types*`)
- Used by: compiler and CLI commands (`run`, `eval`, `parse`, `compile`)

**Type Analysis Layer:**
- Purpose: Optional gradual type inference/checking before bytecode generation
- Contains: type checker and runtime type metadata utilities (`src/gene/type_checker.nim`, `src/gene/types/runtime_types.nim`)
- Depends on: parser output + type descriptors in core type modules
- Used by: compile pipeline when type checking is enabled

**Compilation Layer:**
- Purpose: Emit bytecode instructions and compilation metadata
- Contains: compiler core and form-specific compiler modules (`src/gene/compiler.nim`, `src/gene/compiler/*.nim`)
- Depends on: AST/value model, type metadata, instruction definitions
- Used by: VM runtime and GIR serializer

**Execution Layer (VM):**
- Purpose: Execute bytecode instructions, manage scopes/frames/calls/exceptions/async
- Contains: VM core and instruction handlers (`src/gene/vm.nim`, `src/gene/vm/*.nim`)
- Depends on: compiled units, value model, stdlib registration
- Used by: run/eval/repl and extension callback paths

**Persistence/Cache Layer (GIR):**
- Purpose: Serialize/deserialize compilation units for reuse
- Contains: GIR formats and serializers (`src/gene/gir.nim`)
- Depends on: instruction/value/type descriptor serialization logic
- Used by: `run` command cache path and `compile -f gir`

**Extension/Namespace Layer:**
- Purpose: Provide optional namespaces for HTTP, DB, AI, LLM, logging
- Contains: `src/genex/*.nim` and `src/genex/ai/*`
- Depends on: VM native function interfaces and third-party libraries
- Used by: Gene programs importing `genex/*`

## Data Flow

**CLI Run Flow (`gene run <file>`):**
1. CLI entry (`src/gene.nim`) resolves `run` command
2. `src/commands/run.nim` parses options and initializes app/VM
3. Run command checks GIR cache (`build/*.gir`) for up-to-date compiled module
4. If cache miss: parse source (`src/gene/parser.nim`) and compile (`src/gene/compiler.nim`)
5. VM executes `CompilationUnit` (`src/gene/vm.nim`)
6. Optional module init runs; command returns success/failure

**Eval Flow (`gene eval <code>`):**
1. Parse command/eval options (`src/commands/eval.nim`)
2. Initialize VM/stdlib and set eval context
3. Compile and execute inline code (or stdin)
4. Return/print final value; optionally emit compile/trace output

**State Management:**
- VM execution state lives in frame/scope stacks and compilation-unit pointers
- GIR cache state is file-based under `build/`
- Thread pools/channels are managed in VM thread modules (`src/gene/vm/thread.nim`)

## Key Abstractions

**Value / ValueKind:**
- Purpose: Uniform runtime representation for scalars, refs, AST nodes, callables
- Examples: `Value`, `ValueKind`, constructors/helpers in `src/gene/types/*.nim`
- Pattern: Tagged value model with helper conversion/accessor functions

**CompilationUnit + InstructionKind:**
- Purpose: Portable bytecode + metadata payload executed by VM and serialized by GIR
- Examples: instruction enums/records in `src/gene/types/type_defs.nim`; serialization in `src/gene/gir.nim`
- Pattern: Stack-machine instruction stream with associated constants and debug metadata

**Namespace/Class Runtime Objects:**
- Purpose: Host symbols, methods, native functions, and extension surfaces
- Examples: namespace/class creation in stdlib and `src/genex/*` initializers
- Pattern: Runtime registry pattern populated at VM/app initialization

## Entry Points

**CLI Entry:**
- Location: `src/gene.nim`
- Triggers: user executes `gene <command>`
- Responsibilities: command registration, dispatch, process exit handling

**Command Handlers:**
- Location: `src/commands/*.nim`
- Triggers: command manager dispatch
- Responsibilities: parse options, initialize VM/app context, invoke parse/compile/execute routines

**Extension Registration:**
- Location: `src/genex/*.nim`, `src/genex/ai/*.nim`
- Triggers: VM/app init callbacks
- Responsibilities: create namespace/class bindings and native methods

## Error Handling

**Strategy:**
- Command boundary returns structured `CommandResult` success/failure
- Runtime/compiler/parser paths raise catchable exceptions that command handlers convert to user-visible failures

**Patterns:**
- `raise new_exception(types.Exception, ...)` in runtime/extension code
- `try/except CatchableError` around command execution boundaries
- Optional REPL-on-error fallback in run/eval command handlers

## Cross-Cutting Concerns

**Logging:**
- Central command logger setup in `src/commands/base.nim`
- Module-specific debug branches in some subsystems (especially AI/streaming)

**Validation:**
- Option parsing guards in command handlers
- Runtime argument validation in native extension methods
- Optional type checking in compile/run/eval pipelines

**Async/Concurrency:**
- Event-loop polling integrated into VM execution path
- Thread/channel infrastructure in `src/gene/vm/thread.nim`
- HTTP and AI extensions rely on async primitives

---
*Architecture analysis: 2026-02-26*
*Update when major patterns change*
