# Gene VM Architecture

This document describes the VM-based implementation that lives under `src/gene/`.  
The execution pipeline looks like this:

```
source.gene ──► Parser ──► AST ──► Compiler ──► CompilationUnit ──► VM ──► result
                           │                         │
                           └──────► GIR writer ◄─────┘
```

## Components

### Command Front-End (`src/gene.nim`, `src/gene/commands/`)
- All CLI behaviour is routed through a `CommandManager`.
- `run`, `eval`, `repl`, `parse`, and `compile` commands live in `src/gene/commands/*.nim`.
- `run` optionally loads cached Gene IR (`*.gir`) from `build/`, otherwise parses and compiles on the fly.
- Shared helpers set up logging, initialise the VM (`init_app_and_vm`), and register runtime namespaces (`register_io_functions`).

### Parser (`src/gene/parser.nim`)
- Reads S-expressions, supports macro dispatch (quote/unquote, `@decorators`, string interpolation).
- Produces nested `Gene` nodes backed by `Value` (not plain Nim objects), retaining metadata for later phases.
- Macro readers are stored in two dispatch tables (`macros` and `dispatch_macros`) making it easy to extend syntax.

### Compiler (`src/gene/compiler.nim`)
- Walks the parsed form and emits instructions defined in `InstructionKind`.
- Handles special forms (conditionals, loops, namespaces, class definitions, `$caller_eval`).
- Builds argument matchers so functions, macros, and methods can destructure their inputs.
- Produces a `CompilationUnit` (instruction stream + constant table + metadata) consumed by the VM or the GIR serializer.

### Gene IR (GIR) (`src/gene/gir.nim`)
- Serialises/deserialises `CompilationUnit` objects.
- Embeds version info, compiler fingerprint, and optional source hash for cache validation.
- `gene compile` writes GIR files; `gene run` can execute them directly.

### Virtual Machine (`src/gene/vm.nim`)
- Stack-based VM with computed-goto dispatch (`{.computedGoto.}` pragma).
- Each `Frame` owns a 256-slot value stack, an instruction pointer, argument list, and scope chain.
- Scope objects form a linked list; ref-counted manually to avoid churn (see `IkScopeStart`/`IkScopeEnd`).
- Macro-aware call path keeps arguments unevaluated when `Function.is_macro_like` is set.
- Async support wraps expressions in futures; await simply unwraps (pseudo-async).
- Includes tracing (`VM.trace`), profiling (`VM.profiling`, `instruction_profiling`), and GIR-aware execution.

## Value Representation (`src/gene/types.nim`)

- `Value` is a POD `distinct int64`; helper templates interpret the bit pattern as ints, floats, pointers, or tagged indices.
- `ValueKind` enumerates 100+ variants (scalars, collections, futures, namespaces, instructions, etc.).
- Heap-allocated data lives in `Reference` objects; the VM retains/releases them explicitly when storing in scopes or arrays.
- Symbol keys (`Key`) are cached integers that index into the global symbol table for fast lookup.

## Instruction Families

Instruction opcodes live in `InstructionKind`. A few important groups:

- **Stack & Scope**: `IkPushValue`, `IkPushNil`, `IkPop`, `IkDup*`, `IkScopeStart`, `IkScopeEnd`.
- **Variables**: `IkVar`, `IkVarResolve`, `IkVarAssign`, plus literal variants (`IkVarAddValue`, `IkVarSubValue`, …).
- **Control Flow**: `IkJump`, `IkJumpIfFalse`, `IkLoopStart/End`, `IkContinue`, `IkBreak`, `IkReturn`, `IkTailCall`.
- **Data & Collections**: `IkArrayStart/End`, `IkMapStart/End`, `IkGene*`, spread instructions, range/enum creation.
- **Functions & Macros**: `IkFunction`, `IkMacro`, `IkBlock`, `IkCallInit`, `IkCallerEval`.
- **Classes & Methods**: `IkClass`, `IkSubClass`, `IkNew`, `IkDefineMethod`, `IkResolveMethod`, `IkSuper`.
- **Error Handling**: `IkTryStart`, `IkTryEnd`, `IkCatchStart/End`, `IkFinally`, `IkThrow`.
- **Async**: `IkAsyncStart`, `IkAsyncEnd`, `IkAwait`.

See `src/gene/compiler.nim` for how AST nodes map to these instructions, and `src/gene/vm.nim` for runtime semantics.

## Memory Model & Scope Lifetime

- Frames are pooled; `new_frame` reuses objects when possible to cut allocations.
- Scopes (`ScopeObj`) are manually ref-counted. `IkScopeEnd` calls `scope.free()` which decrements the ref count and only deallocates when it reaches 0.
  ✅ Scope lifetime is correctly managed - async code can safely capture scopes and they won't be freed prematurely.
- Nim ORC/ARC handles heap references (`Reference`) while the VM keeps hot paths allocation-free by using POD `Value`s.

## Native Integration

- `vm/core.nim` initialises built-in namespaces (math, string, array, map, IO, async).
- `register_io_functions` adds file helpers (`io/read`, `io/write`, async counterparts).
- Native functions use `NativeFn`/`NativeMethod` signatures and are stored in class/namespace tables.
- Extensions can be built as shared libraries (see `nimble buildext`) and loaded at runtime.

## Example Execution Flow

```
(fn add [a b] (+ a b))
(add 1 2)
```

Compilation emits (simplified):
```
IkFunction           ; allocate function object
IkVar                ; bind to current scope
IkVarResolve         ; push function for call
IkPushValue          ; push literal 1
IkPushValue          ; push literal 2
IkCallInit           ; prepare call frame, process matcher
IkReturn             ; return result
```

At runtime the VM:
1. Pushes a new frame when hitting `IkFunction`.
2. Stores locals in the current scope via `IkVar`.
3. Creates a new call frame (`new_frame`) when `IkCallInit` runs.
4. Executes the function body with computed-goto dispatch until `IkReturn`.

## Observability & Tooling

- `VM.trace = true` prints the instruction stream as it executes (enabled via CLI `--trace`).
- Instruction and function profilers (`VM.print_profile`, `VM.print_instruction_profile`) help prioritise optimisations.
- GIR hashes plus timestamps make it cheap to spot stale IR during `gene run`.
- `docs/performance.md` tracks benchmarking methodology and ongoing optimisation ideas.

## Current Pain Points

- Scope lifetime around async/await needs work (`IkScopeEnd` free ordering).
- Class system lacks exhaustive tests for constructors, inheritance, and keyword arguments.
- Pattern matching infrastructure exists but many `match` forms remain disabled in the test suite.

See also:
- [`docs/performance.md`](performance.md) — hotspot analysis and optimisation roadmap.
- [`docs/IMPLEMENTATION_STATUS.md`](IMPLEMENTATION_STATUS.md) — up-to-date checklist of supported features.
- [`docs/gir.md`](gir.md) — details on the IR format and CLI workflows.
