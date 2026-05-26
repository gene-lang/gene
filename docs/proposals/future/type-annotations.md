# Type Annotations for Native Functions and Methods

## Motivation

Gene programs can already declare parameter and return types for user-level callables —
`(fn add [a: Int b: Int] -> Int ...)`, `(method inc [n: Int] -> Int ...)`, and
the matching type aliases (`(type UserId Int)`). The matcher captures those
ids, and `process_args` enforces them at call time
(`src/gene/types/core/matchers.nim:334-447`, `src/gene/vm/exec.nim:2808-2815`).

Native callables — `NativeFn` procs registered from Nim via `def_native_method`,
`def_native_constructor`, and the standalone-fn variants used by every stdlib
module — are the gap. They carry only a half-formed signature stub today:
`Method.native_param_types: seq[(string, Value)]` and `native_return_type: Value`
are populated by `def_native_method` (`src/gene/types/classes.nim:222-237`) but
nothing consumes them for type checking, reflection, or JIT marshalling.
Callers see no type errors, the introspection surface returns nothing useful,
and the JIT-side `NativeFnSig` (`src/gene/native/trampoline.nim:5-13`) tracks
only ABI tags (`CrtInt64`, `CrtFloat64`, `CrtValue`) — not Gene types.

The goal is to make native callables typed in the same sense user callables are:
declared in one place, enforced at call boundaries, surfaced through reflection,
and round-trippable through serialization where the rest of the type system is.

## Non-Goals

- No new value semantics. Type annotations on native callables are advisory at
  parse time and enforced at runtime; they do not change argument layout, calling
  convention, or the NaN-boxed value representation.
- No automatic coercion. `Int -> Float` is not promoted silently; the existing
  rules of the type checker apply.
- No FFI/type inference from Nim type signatures in v1. Developers declare types
  explicitly on the Gene side of the boundary; the Nim signature stays
  `proc(vm, args, arg_count, has_keyword_args): Value`.

## Current State (Evidence)

| Surface | What exists | Gap |
|---|---|---|
| User `(fn …)` | `RootMatcher.has_type_annotations`, `return_type_id`, `process_args` enforces (`exec.nim:2813`) | — |
| User `(method …)` | Same matcher path, includes `self` as first param | — |
| Native `def_native_method` | `(name, type-value)` pairs + return value stored on `Method` (`classes.nim:222`) | Nothing reads them at call time |
| Native standalone fn | `VkNativeFn` ref, no signature object | No place to put types |
| Native constructor | `def_native_constructor(f)` — no params/returns | No signature |
| Native macro / macro-method | `is_macro: true`, args unevaluated | Must remain untyped |
| JIT marshalling | `NativeFnSig{argTypes, returnType}` keyed by `pointer(fn)` (`trampoline.nim`) | Only ABI tags; no Gene type ids |
| Dylib-bound fn (foreign symbol) | Nothing — no surface to dlopen and call a proc | Covered by sibling proposal: [`dynamic-library-binding.md`](dynamic-library-binding.md). Shares the same `NativeSignature`. |

## Design Overview

Introduce a single `NativeSignature` record that is the canonical home for a
native callable's typing information, and make every native registration API
take one. The structure parallels what `RootMatcher` already gives user
callables, reusing `CallableParamDesc` and `TypeId` so the runtime, the type
checker, the JIT, and reflection all see the same shape.

```
NativeSignature = ref object
  params: seq[CallableParamDesc]   # positional, positional-rest, keyword, keyword-rest
  return_type_id: TypeId
  module_path: string              # so type ids resolve in a registry
  receives_self: bool              # true for methods / constructors
  is_variadic: bool                # derived from params; cached
  arity_min, arity_max: int        # derived; cached
  abi: NativeFnSig                 # JIT marshalling tags; derived
```

The shape mirrors `Function.matcher` so existing code that walks a
`CallableParamDesc` (e.g. reflection, error reporting) works without
case-splitting on "native vs user".

### Constraint: Nim Cannot Name User-Defined Gene Types

