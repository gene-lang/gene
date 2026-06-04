# Type Annotations for Native Functions, Constructors, and Methods

## Motivation

Gene programs can already declare parameter and return types for user-level
callables — `(fn add [a: Int b: Int] -> Int ...)`, `(method inc [n: Int] -> Int ...)`,
type aliases (`(type UserId Int)`), and even local variables
(`(var x: Int ...)`). The matcher captures those ids
(`resolve_type_value_to_id_with_index`, `src/gene/types/core/matchers.nim:335`),
`process_args` enforces them at function call time
(`src/gene/vm/args.nim:104`, invoked from `src/gene/vm/exec.nim:2808-2815`), the
`IkVar` instruction enforces variable annotations at assignment time
(`src/gene/vm/exec.nim:785-788`), and the static type checker validates call
sites ahead of execution.

Native callables — `NativeFn` procs registered from Nim via `def_native_method`,
`def_native_constructor`, and the standalone-fn variants used by every stdlib
module — are partially typed and inconsistently so:

- **Methods** carry a *class-`Value`*-based signature stub today:
  `Method.native_param_types: seq[(string, Value)]` and `native_return_type: Value`
  are populated by `def_native_method` (`src/gene/types/classes.nim:222-237`).
  The **static type checker already consumes them** — `check_native_method_call`
  (`src/gene/type_checker.nim:2164-2225`) checks arity and per-argument class
  compatibility and uses the declared return type. So typed native *methods*
  already surface mismatches at call sites — as gradual warnings, since the
  checker is only ever run non-strict (`pipeline.nim:479`).
- **Runtime** dispatch does *not* type-check. The `VkNativeFn` branch of method
  dispatch checks arity only (`validate_native_method_arity`,
  `src/gene/vm/dispatch.nim:560`); `call_native_with_gene_args`
  (`src/gene/vm/exec.nim:66`) checks nothing. The class-`Value` types are invisible
  at runtime.
- **Standalone native fns** (`VkNativeFn` ref, not a `Method`) and **constructors**
  (`def_native_constructor(f)`, `src/gene/types/classes.nim:271`, no params) have
  no signature storage at all — no static checking, no runtime checking.
- **The JIT** has an ABI-tag table (`NativeFnSig{argTypes, returnType}` keyed by
  `pointer(fn)`, `src/gene/native/trampoline.nim:5-19`) that the HIR lowering
  *reads* (`src/gene/native/bytecode_to_hir.nim:156,168`) but that is
  **never populated** — `register_native_sig` (`trampoline.nim:12`) has zero
  callers. Typed native-call marshalling is dormant infrastructure.

So there are two diverging native-type representations (class-`Value` for the
checker; ABI tags for the JIT, currently empty), zero runtime enforcement, and
two whole callable kinds (standalone fns, constructors) with no typing at all.
Meanwhile user callables and variables use a single, coherent `TypeId`-based
path end to end.

The goal is to give native functions, constructors, and methods typing that is
**aesthetically and mechanically identical to user-level typing**: written in the
same declaration grammar, resolved through the same `TypeId` machinery, enforced
through the same `validate_type` core, surfaced through the same reflection, and
checked by the same static type checker. The preferred declaration point is
**Gene code, at the moment the callable is added to a namespace or class**, so
that any `import`ed custom types are in scope and resolve to the same `TypeId`s
a `(fn ... -> User)` would produce.

## Non-Goals

- No new value semantics. Type annotations on native callables are advisory at
  parse time and enforced at runtime; they do not change argument layout, calling
  convention, or the NaN-boxed value representation.
- No automatic coercion. `Int -> Float` is not promoted silently; the existing
  rules of the type checker apply.
- No FFI/type inference from Nim type signatures in v1. Developers declare types
  explicitly on the Gene side of the boundary; the Nim signature stays
  `proc(vm, args, arg_count, has_keyword_args): Value`.
- No new signature *grammar*. Native callables reuse the existing Gene
  declaration grammar (`[a: T b: T ^kw: T] -> R`), shared with the sibling
  [`dynamic-library-binding.md`](dynamic-library-binding.md) proposal.

## Current State (Evidence)

