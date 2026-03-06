# Architecture Review: Gene as a Gradual-First Language

**Reviewer:** Claude (AI)
**Date:** 2026-02-06
**Branch:** static-lang2
**Scope:** src/gene/ — type system, compiler, VM, native codegen

## Verdict

**The foundation is strong for a gradual-first language. The next architectural step is a descriptor-centric type pipeline: type descriptor objects during compilation, persisted in GIR, and materialized to runtime type objects (with lazy implementation loading).**

## Product Direction (Gradual-First)

1. **Dynamic remains baseline**: unannotated code must keep working with `Any` and dynamic dispatch.
2. **Types are opt-in guarantees**: annotations improve safety, tooling, and optimization where desired.
3. **Strictness is optional**: strict modes should be per module/profile, not global language policy.
4. **Optimizations are semantics-preserving**: typed fast paths must always have dynamic fallback.
5. **Static-only features are secondary**: prioritize features that improve mixed typed/untyped code first.

## Design Decisions to Preserve

1. **Descriptor-centric type model**: compile-time should produce canonical type descriptors (`TypeDesc`) with stable IDs, not string-serialized types as canonical identity.
2. **Predeclaration for forward references**: compiler predeclares local/module names so definitions can be referenced before textual declaration where supported.
3. **Runtime type preservation is selective**: locals and function params carry enforceable expectations today; namespace/class-member storage is still mostly dynamic unless explicitly checked.
4. **Dynamic semantics remain default**: descriptor-driven typing must preserve runtime fallback behavior for untyped code.

## Target Architecture (Type Descriptor Pipeline)

1. **Compilation phase**:
   - Type checker produces canonical `TypeDesc` objects (named, applied, union, function, variables).
   - Compiler stores `TypeId` references in scope/matcher metadata instead of strings.
2. **GIR phase**:
   - GIR persists a per-module type descriptor table (`TypeId -> TypeDesc`) plus references from bytecode metadata.
   - Imported GIR modules expose descriptor metadata for boundary/type-resolution checks.
3. **Runtime phase**:
   - Loader interns descriptors into runtime type objects (`RtTypeObj` / class-backed wrappers).
   - Validation (`validate_type`) operates on descriptor/runtime objects, not reparsed strings.
4. **Implementation materialization**:
   - Runtime type objects can carry implementation hooks.
   - Constructor/method/init bodies can be compiled/linked on demand while preserving current module/class init semantics.

## What's Already Solid

### 1. Type Checker (~2k lines, fully functional)

`src/gene/type_checker.nim` implements a real Hindley-Milner-style unification engine:

- `TypeExpr` ADT: `TkAny`, `TkNamed`, `TkApplied`, `TkUnion`, `TkFn`, `TkVar`
- Proper occurs check, substitution resolution, scoped type environments
- Handles `var`, `fn`, `class`, `method`, `ctor`, `match`, `case`, `for`, `while`, `try/catch`
- ADT support with `Result<T,E>` / `Option<T>` built in, plus user-defined parametric ADTs via `type`
- Class inheritance tracking with field and method type lookups
- Integrated into compiler pipeline via `parse_and_compile*` with `strict = false` (gradual mode)

### 2. Runtime Type Validation

`src/gene/types/runtime_types.nim` provides the runtime half:

- NaN-tag-based fast type tests (`is_int`, `is_float`, `is_string`, etc.)
- `validate_type()` raises catchable Gene exceptions on mismatch
- Union, ADT, and function type compatibility at runtime
- Wired into VM variable, argument, return, and typed-property paths when descriptor expectations exist
- Current runtime checks are descriptor-backed; strings remain mostly for diagnostics and display

### 3. NaN-Boxing Value Representation

The 8-byte NaN-boxed `Value` already encodes primitive type tags (INT, FLOAT, STRING, SYMBOL, ARRAY, MAP, INSTANCE, GENE):

- Primitive type checks are single bit-mask operations (no indirection)
- Tag space naturally segments typed vs untyped values
- Gradual typing gates on these tags at zero cost for primitives

### 4. Native Compilation Pipeline

`src/gene/native/hir.nim` defines a typed SSA-form IR (`HirType`: I64, F64, Bool, Ptr, Value) with x86-64 and ARM64 backends. Type information flows through to register allocation and instruction selection.

### 5. GIR Serialization

`src/gene/gir.nim` serializes scope `type_expectations` and module type metadata. Type information already persists across compilation runs; the planned upgrade is descriptor-table serialization instead of string-only expectations.