Native registration runs in Nim at VM bootstrap (`src/gene/stdlib/*.nim`,
`src/genex/*.nim`), *before* any Gene module exists. At that point the only
types that resolve cleanly are the built-in primitives recognized by
`lookup_builtin_type` (`Int`, `Float`, `String`, `Bool`, `Nil`, `Any`) and
their applied/union forms.

The user-callable type resolver (`resolve_type_value_to_id_with_index`,
`matchers.nim:335`) handles unknown names by interning them as `TdkNamed`
against the *caller's* `module_path` and a per-CU `type_aliases` table. Nim
has neither: there is no Gene `import` chain at registration time, and no
calling compilation unit. A Nim-side `native_sig("[user: UserId]")` would
therefore intern `UserId` as a forward reference that can only resolve if
*every* future caller happens to have a `UserId` in its own scope — brittle
and wrong as a signature contract.

This makes Gene the primary surface for typing native callables. Nim
registration remains supported, but only as a shortcut for signatures whose
types are all built-in.

### Declaration Surface

**1. Gene-side (Primary)**

A Gene module imports the modules that define the types it needs, then
declares the native callable's signature using `$assign-type` family:

```gene
(import UserId from "myapp/types")
(import User    from "myapp/types")

($assign-type      myapp/users/find_by_email
                   [^prefix: String email: String] -> (User | Nil))
($assign-ctor-type myapp/users/User
                   [^id: UserId email: String])
($assign-method-type myapp/users/User "rename"
                   [new-name: String] -> User)
```

These forms run against the importing module's `type_aliases` /
`type_descs`, so `UserId` and `User` resolve to the same `TypeId`s the
user-level type checker would produce for `(fn ... -> User)`. The result is
written into the target callable's `NativeSignature` slot. For methods, the
implicit `self` parameter is type-checked against the owning class; declared
parameters cover only the call-site arguments.

A small companion convention for stdlib: each `src/gene/stdlib/*.nim` that
registers native callables ships a `src/gene/stdlib/types/<module>.gene`
file that runs during VM bootstrap *after* the Nim registration phase and
*before* user code executes. This is where stdlib's user-type-touching
signatures (e.g. `Array/.map [^idx (Fn [Any] -> Any)] -> (Array Any)`) live.

**2. Nim-side (Built-in-only shortcut)**

For signatures that mention only built-in primitives, the registration API
accepts an optional `NativeSignature` directly:

```nim
proc def_native_method*(self: Class, name: string, f: NativeFn,
                        sig: NativeSignature = nil)
```

A `native_sig` helper parses a literal string but is explicitly restricted
to built-in resolution; passing an unknown symbol is a compile-time error in
the helper, not a silent forward reference:

```nim
self.def_native_method("inc", counter_inc,
  native_sig("[n: Int] -> Int"))   # OK — Int is built-in

self.def_native_method("rename", user_rename,
  native_sig("[name: User] -> User"))   # Error: `User` is not a built-in
                                        # use $assign-method-type in Gene
```

This keeps the fast path fast (`Int`, `String`, `Float` arguments to JIT-hot
stdlib calls get their `NativeSignature.abi` without waiting for Gene
bootstrap) while making the boundary explicit: the moment a signature wants
a user type, it has to be expressed where `import` exists.

### Runtime Enforcement

Three call sites currently invoke native callables and need a single shared
validation step:

1. `call_native_with_gene_args` (`src/gene/vm/exec.nim:66`) — generic call.
2. The `VkNativeFn` branch of method dispatch (`src/gene/vm/dispatch.nim:559`).
3. The fast `try_native_call` / `try_native_call1` JIT path
   (`src/gene/vm/native.nim:173`).

All three resolve a `NativeSignature` from the callable, run the same
`validate_native_args(sig, args, has_kw)` that uses the existing
`validate_type` helper (`exec.nim:778-790`), and only then dispatch. Return-type
validation reuses the same helper applied to the returned `Value`. When
`vm.type_check` is false, the check short-circuits; the cost on the
type-checking-disabled path is one bool test plus the existing arity check.

### Reflection