| Surface | Static check | Runtime enforcement | Representation | Gap |
|---|---|---|---|---|
| Variable `(var x: Int …)` | — | ✅ `IkVar` (`exec.nim:785-788`) | `TypeId` | — |
| User `(fn …)` | ✅ checker | ✅ `process_args` (`args.nim:104`) | `RootMatcher` / `TypeId` | — |
| User `(method …)` | ✅ checker | ✅ `process_args` (self is first param) | `RootMatcher` / `TypeId` | — |
| Native `def_native_method` | ✅ `check_native_method_call` (`type_checker.nim:2164`) | ❌ arity only (`dispatch.nim:560`) | **class-`Value`** pairs (`classes.nim:222`) | No runtime check; wrong representation |
| Native standalone fn | ❌ none (checker handles method callees only, `type_checker.nim:2244`) | ❌ | none | No signature anywhere |
| Native constructor | ❌ `def_native_constructor(f)` no params (`classes.nim:271`) | ❌ | none | No signature anywhere |
| Native macro / macro-method | n/a (`is_macro: true`, args unevaluated) | n/a | n/a | Must remain untyped |
| JIT → NativeFn marshalling | n/a | uses `NativeFnSig` ABI tags (`trampoline.nim`) | ABI tags, **table empty** | Never populated (`register_native_sig` has no callers) |
| Dylib-bound fn (foreign symbol) | — | — | — | Covered by [`dynamic-library-binding.md`](dynamic-library-binding.md); shares this `NativeSignature` |

## Design Overview

One signature shape serves the whole runtime. A `NativeSignature` is defined to
be **`RootMatcher`-shaped** — it reuses `CallableParamDesc` and `TypeId` so the
runtime, the static type checker, the JIT, and reflection see the same structure
for native and user callables and never case-split on "native vs user".

```
NativeSignature = ref object
  params: seq[CallableParamDesc]   # positional, positional-rest, keyword, keyword-rest
  return_type_id: TypeId
  type_descriptors: seq[TypeDesc]  # the interned descriptors params/return resolve against
  module_path: string              # so named type ids resolve in the module registry
  receives_self: bool              # true for methods / constructors
  has_type_annotations: bool       # cached: any param or return is non-Any
  is_variadic: bool                # derived from params; cached
  arity_min, arity_max: int        # derived; cached
  abi: NativeFnSig                 # JIT marshalling tags; derived (see JIT section)
```