### 6. Module Type Metadata Across Imports

Module definitions now carry structural type metadata (`ModuleTypeNode`) through compilation and GIR serialization, and the type checker consumes this during import resolution. This directly improves gradual typing at module boundaries.

## Architectural Gaps (Against Gradual-First Goals)

### 1. No Typed IR Between AST and Bytecode (Optimization Gap)

Compiler goes AST → bytecode directly. No place for:
- Type-driven dead code elimination
- Monomorphization of generic functions
- Constant propagation with type knowledge
- Devirtualization of method calls

The HIR exists but only for the native JIT path.

### 2. No Canonical Descriptor Pipeline Across Compile/GIR/Runtime

Type information still crosses major boundaries as strings (`ScopeTracker.type_expectations`, matcher `type_name`, return type names). Caching hides some costs, but the bigger issue is identity/coherence: compile-time, GIR, and runtime do not share a canonical descriptor object graph with stable IDs.

### 3. Type Checker Only Partially Informs Bytecode Emission

The checker feeds metadata into compilation (binding/param/return type props), and the compiler/VM already use that for gradual boundary validation. What is missing is optional opcode specialization/typed instruction selection for performance; this is a secondary optimization track, not a correctness blocker for gradual typing.

### 4. Flow Typing Is Partial

Type narrowing exists in limited form, but it is not yet comprehensive across `if`/`case`/`match` patterns and richer guards. Gradual-first ergonomics still require broader and more consistent flow-sensitive narrowing.

### 5. No First-Class Generics for Functions/Classes

`TkApplied` supports applied types (`Array<T>`, `Map<K,V>`, etc.), and users can define parametric ADTs. The missing piece is first-class generics for functions/classes (with proper polymorphic instantiation/monomorphization). Constructor typing is still partially special-cased (`Ok`/`Err`/`Some`/`None`).

### 6. Class Fields Are Still Raw Storage at Runtime

Instance fields are still stored as raw `Value` slots/tables. Runtime `Class` objects now carry property type metadata and validate typed assignments, but there is still no specialized typed field layout or deeper storage optimization.

## Deferred / Out of Scope (Current Phase)

- **Interfaces and type aliases**: currently compile-time oriented in the compiler path; runtime enforcement remains limited.
- **Comptime-heavy type features**: kept separate from runtime gradual guarantees.
- **Enum/interface deep integration**: tracked as follow-up work; not required to deliver core gradual-first goals.

## Gradual Typing Strengths

The architecture is better suited for gradual than full static typing:

1. **`Any` is the top type** — unannotated code defaults to `Any`, works dynamically
2. **Runtime checks at boundaries** — `validate_type` at var assignment and function calls
3. **Type checker is non-strict** — unknown types don't block compilation
4. **Dynamic dispatch with inline caches** — `IkUnifiedMethodCall*` handles "typed receiver, dynamic method" efficiently

## Recommendations

| Priority | Gap | Fix |
|----------|-----|-----|
| **P0** | No canonical descriptor pipeline | Introduce `TypeDesc` + stable `TypeId` across checker, compiler metadata, GIR, and VM |
| **P0** | Runtime still string-backed | Materialize descriptor-backed runtime type objects and validate against them |
| **P0** | Lazy implementation integration | Attach implementation hooks to runtime type objects; compile/load ctor/method/init bodies on demand |
| **P0** | Flow typing is partial | Extend narrowing across `if`/`case`/`match` and richer guard forms |
| **P1** | Gradual boundary UX | Improve runtime type error diagnostics (location, expected/actual, binding context) |
| **P1** | Metadata continuity | Keep backward-compatible GIR migration path (string metadata -> descriptor table) |
| **P1** | Type metadata not used for specialization | Add optional specialized instruction variants with dynamic fallback |
| **P2** | No first-class generics for fn/class | Add polymorphic fn/class generics; choose monomorphization or erasure |
| **P2** | No typed IR for bytecode path | Introduce lightweight typed IR only if needed for measurable wins |
| **P2** | No runtime field layout optimization | Pack fields as typed slots only behind optional optimization mode |

## Summary

The type checker is real (unification, ADTs, class hierarchy). Runtime validation works. NaN-boxing provides fast primitive type checks. The native JIT pipeline demonstrates typed execution. The main work now is **descriptor unification**: one canonical type representation flowing from compilation to GIR to runtime objects, with lazy implementation loading where appropriate.

Full static mode can remain a future optional track. The near-term strategy should optimize the mixed typed/untyped experience while replacing string-based type transport with descriptor-based identity.
