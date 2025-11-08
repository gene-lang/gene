<!-- OPENSPEC:START -->
# OpenSpec Instructions

These instructions are for AI assistants working in this project.

Always open `@/openspec/AGENTS.md` when the request:
- Mentions planning or proposals (words like proposal, spec, change, plan)
- Introduces new capabilities, breaking changes, architecture shifts, or big performance/security work
- Sounds ambiguous and you need the authoritative spec before coding

Use `@/openspec/AGENTS.md` to learn:
- How to create and apply change proposals
- Spec format and conventions
- Project structure and guidelines

Keep this managed block so 'openspec update' can refresh the instructions.

<!-- OPENSPEC:END -->

# Gene Agent Guide

These notes summarise the current VM implementation so future agents can orient quickly.  
Refer back to `CLAUDE.md` for the long-form deep dive when needed.

## Codebase Snapshot

- **Bytecode VM** in Nim (`src/gene/`) with stack frames, pooled scopes, and computed-goto dispatch (`src/gene/vm.nim`).
- **Gene IR (GIR)** (`src/gene/gir.nim`) persists compiled bytecode (`*.gir`) under `build/` for reuse.
- **Command infrastructure** (`src/gene/commands/`) exposes `run`, `eval`, `repl`, `parse`, and `compile`.
- **Reference interpreter** remains in `gene-new/` and is the behavioral oracle during parity work.

Key modules:
- `src/gene/parser.nim` — S-expression reader with macro dispatch table.
- `src/gene/compiler.nim` — emits instructions defined in `src/gene/types.nim`.
- `src/gene/vm/core.nim` — native functions, class initialisation, `register_io_functions`.
- `src/gene/vm/async.nim` — pseudo future implementation backing `async`/`await`.

## Feature Status

- ✅ Macros and macro-like functions (`fn!`, `$caller_eval`) with unevaluated arguments.
- ✅ Basic classes (`class`, `new`, nested classes) and namespace plumbing.
- ✅ Futures run synchronously; `async` wraps expressions and `await` unwraps results.
- ✅ Scope lifetime management: `IkScopeEnd` correctly uses ref-counting to prevent premature freeing when async blocks capture scopes.
- ⚠️ Pattern matching beyond argument binders is still experimental (`match` tests largely disabled).
- ⚠️ Module/import system and richer class method dispatch (constructors, inheritance, keyword args) are incomplete.

## Language Syntax Quick Look

```gene
# Comments start with #
(var x 10)                 # Variable declaration
(x = (+ x 1))              # Assignment
(fn add [a b] (+ a b))     # Function definition
(if (> x 5) "big" "small") # Conditional
(do expr1 expr2 expr3)     # Sequencing
(try
  (throw "boom")
catch *
  ($ex .message))          # Catch all exceptions with $ex
(async (println "hi"))     # Futures resolve synchronously today
{:a 1 :b [1 2 3]}          # Map literal with nested array
```

## VM Architecture Highlights

- Stack-based VM with pooled frames (256-value stack per frame) and computed-goto dispatch (`{.computedGoto.}`).
- Scopes (`ScopeObj`) are manually managed structures allocated via `alloc0`; always initialise `members = newSeq[Value]()`.
- Compilation pipeline: parse S-expressions → build AST (`Gene` nodes) → emit `Instruction` seq defined in `src/gene/types.nim`.
- GIR serializer (`src/gene/gir.nim`) persists constants + instructions; cached under `build/` and reused by the CLI.
- Async is pseudo: futures complete immediately on the calling thread. Await simply unwraps the future’s value.

## Instruction Cheatsheet

`InstructionKind` lives in `src/gene/types.nim` (see around `IkPushValue` onwards). Handy groups:
- **Stack**: `IkPushValue`, `IkPop`, `IkDup`, `IkSwap`.
- **Variables & Scopes**: `IkVar`, `IkVarResolve`, `IkVarAssign`, `IkScopeStart`, `IkScopeEnd`.
- **Control Flow**: `IkJump`, `IkJumpIfFalse`, `IkReturn`, `IkLoopStart`, `IkLoopEnd`.
- **Function/Macro**: `IkFunction`, `IkMacro`, `IkCall`, `IkCallerEval`.
- **Async**: `IkAsyncStart`, `IkAsyncEnd`, `IkAwait`.

When adding new instructions: extend the enum, teach the compiler (emit case), and handle execution in `vm.nim`.

## Method Dispatch Notes

- `IkCallMethod1` in `src/gene/vm.nim` directs dispatch:
  - `VkInstance` uses the class method tables.
  - `VkString` methods are provided by `App.app.string_class` (ensure new methods registered in `vm/core.nim`).
  - `VkFuture` and other special types have dedicated class objects (`future_class`, etc.).
- `$env` and `$cmd_args` are macro-powered helpers living in the global namespace (`gene/types.nim` initialises them).

## CLI & Tooling

- Build with `nimble build` (outputs `bin/gene`). `nimble speedy` enables release+native flags.
- `bin/gene run <file>` caches bytecode to `build/<path>.gir` unless `--no-gir-cache`.
- `bin/gene eval` accepts inline code or STDIN, with `--trace`, `--compile`, and formatter flags.
- `bin/gene compile` supports multiple output formats (`pretty`, `compact`, `bytecode`, `gir`) and `--emit-debug`.
- `bin/gene repl` starts an interactive shell; ensure `register_io_functions` runs before relying on `io/*`.

## Testing

- `nimble test` executes the curated Nim test matrix defined in `gene.nimble`.
- Individual Nim tests can be run with `nim c -r tests/test_X.nim`.
- `./testsuite/run_tests.sh` drives Gene source programs and expects `bin/gene` to exist.
- When adding language features, mirror coverage in both Nim tests and Gene test programs.

## Known Hazards

- **Exception handling**: use `catch *`; naming the exception (`catch ex`) still panics on macOS.
- **String methods**: `IkCallMethod1` must dispatch to `App.app.string_class` for string-specific natives.
- **Value initialisation**: manually allocate (`alloc0`) structures; always set `members = newSeq[Value]()` for new scopes.
- **Environment helpers**: `$env`, `$cmd_args` rely on `set_cmd_args`; ensure command modules set them before evaluating code.

## Documentation Map

- `docs/architecture.md` — high-level VM and compiler overview.
- `docs/gir.md` — GIR format and serialization details.
- `docs/performance.md` — current fib(24) numbers (~3.8M calls/sec optimised) and optimisation backlog.
- `docs/IMPLEMENTATION_STATUS.md` — parity tracking vs. the interpreter (update when shipping new language features).
- `docs/implementation/*.md` — design notes for async, caller_eval, and current dev questions.

## Contribution Tips

- Align new behaviour with `gene-new/` unless intentionally diverging; port interpreter tests when possible.
- Maintain GIR compatibility when touching instruction encoding.
- Prefer adding new VM instructions to `InstructionKind` with corresponding compiler/VM changes together in one change.
- Keep new docs linked from `docs/README.md` to avoid stale references.