`params`, `return_type_id`, `type_descriptors`, and `has_type_annotations` are
the *same fields* `RootMatcher` already carries (`src/gene/types/type_defs.nim:731-741`).
That is deliberate: the signature is produced by the **same resolver** the
declaration grammar already runs (`resolve_type_value_to_id_with_index`,
`matchers.nim:335`) and is validated by the **same core** that user callables and
variables use (`validate_type`, `src/gene/types/runtime_types.nim:891`). See
[Representation and Reuse](#representation-and-reuse) for why this is a
`RootMatcher`-shaped record rather than a literal second `RootMatcher`.

### Constraint: Nim Cannot Name User-Defined Gene Types

Native registration runs in Nim at VM bootstrap (`src/gene/stdlib/*.nim`,
`src/genex/*.nim`), *before* any Gene module exists. At that point the only
types that resolve cleanly are the built-ins recognized by `lookup_builtin_type`
(`src/gene/types/descriptors.nim:39-54`): `Any`, `Int`, `Float`, `String`,
`Bool`, `Nil`, `Void`, `Symbol`, `Char`, `Array`, `Map`, plus their applied
(`(Array Int)`) and union (`Int | String`) forms.

The user-callable type resolver handles *unknown* names by interning them as
`TdkNamed` against the *caller's* `module_path` and a per-CU `type_aliases` table
(`matchers.nim:353-355`). Nim has neither: there is no Gene `import` chain at
registration time, and no calling compilation unit. A Nim-side
`native_sig("[user: UserId]")` would intern `UserId` as a forward reference that
resolves only if *every* future caller happens to have a `UserId` in scope —
brittle and wrong as a signature contract.

This is the core reason the primary surface is **Gene code at binding time**:
that is the only place where `import` exists and a user type name resolves to a
stable `TypeId`. Nim-side registration stays supported, but only as a shortcut
for signatures whose types are all built-in.

### Declaration Surface

**1. Gene-side at binding time (Primary)**

A native callable is declared with the *normal* `fn` / `ctor` / `method`
grammar inside a `ns` or `class`, where imported custom types are in scope. The
implementation pointer is supplied with `^native`, exactly as the sibling
[`dynamic-library-binding.md`](dynamic-library-binding.md) proposal does for
foreign symbols — there is no separate signature syntax.

```gene
(import UserId from "myapp/types")
(import User   from "myapp/types")

(ns myapp/users
  (fn find-by-email [^prefix: String email: String] -> (User | Nil)
    ^native users-find-by-email)        ; users-find-by-email: a registered NativeFn

  (class User
    (ctor [^id: UserId email: String]
      ^native user-new)

    (method rename [new-name: String] -> User
      ^native user-rename)))
```

Because this is ordinary Gene compiled in the module's context, `UserId` and
`User` resolve through the module's `type_aliases` / `type_descriptors` to the
same `TypeId`s the static checker would produce for `(fn ... -> User)`. The
compiler builds the `NativeSignature` from the matcher it already constructs for
the declaration (`compile_fn`, `src/gene/compiler/functions.nim:89`;
`compile_method_definition:243`; `compile_constructor_definition:326`), and binds
it to the callable when the declaration publishes into the namespace/class. For
methods and constructors the implicit `self` is type-checked against the owning
class; declared parameters cover only the call-site arguments
(`receives_self: true`).

`^native <name>` references a `NativeFn` already registered in the runtime (the
stdlib/extension case) or a foreign symbol via `($dyn/find ...)` (the FFI case).
The two proposals share this mechanism; this proposal owns the *typing*, the
FFI proposal owns *foreign-symbol resolution and the cdecl trampoline*.

**2. Gene-side retrofit for Nim-registered stdlib (`$assign-type` family)**

Built-in classes (`Array`, `Map`, `String`) and their methods are *created in
Nim*; they cannot be re-declared in a Gene `class` body. For these, a Gene
module attaches a signature to an already-registered callable. Each
`src/gene/stdlib/*.nim` that registers user-type-touching natives ships a
companion `src/gene/stdlib/types/<module>.gene` that runs during bootstrap
*after* Nim registration and *before* user code:

```gene
($assign-method-type Array "map" [^idx (Fn [Any] -> Any)] -> (Array Any))
($assign-type        myapp/users/legacy-find [email: String] -> (User | Nil))
($assign-ctor-type   myapp/users/User        [^id: UserId email: String])
```

These run against the importing module's `type_aliases` / `type_descriptors`, so
they have the same access to custom types as a binding-site declaration. The
result is written into the target callable's `NativeSignature` slot. This is the
*retrofit* path; prefer binding-site declaration (surface 1) for anything
declared in Gene in the first place.

**3. Nim-side built-in-only shortcut**

For signatures that mention only built-ins, registration accepts an optional
`NativeSignature` directly, so JIT-hot stdlib primitives are typed before Gene
bootstrap runs:

```nim
proc def_native_method*(self: Class, name: string, f: NativeFn,
                        sig: NativeSignature = nil)

self.def_native_method("inc", counter_inc,
  native_sig("[n: Int] -> Int"))        # OK — Int is built-in

self.def_native_method("rename", user_rename,
  native_sig("[name: User] -> User"))   # compile-time error in native_sig:
                                        # `User` is not built-in — use $assign-method-type
```

`native_sig` parses a literal string but is explicitly restricted to built-in
resolution; an unknown symbol is a compile-time error in the helper, not a silent
forward reference.

### Representation and Reuse

The old `Method.native_param_types: seq[(string, Value)]` is **class-`Value`**-based:
each param's expected type is a `VkClass` value (`type_defs.nim:578-580`). The
static checker consumes that via `native_type_from_class_value`
(`type_checker.nim:2107`) and `class_matches_expected` (`type_checker.nim:2127`).
This proposal moves native typing to **`TypeId`** + the module type registry —
the representation user callables, variables, and serialization already use.

Two structural options were considered (see Trade-offs): give native callables a
literal `RootMatcher`, or extract a shared base. v1 uses a dedicated
`RootMatcher`-shaped `NativeSignature` record, but it must **share the resolver
and the validation core** so no logic is duplicated:

- Parameter/return resolution: `resolve_type_value_to_id_with_index`
  (`matchers.nim:335`) — the same call the matcher uses.
- Runtime validation: `validate_type` (`runtime_types.nim:891`) — the same call
  `IkVar` and `process_args` use. There is no bespoke `validate_native_args`
  type logic; a thin `validate_native_args(sig, args, has_kw)` wrapper only
  walks `sig.params` and delegates each element to `validate_type`.
- Reflection: one adapter over `CallableParamDesc`, shared with user callables.

### Runtime Enforcement

Two call sites genuinely dispatch `NativeFn` callables and need the shared check:

1. `call_native_with_gene_args` (`src/gene/vm/exec.nim:66`) — generic call.
2. The `VkNativeFn` branch of method dispatch (`src/gene/vm/dispatch.nim:559`),
   which already validates arity (`dispatch.nim:560`) but not types.

Both resolve the callable's `NativeSignature`, and — when `vm.type_check` is on
and the signature `has_type_annotations` — run `validate_native_args` before
dispatch and `validate_type` on the returned `Value` after. When `vm.type_check`
is false, or the signature is all-`Any`, the cost is one bool test on top of the
existing arity check.

These are the **dynamic↔foreign boundary casts** of the gradual type model — the
one place a native signature is always a checked boundary, since the foreign side
is opaque. See [`gradual-typing.md`](gradual-typing.md) for the consistency
relation, cast-insertion/elision rule, and blame semantics these checks
implement.

> **Not an enforcement site:** `try_native_call` / `try_native_call1`
> (`src/gene/vm/native.nim:148-207`) is a *different* subsystem — it dispatches
> **JIT-compiled Gene user functions** through their machine-code entry point
> (`f.native_entry`, set in `prepare_native_ctx`, `native.nim:116`) and already
> reads argument types from the function's own `RootMatcher`
> (`native_arg_type_id` → `f.matcher.children[idx].type_id`, `native.nim:4-8`).
> It does not consume a `NativeFn` `NativeSignature`. The seam where JIT'd code
> marshals *into* a stdlib `NativeFn` is `bytecode_to_hir.nim:156,168` (see JIT
> section).

### Static Type Checking (Gradual)

Gene is **gradually typed and compiled just-in-time, per module**. The only
checker mode wired into the pipeline is non-strict — every `new_type_checker`
call passes `strict = false` (`src/gene/compiler/pipeline.nim:479,640,726`), with
the explicit contract *"non-strict mode allows unknown types (treated as Any)"*.
Checking is interleaved node-by-node with compilation (`type_check_node`,
`pipeline.nim:509-526`); a module is compiled when it is imported/loaded; and
`.gir` is a per-module *bytecode cache* (`save_gir`/`load_gir`,
`src/gene/vm/module.nim:1245-1277`), not a whole-program analysis. `gene compile`
compiles a single file the same gradual way (`src/commands/compile.nim:398`) and
does not load that file's imports — its "AOT" direction means *eagerly compile
function bodies and cache them*, not strict cross-module type resolution.

Two consequences set the contract for native typing:

- **Runtime enforcement is authoritative; compile-time checking is advisory.**
  Today a native *method* call mismatch is only a *warning* — `check_native_method_call`
  raises solely under `self.strict` (never set) and otherwise `self.warn`s
  (`type_checker.nim:2206-2218`); the runtime does not check at all. The core
  value of this proposal is the *runtime* check (see Runtime Enforcement). The
  compile-time path stays gradual and mirrors exactly what user callables get.
- **Not-yet-loaded types are never compile errors.** If a caller is compiled
  before the module defining a referenced type is loaded, the name degrades to
  `Any` and the authoritative check fires at runtime once the class is
  registered. There is no strict cross-module gate to fail (see
  [Cyclic Typing Dependencies](#cyclic-typing-dependencies)).

The work needed is therefore an alignment, not a new phase:

- **Migrate `check_native_method_call`** (`type_checker.nim:2164-2225`) off
  class-`Value`s. Today it reads `native_param_types`/`native_return_type` and
  maps class `Value`s to `TypeExpr` via `native_type_from_class_value`. It must
  instead read the method's `NativeSignature` and resolve each `TypeId` (and the
  return `TypeId`) against `sig.type_descriptors`. `class_matches_expected`
  (`type_checker.nim:2127`) is replaced by the standard `TypeId`-based
  compatibility the checker already uses for user methods. This keeps the gradual
  warnings working under the new representation — it is a checker rewrite, not a
  field rename, and is the most consequential migration in this proposal.
- **Extend to standalone fns and constructors.** The checker currently only
  handles native *method* callees (`type_checker.nim:2244`). Add the symmetric
  path for `VkNativeFn` standalone callees and for `new`/ctor calls, reading the
  same `NativeSignature` — still gradual, still advisory.

### Cyclic Typing Dependencies

A native signature may reference a type that is recursive (`class User` with a
`-> User` method), mutually recursive (`A` returns `B`, `B` returns `A`), or
defined in another module. The binding-site model handles these because it only
needs the type *name* to be writable, never the type to *exist* at bind time —
the same property user callables already rely on.

- **Class-reference cycles** resolve by name, lazily. An unknown name interns as
  `TdkNamed{name, module_path}` with a `TypeId` minted immediately
  (`matchers.nim:353-355`); `type_desc_to_rt` returns `RtNamed{name}` *without
  expanding the class* (`runtime_types.nim:192-193`); the name → `Class` binding
  happens at *use* time against the live namespace (`runtime_class_for_type`,
  `type_checker.nim:2137-2162`). A `NativeSignature` therefore stores
  `(module_path, name)` ids and the referenced class need not be registered when
  the signature is bound. Recursive and mutually-recursive references are flat,
  not nested, because named types are expansion leaves.
- **Structural cycles** (`(type A B)` / `(type B A)`, deeply nested applied/union
  graphs) are terminated by the existing depth guard — `depth > 64 → Any` in both
  `type_desc_to_rt` (`runtime_types.nim:185`) and the canonical key builder
  `type_desc_key` (`descriptors.nim:112`). They degrade to `Any` rather than loop.
- **Module import cycles** are a pre-existing, orthogonal concern. Gene already
  reports them (`raise_import_error` emits `cycle=A -> B -> C`,
  `src/gene/vm/module.nim:85-98`) and keeps a global cross-module type registry
  (`LoadedModuleTypeRegistry`, `module.nim:38`). A binding-site declaration is
  ordinary Gene in its module, so it introduces no module-graph edge that
  `(fn … -> ImportedType)` does not already introduce. Native typing neither
  worsens nor needs to newly solve import cycles.

To preserve this, the implementation must hold these invariants:

1. **Bind lazily.** Binding-site declaration and `$assign-type` intern names and
   store `TypeId`s; they must never resolve a name to a `Class` or expand the
   referenced type's structure at bind time. Eager resolution would create the
   ordering dependency a cycle breaks.
2. **Compare by canonical key, not deep expansion.** The conflict policy (see Open
   Questions) compares signatures via the depth-guarded `type_desc_key`
   (`descriptors.nim:111`), so even structural-match checks are cycle-safe.
3. **ABI derivation is cycle-safe by construction.** Mapping a `TypeId` to a
   `CallArgType` only asks "is it `Int`/`Float`?"; every named/user/recursive type
   collapses to `CatValue` without touching the class. Cycles never stall the JIT
   path.
4. **One diagnostic for unresolvable names.** A name that never resolves must
   produce the *same* error the user-callable path produces — not a divergent
   silent `Any`.

The bootstrap `types/*.gene` shims (surface 2) inherit this directly: run them all
in one lazy-binding phase and run-order is irrelevant, because resolution is
deferred. There is no remaining cross-module failure mode. Because checking is
gradual and runtime enforcement is authoritative (see
[Static Type Checking](#static-type-checking-gradual)), a name not yet resolvable
at compile time degrades to `Any` — a possible warning, never an error — and the
real check fires at runtime once the class is registered. The existing import
machinery (`module.nim` import resolution + `cycle=A -> B` reporting) guarantees
registration precedes any call, so even mutually-recursive modules are safe at
runtime.

### Reflection

Reflection accessors for native callables do not exist yet (only `"name"` is
registered on the relevant classes today, e.g. `src/gene/stdlib/classes.nim:525`).
This proposal adds `params` / `return_type` / `signature` accessors that read the
shared `CallableParamDesc` shape, so a user method and a native method expose the
same reflection surface and existing tooling (`/.signature`, doc generators,
`gene compile --format pretty`) sees both uniformly.

### Interaction with the JIT

`NativeSignature.abi` is derived by mapping each `CallableParamDesc.type_id` to a
`CallArgType` (`Int → CatInt64`, `Float → CatFloat64`, everything else →
`CatValue`; `src/gene/types/type_defs.nim:664-666`) and the return `TypeId` to a
`CallReturnType` (`Crt*`, `type_defs.nim:669-671`). Derivation happens when the
signature is bound:

- Nim-side built-in registration → derived synchronously, before any Gene code.
- Gene-side declaration / `$assign-type` → derived at bind time.

This **populates `native_fn_sigs` for the first time**. That table is read by HIR
lowering (`bytecode_to_hir.nim:156,168` via `lookup_native_sig`) but is currently
never written — `register_native_sig` (`trampoline.nim:12`) has no callers, so
typed native-call marshalling is presently dormant. Binding a `NativeSignature`
inserts the derived `abi` keyed by `pointer(fn)`. If a callable is re-typed by a
later `$assign-type`, the entry for `pointer(fn)` is invalidated (a single table
delete) so the next JIT lowering re-derives. This activates the existing
infrastructure rather than replacing absent call sites.

### Interaction with `serdes` / SQL Persistence

`NativeSignature` is *not* serialized — native callables are persisted as
symbolic references already. The `TypeId`s it embeds belong to the same module
type registry that the in-flight type-serialization design
(`docs/proposals/future/type-serialization.md`) and the SQL persistence work
(`openspec/changes/add-sql-value-persistence/`) rely on. Reusing
`CallableParamDesc + TypeId` gives cross-feature consistency for free.

## Compatibility and Migration

- The old `def_native_method(self, name, f, params, returns)` overload becomes a
  shim that builds a `NativeSignature` — but it can only carry built-in type
  references, since class-`Value` params for built-in classes map to built-in
  `TypeId`s and anything else was already unreachable from a Gene caller.
- **Breaking change (internal):** `Method.native_param_types: seq[(string, Value)]`
  and `native_return_type: Value` are removed. The one in-tree consumer,
  `check_native_method_call` (`type_checker.nim:2164-2225`) with helpers
  `native_type_from_class_value` (`2107`) and `class_matches_expected` (`2127`),
  is rewritten to read `NativeSignature` `TypeId`s. This is the load-bearing part
  of the migration and is scoped as a checker change, not a field rename.
- The default for an unannotated callable is "all params `Any`, return `Any`" —
  equivalent to today's runtime behaviour and preserved for back-compat.
- Stdlib migration is staged: phase 1 ports primitives-only signatures to the
  Nim-side shortcut (surface 3); phase 2 adds `src/gene/stdlib/types/*.gene`
  retrofits (surface 2) for signatures referencing user-visible classes
  (`Array[T]`, `Map[K,V]`, callback `Fn` types, etc.).
- A `--strict-native-types` opt-in (or `App.app.strict_native_types`) escalates
  remaining unannotated callables — first to a warning, then, opt-in, to a
  *runtime* error on call. This is a gradual-typing lint gate, not a new strict
  compile phase (none exists; see Static Type Checking).

## Open Questions

- **Bootstrap ordering for retrofits.** When do `src/gene/stdlib/types/*.gene`
  shims run? Candidate: at the end of `runtime.init`, after Nim registration and
  before user code, so a stdlib callable is never observed unannotated-then-
  annotated within one run. Lazy-on-first-use would start a callable as `Any` and
  later gain a signature — harmless for gradual *checking*, but it makes *runtime*
  enforcement non-deterministic across the boundary. Deterministic end-of-init
  binding is preferred. This is purely a runtime-ordering choice; there is no
  compile-time registry to populate (see Static Type Checking).
- **Generic native functions.** Should `(fn[T] ...)`-shaped signatures
  (`[x: T] -> T`) be supported? Straightforward for Gene-side declarations (the
  existing `type_vars` mechanism applies, `matchers.nim:348`) but `T` collapses to
  `CatValue` unconditionally in the JIT `abi` derivation.
- **Conflict policy.** If a callable already has a non-`Any` `NativeSignature`
  (e.g. set by the Nim shortcut, then re-set in Gene), is the second assignment an
  error, an override, or required to match structurally? Default proposal:
  match-or-error compared via the depth-guarded canonical key `type_desc_key`
  (`descriptors.nim:111`) so the check stays cycle-safe (see
  [Cyclic Typing Dependencies](#cyclic-typing-dependencies)), with `$assign-type!`
  as the explicit-override form.

## Future Work

- Auto-derive `NativeSignature` from Nim type signatures via a `{.nativeFn.}`
  macro, once enough call sites use the typed API to justify the macro surface.
- Effect annotations (`!throws`, `!async`) for native callables, in line with the
  `!` effects syntax already parsed for method declarations
  (`src/gene/compiler/functions.nim:296-299`, inside `compile_method_definition`).
- Overload resolution by signature for native methods that today simulate variants
  by inspecting `arg_count` (e.g. `String.sub`, `Array.slice`).
