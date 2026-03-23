# Migrate Gene to a Static Language

This document captures the architectural changes required to move Gene from a dynamic runtime to a statically typed language that still feels ergonomic for AI and humans. It complements `docs/proposals/future/ai-first-design.md` but focuses on the *systems changes* needed to make static typing, compile-only builds, interfaces, and module-level compilation practical.

## Goals

- Make Gene a statically typed language with **implicit Any** defaults.
- Allow **full AOT compilation** of modules, classes, functions, and method bodies.
- Allow compiling **without executing top-level code**.
- Provide **interfaces** and compile-time conformance checks.
- Keep the language friendly for AI: predictable, machine-checkable semantics, clear errors.

## Non-Goals (for now)

- WASM memory model decisions (tracked separately once requirements are clearer).
- Full HM inference across modules (we can incrementally improve inference later).
- Rewriting the VM to do full type enforcement at every operation (type *checking* is primarily compile-time; type *objects* exist at both compile time and runtime).

## Guiding Principles

- **Any is the base type.** Missing annotations imply `Any` rather than error.
- **Explicit types are encouraged** and enforced when present.
- **Types are real objects in both phases.** `Int`, `Str`, user-defined classes, enums, and interfaces are concrete type objects during compilation *and* execution.
- **Types are preserved, not erased.** All variables, namespace members, and function arguments carry their type at runtime. Intermediate expression types are inferred from their source (the variable, function return type, or literal they originate from).
- **Forward declarations are supported.** A type can be referenced before it is fully defined within the same module. The compiler uses multi-pass resolution to handle forward references.
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

## Dual-Phase Type Objects

A core design decision: **types are real objects at both compilation and execution time.** This is not the same as "everything is dynamic" — type *checking* happens at compile time, but type *objects* persist into runtime for reflection, `is?` checks, dynamic dispatch, and error messages.

```gene
(fn f [i: Int] -> Str ...)   # Int and Str are real types at compile time AND runtime
(class A ...)                 # A is a known type during compilation AND a class object at runtime
```

### Why dual-phase?

- **Compile time**: The type checker needs type objects to validate annotations, check conformance, and infer types. When the compiler encounters `Int` in a type position, it resolves to a known type entry — not just a string name.
- **Runtime**: The VM needs type objects for method dispatch (`get_class()`), `is?` checks, reflection, and meaningful error messages. Gene already stores classes as `VkClass` values.
- **Consistency**: A `(class A)` declaration should mean the same thing in both phases — it creates a type that code can reference for checking and that instances point back to at runtime.

### Type Object Lifecycle

**Built-in types** (`Int`, `Str`, `Bool`, `Array`, `Map`, etc.):
- Pre-registered in the compiler's type environment before any user code is processed.
- Pre-registered as runtime class objects (`App.app.int_class`, `App.app.string_class`, etc.) during VM initialization.
- Available in both phases without any user declaration.

**User-defined classes** (`(class A ...)`):
- **Compilation**: Registered in the compiler's type table immediately when the declaration is encountered. Subsequent code in the same module can reference `A` as a type for annotations and checking.
- **Execution**: The compiled instructions create a `Class` object (wrapped as `VkClass`) in the current scope/namespace. This is how Gene already works.

**Enums** (`(enum Option [T] ...)`):
- **Compilation**: Registered as a type with variant metadata. The compiler generates constructor functions and records variant tags for exhaustiveness analysis.
- **Execution**: Enum type and variant constructors exist as callable values.

**Interfaces** (`(interface Iterable ...)`):
- **Compilation**: Registered as a type with required method signatures. Used for conformance checking against classes.
- **Execution**: Optionally preserved as metadata for runtime `implements?` queries.

### Type Preservation and Inference

Types are **preserved** at runtime — they are not erased after compilation. Every named binding carries its type:

- **Variables** (`(var x: Int 10)`) — type is stored alongside the value in the scope slot.
- **Function arguments** (`(fn f [i: Int] -> Str ...)`) — parameter and return types are part of the function object at runtime.
- **Namespace members** — exported names carry their declared or inferred type, available for both type checking by importers and runtime reflection.

