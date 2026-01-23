# Migrate Gene to a Static Language

This document captures the architectural changes required to move Gene from a dynamic runtime to a statically typed language that still feels ergonomic for AI and humans. It complements `docs/ai-first-design.md` but focuses on the *systems changes* needed to make static typing, compile-only builds, interfaces, and module-level compilation practical.

## Goals

- Make Gene a statically typed language with **implicit Any** defaults.
- Allow **full AOT compilation** of modules, classes, functions, and method bodies.
- Allow compiling **without executing top-level code**.
- Provide **interfaces** and compile-time conformance checks.
- Keep the language friendly for AI: predictable, machine-checkable semantics, clear errors.

## Non-Goals (for now)

- WASM memory model decisions (tracked separately once requirements are clearer).
- Full HM inference across modules (we can incrementally improve inference later).
- Rewriting the VM to enforce types at runtime (type checking is compile-time).

## Guiding Principles

- **Any is the base type.** Missing annotations imply `Any` rather than error.
- **Explicit types are encouraged** and enforced when present.
- **Compile-only must be safe**: no side effects, no conditional runtime imports.
- **AOT should be deterministic** and reproducible from source + flags.

## Current Baseline (today)

- Dynamic execution model: parse + compile + execute immediately.
- Type checker exists but defaults to strict behavior in some areas.
- Imports can run code at load time (module top-level execution).
- Classes are compiled and executed in the same pass.

## Target Execution Model

```
Source -> Parse -> Type Check -> Compile -> AOT Artifact (GIR)
                               |
                               +-> Run (optional): execute module init
```

Key distinction: **compilation is separate from execution**. A module can be compiled into GIR without executing top-level code.

## Architectural Changes

### 1) Type System Defaults (Implicit Any)

- Missing type annotations are treated as `Any`.
- Type checking still runs; it only fails when concrete types are violated.
- Add optional strict modes later:
  - `--require-annotations` (future)
  - `--warn-any` (future)

### 2) Compile-Only Modules

We need to compile modules without executing their top-level expressions.

**Proposed shape:**
- Every module compiles into:
  - `__init__` function (top-level executable body)
  - `__defs__` (functions, classes, method bodies compiled eagerly)
- `gene compile` produces GIR without calling `__init__`.
- `gene run` executes `__init__` after loading GIR.

This allows:
- Building AOT artifacts in CI
- Loading modules without side effects
- Reproducible builds

### 3) Compile-Time Execution + Conditional Imports

Conditional import in a static compile-only world is dangerous if evaluated at runtime.
We will use **compile-time execution** to decide imports and generate code.

**Syntax:**
```gene
(comptime
  (var target ($env "GENE_TARGET"))
  (if (target == "wasm")
    (import std/wasm [mem])
  else
    (import std/native [mem])
  )
)
```

**Rules:**
- `(comptime ...)` executes during compilation only.
- It can define variables, do string operations, and read environment variables.
- Any side effects happen at compile time, not runtime.
- Runtime conditional imports should be disallowed or treated as dynamic `require`.

### 4) Interfaces

Interfaces define method signatures that classes must implement.

**Candidate syntax:**
```gene
(interface Iterable
  (method iter [] -> (Iterator Any))
)

(class List
  ^implements [Iterable]
  (method iter [] -> (Iterator Any)
    ...)
)
```

**Compiler requirements:**
- Interface methods are type-checked like function signatures.
- Class conformance checked at compile time.
- Optional runtime reflection metadata for `implements?`.

### 5) AOT Compilation Targets

AOT requires compiling method/function bodies in advance (no lazy compilation at first call).

- Eagerly compile all `fn`, `method`, `ctor` in a module.
- Allow flags to include/exclude debug metadata.
- Maintain GIR compatibility as the stable output format.

### 6) Algebraic Data Types (Enums)

Enums are a foundational part of the static language. They must be compiled, not provided
as runtime stdlib constructors.

**Syntax (see `docs/ai-first-design.md` Phase 2):**
```gene
(enum Option [T]
  (Some [value: T])
  None
)
```

**Compilation outcomes:**
- Generate constructor functions/values for each variant.
- Emit type metadata for pattern matching and tooling.
- Preserve variant tags for exhaustiveness analysis.

**Compile-time requirements:**
- Generate constructors when enum is compiled (no runtime native fallback).
- Store enum metadata in GIR for type checking and tooling.
- Enable compile-time exhaustiveness checks for `case/when`.

## Migration Strategy

1. **Implicit Any defaults**
   - Update type checker to treat missing annotations as `Any`.
   - Add warnings for unintended `Any` later.

2. **Compile-only pipeline**
   - Split module compilation from execution.
   - Introduce `__init__` and compile-only mode.

3. **Conditional imports**
   - Add compile-time condition construct.
   - Disallow runtime conditional imports in compile-only builds.

4. **Algebraic data types (enums)**
   - Add enum declarations and constructor generation.
   - Compile pattern matching with exhaustiveness analysis.
   - Persist enum metadata in GIR.

5. **Interfaces**
   - Define syntax + conformance checks.
   - Add class metadata and compiler validation.

## Open Questions

- Should module `__init__` be *optional* (i.e., pure modules) or always generated?
- How to represent interface conformance in GIR for tooling?
- How to represent enum metadata (type id, variants, fields) in GIR?
- Do we allow partial type checking (warnings-only) for legacy code?
- Should `Any` default be configurable per project?
 - What compile-time capabilities are allowed beyond env + string ops (file reads, network)?

## Related Documents

- `docs/ai-first-design.md` — overall AI-first roadmap
- `docs/ai-first.md` — AI-first language overview
- `openspec/changes/add-static-typing/*` — initial static typing change
- `openspec/changes/add-module-system/*` — module system change
