# Coding Conventions

**Analysis Date:** 2026-02-26

## Naming Patterns

**Files:**
- `snake_case.nim` across core runtime and helpers (`type_checker.nim`, `runtime_helpers.nim`)
- command files are short lowercase names (`run.nim`, `eval.nim`, `compile.nim`)
- test files follow `test_<feature>.nim`

**Functions/Procs:**
- Internal procs typically use `snake_case` (`parse_options`, `init_thread_pool`, `read_token`)
- Some legacy or interop-style names use camelCase (`parseArgs`, `buildOpenAIConfig`)
- Native VM callbacks usually use `vm_<action>` naming (`vm_open`, `vm_query`, `vm_openai_chat`)

**Variables:**
- Local vars are lowercase with underscores (`conn_id`, `stmt_text`)
- Constants are uppercase snake case (`DEFAULT_COMMAND`, `GIR_VERSION`, `MAX_HTTP_WORKERS`)
- Global module vars are lowercase with descriptive suffixes (`connection_class_global`, `openai_clients`)

**Types:**
- Type/object names are PascalCase (`VirtualMachine`, `CompilationUnit`, `OpenAIConfig`)
- Enums use PascalCase names with prefixed values (`InstructionKind`, `VkInt`, `NctGuarded`)

## Code Style

**Formatting:**
- No dedicated formatter config file detected (no `.nimpretty`, no centralized formatter script)
- Nim idioms are followed: 2-space indentation, explicit type signatures on public APIs
- Inline comments are used sparingly; TODO markers are explicit

**Linting:**
- No separate linter config detected in repository root
- Quality enforcement is primarily via compile + test gates (`nimble test`, CI workflow)

## Import Organization

**Order (common pattern):**
1. Nim stdlib imports (`os`, `tables`, `strutils`, etc.)
2. local project imports (`../gene/types`, `./helpers`, `./vm/*`)
3. selective `from ... import ...` for narrower symbol imports

**Grouping:**
- Imports are usually grouped by source with blank lines between stdlib and internal modules
- `include` statements are used intentionally in VM/compiler composition files

**Path Aliases:**
- No custom alias system; relative import paths are used directly

## Error Handling

**Patterns:**
- Runtime/extension errors use `raise new_exception(types.Exception, <message>)`
- Command handlers convert failures to `CommandResult` via `failure(...)`
- Command boundaries wrap execution in `try/except CatchableError`

**Error Types:**
- Runtime semantic errors: Gene `types.Exception`
- Command-level operational errors: returned `CommandResult.error`
- Integration-specific errors: dedicated error objects (for example `OpenAIError`)

## Logging

**Framework:**
- Nim `logging` module at command layer (`src/commands/base.nim`)
- Level threshold set by `--debug` flag in command handlers

**Patterns:**
- Most core code avoids noisy logging by default
- Debug branches in integration modules use compile-time debug toggles

## Comments

**When to Comment:**
- Comments explain invariants, migration notes, and non-obvious behavior
- TODO comments are used to track known incomplete areas

**Doc Comments:**
- Public helper procs occasionally include concise intent comments
- Heavy API docs are maintained in `docs/*.md` rather than code annotations

**TODO Comments:**
- Pattern: `# TODO: ...` appears in tests and runtime implementation files
- TODOs are often paired with disabled tests to document missing behavior

## Function Design

**Size:**
- Large orchestration files exist (`src/gene/vm.nim`, `src/gene/compiler.nim`) but are segmented with `include`/module splits
- Smaller modules encapsulate feature-specific logic (`src/gene/compiler/*.nim`, `src/gene/vm/*.nim`)

**Parameters:**
- Native VM bindings follow a consistent callable signature:
  `proc fn(vm: ptr VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value`
- Argument validation is usually immediate and fail-fast at function start

**Return Values:**
- Commands return structured `CommandResult`
- Runtime methods return `Value` and use `NIL` when no meaningful value is returned

## Module Design

**Exports:**
- Most command modules expose `init*` and `handle*`
- Core modules expose targeted public APIs with `*` export markers

**Composition:**
- VM/compiler use modularized files plus include-based composition for performance/organization
- Extension modules self-register through init callbacks (`VmCreatedCallbacks`)

---
*Convention analysis: 2026-02-26*
*Update when patterns change*