**Intermediate values** (temporaries on the VM stack) do not need explicit annotations. Their types are **inferred from their source**:

```gene
(var x: Int 10)
(var y: Int 20)
(var z (x + y))       # z's type is inferred as Int (from Int + Int -> Int)
(var s (f x))         # s's type is inferred as Str (from f's return type)
(var a [1 2 3])       # a's type is inferred as (Array Int) from literal contents
```

The inference rule is simple: the type of an expression is determined by where it comes from — the type of the variable being read, the return type of the function being called, or the type of the literal being written.

### Forward Declarations

Types can be referenced before they are fully defined within the same module. The compiler uses **multi-pass resolution**:

1. **First pass (declaration scan)**: Collect all type names (`class`, `enum`, `interface`) in the module and create placeholder type entries.
2. **Second pass (full compilation)**: Resolve type bodies, method signatures, and annotations against the complete set of known types.

```gene
(class Node
  (var value: Int)
  (var next: (Option Node))   # Node references itself — OK
)

(class A
  (var b: B)                   # Forward reference to B — OK
)

(class B
  (var a: A)
)
```

This applies within a single module. Cross-module forward references are not needed because imports are resolved before the importing module is compiled.

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

During compilation, `class`, `enum`, and `interface` declarations are processed eagerly:
- Their type entries are registered in the compiler's type table immediately.
- Subsequent code in the same module can reference them in type annotations.
- The compiled GIR includes type metadata so downstream modules can import types without re-parsing source.

This allows:
- Building AOT artifacts in CI
- Loading modules without side effects
- Reproducible builds
- Cross-module type checking from GIR alone

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

**Syntax (see `docs/proposals/future/ai-first-design.md` Phase 2):**
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

1. **Dual-phase type registration**
   - Register built-in types (`Int`, `Str`, `Bool`, `Array`, `Map`, etc.) in the compiler's type environment at startup, mapped to the same class objects the VM already initializes.
   - When the compiler encounters `(class A ...)`, register `A` as a known type in the compiler's scope immediately (before emitting runtime instructions).
   - Resolve type names in annotations (e.g., `i: Int`) to actual type entries, not just strings.

2. **Implicit Any defaults**
   - Update type checker to treat missing annotations as `Any`.
   - Add warnings for unintended `Any` later.

3. **Compile-only pipeline**
   - Split module compilation from execution.
   - Introduce `__init__` and compile-only mode.
   - Persist type metadata in GIR so downstream modules can import types without re-parsing source.

4. **Conditional imports**
   - Add compile-time condition construct.
   - Disallow runtime conditional imports in compile-only builds.

5. **Algebraic data types (enums)**
   - Add enum declarations and constructor generation.
   - Register enum types in the compiler's type table at declaration time.
   - Compile pattern matching with exhaustiveness analysis.
   - Persist enum metadata in GIR.

6. **Interfaces**
   - Define syntax + conformance checks.
   - Register interface types in the compiler's type table at declaration time.
   - Add class metadata and compiler validation.

## Open Questions

- Should module `__init__` be *optional* (i.e., pure modules) or always generated?
- How to represent interface conformance in GIR for tooling?
- How to represent enum metadata (type id, variants, fields) in GIR?
- Do we allow partial type checking (warnings-only) for legacy code?
  No. This is a greenfield language. We will not support legacy code.
- Should `Any` default be configurable per project?
  No.
- What compile-time capabilities are allowed beyond env + string ops (file reads, network)?
- Should the compiler's type table be a shared structure between the type checker and the code generator, or should they maintain separate representations?
- What is the runtime representation of preserved types? Options: attach type tag to every scope slot, store type metadata only on function/class objects, or both.

## Related Documents

- `docs/proposals/future/ai-first-design.md` — overall AI-first roadmap
- `docs/proposals/future/ai-first.md` — AI-first language overview
- `openspec/changes/add-static-typing/*` — initial static typing change
- `openspec/changes/add-module-system/*` — module system change