`Method.params` / `Method.return_type` Gene-side accessors gain a real
implementation that reads `NativeSignature`. The reflection surface becomes
symmetric: a user method and a native method expose the same shape, and
existing tools (`/.signature`, doc generators, `gene compile --format pretty`)
get the same metadata for both.

### Interaction with the JIT

`NativeSignature.abi` is derived by mapping each `CallableParamDesc.type_id`
to a `CallArgType` (Int → `CatInt64`, Float → `CatFloat64`, everything else →
`CatValue`). Derivation happens at the point the signature is bound:

- Nim-side registration (built-ins only) → derived synchronously, before any
  Gene code runs.
- Gene-side `$assign-type` → derived at `$assign-type` execution time. If the
  callable has already been JIT-marshalled under the previous signature
  (typically the default all-`CatValue` shape), the JIT trampoline cache
  entry for `pointer(fn)` is invalidated so the next call re-derives. Native
  call sites already key by `pointer(fn)` in `trampoline.nim:5-13`, so
  invalidation is a single table delete.

This replaces the ad-hoc `register_native_sig` call sites and removes the
"JIT knows a signature the type system does not" duplication.

### Interaction with `serdes` / SQL Persistence

`NativeSignature` is *not* serialized — native callables are persisted as
symbolic references already. The type ids it embeds, however, belong to the
same module type registry that the in-flight type-serialization design
(`docs/proposals/future/type-serialization.md`) and the SQL persistence work
(`openspec/changes/add-sql-value-persistence/`) rely on. By reusing
`CallableParamDesc + TypeId` we get cross-feature consistency for free.

## Compatibility and Migration

- The old `def_native_method(self, name, f, params, returns)` overload becomes
  a thin shim that builds a `NativeSignature` — but it can only carry
  built-in type references, since that is all Nim ever had access to anyway.
- **Breaking Change**: The legacy
  `Method.native_param_types: seq[(string, Value)]` field is removed.
  Consumers of this field move to `NativeSignature`.
- The default for an unannotated callable is "all params `Any`, return
  `Any`" — equivalent to today's behaviour and preserved for backwards
  compatibility.
- Stdlib migration is staged: phase 1 ports primitives-only signatures to
  the Nim-side helper; phase 2 introduces `src/gene/stdlib/types/*.gene`
  shims for signatures that reference user-visible classes (`Array[T]`,
  `Map[K,V]`, callback `Fn` types, etc.).
- A `--strict-native-types` flag (or `App.app.strict_native_types`)
  escalates remaining unannotated callables to a warning, then to an error
  in a later release.

## Open Questions

- **Bootstrap ordering.** When exactly do `src/gene/stdlib/types/*.gene`
  shims run? Candidates: (a) at the end of `runtime.init` after all Nim
  registrations and before user code; (b) lazily on first use of each
  stdlib module. (a) gives deterministic typing at the cost of bootstrap
  time; (b) gives faster startup but means the same callable can be
  unannotated then annotated within a single program run.
- **Generic native functions.** Should we support `(fn[T] ...)` shaped
  signatures (`$assign-type ... [x: T] -> T`)? This is straightforward for
  Gene-side declarations (the existing `type_vars` mechanism applies) but
  pushes complexity into the JIT's `abi` derivation since `T` collapses to
  `CatValue` unconditionally.
- **Conflict policy for `$assign-type`.** If a callable already has a
  non-`Any` `NativeSignature` (e.g. set in Nim, then re-set in Gene), is
  the second assignment an error, an override, or required to match
  structurally? Default proposal: structural-match-or-error, with
  `$assign-type!` as the explicit-override form.

## Future Work

- Auto-derive `NativeSignature` from Nim type signatures via a `{.nativeFn.}`
  macro, once enough call sites use the typed API to justify the macro surface.
- Effect annotations (`!throws`, `!async`) for native callables, in line with
  the `!` effects syntax already parsed in `compile_native_fn`
  (`src/gene/compiler/functions.nim:296-299`).
- Overload resolution by signature for native methods that today simulate
  variants by inspecting `arg_count` (e.g. `String.sub`, `Array.slice`).
