# Gradual Typing: A Concrete Model for JIT and AOT

> Status: future roadmap design. Current implemented gradual-typing behavior is
> documented in [`docs/gradual-typing.md`](../../gradual-typing.md) and
> [`docs/type-system-mvp.md`](../../type-system-mvp.md). The AOT gate, explicit
> cast-insertion pass, structured blame model, higher-order proxies, and deep
> collection boundary work described here are not complete current behavior.

## Summary

Gene is a dynamically-typed language with optional type annotations on variables,
functions, methods, constructors, native callables, and FFI bindings. This
document specifies the **gradual type system** those annotations participate in,
and how it behaves under both compilation modes:

- **JIT** — the current default: compile-on-import, open world, permissive
  (gradual warnings), authoritative runtime enforcement.
- **AOT** — a whole-module-graph closed-world build: stricter (consistency
  violations become build errors), faster (more runtime checks elided), and it
  emits typed `.gir` artifacts. AOT is the release gate; JIT is for dev/REPL.

Two decisions anchor the design:

1. **Sound gradual typing with boundary checks.** Types are enforced at runtime
   where typed code meets dynamic/untyped/foreign values; typed↔typed boundaries
   proven consistent at compile time are elided; failures carry **blame**. Typed
   regions cannot "go wrong" internally.
2. **AOT is a stricter, faster gate over identical runtime semantics.** Any
   program AOT accepts runs observably identically under JIT. AOT only turns into
   a *build error* what JIT would have hit as a *runtime cast failure* (or proves
   can never fail). It never changes the result of an accepted program.

Much of this already exists in spirit: the checker's `unify` short-circuits on
`Any` (gradual consistency, `src/gene/type_checker.nim:432-437`); `IkVar`,
`process_args`, and matcher return-validation enforce at runtime
(`src/gene/vm/exec.nim:785-788`, `src/gene/vm/args.nim:104`,
`src/gene/types/runtime_types.nim:537`); and a type-driven native compile tier
already optimizes fully-typed boundaries (`NctFullyTyped`,
`src/gene/vm/core_helpers.nim:200-224`). This proposal makes that intentional and
complete: a defined consistency relation, an explicit cast-insertion pass, a
blame model, and the JIT/AOT split with a stated cross-mode guarantee.

## Non-Goals

- No change to the NaN-boxed value representation or the dynamic core. Untyped
  Gene stays exactly as it is.
- No mandatory annotations. Unannotated code is `Any` end to end and runs as it
  does today.
- No flow-sensitive occurrence typing in v1 (narrowing `x: Int | Nil` by an
  `(if x ...)` test); listed as Future Work.
- No type inference beyond local result types already computed by the checker.

## 1. Type Model

### 1.1 Type universe

Types are the existing `TypeDesc` kinds, interned as `TypeId` against a module
registry (`src/gene/types/descriptors.nim`):

| Surface | `TypeDesc` kind | Notes |
|---|---|---|
| `Any` (the dynamic type) | `TdkAny` | consistent with everything |
| `Int Float String Bool Nil Void Symbol Char` | `TdkNamed` (built-in ids) | `lookup_builtin_type`, `descriptors.nim:39-54` |
| `Array Map` | `TdkNamed` / `TdkApplied` | `(Array Int)` is `TdkApplied` |
| user class / alias name | `TdkNamed{name, module_path}` | resolved by name, lazily |
| `(A \| B)` | `TdkUnion` | |
| `(Fn [A] -> B ! [eff])` | `TdkFn` | higher-order; see §3.1 |
| type variable `T` | `TdkVar` | generics; see §3.2 |

`Any` is the **dynamic type**: the explicit "this value's type is unknown until
runtime" marker. Unannotated slots are `Any`.

### 1.2 Consistency (`~`), not subtyping

The static check uses the **gradual consistency** relation, already implemented
by `unify` (`type_checker.nim:432`):

```
Any ~ T              for all T        (unify short-circuits, type_checker.nim:437)
T   ~ Any            for all T
T   ~ T
(A|B) ~ C            iff A ~ C or B ~ C
(Array A) ~ (Array B) iff A ~ B
(Fn [A] -> R) ~ (Fn [A'] -> R') iff A' ~ A (contravariant) and R ~ R'
Named(n,m) ~ Named(n,m)              (and nominal subclassing: see §1.3)
```

Consistency is **not transitive** (`Int ~ Any` and `Any ~ String`, but
`Int ≁ String`) — this is the defining property of gradual typing and the reason
`Any` is a deliberate opt-out of static guarantees rather than a "top" type.

### 1.3 Nominal subtyping inside consistency

Where both sides are concrete named classes, the relation also admits nominal
subclassing (`is_a`, `src/gene/types/classes.nim:212`): `Sub ~ Super` holds when
`Sub` derives from `Super`. This is the existing `class_matches_expected`
behaviour (`type_checker.nim:2127`), folded into `~`.

### 1.4 Soundness statement

> In a region whose static types contain no `Any`, no type error can occur at
> runtime. Every runtime type error originates at a **boundary** where a value
> whose static type is (transitively) `Any` enters a context demanding a concrete
> type — and the error names that boundary via blame (§2.4).

## 2. Boundaries and Casts

### 2.1 What is a boundary

A **boundary** is any point where a value of static type `S` flows into a
position expecting type `T`, where `S ~ T` but the flow is not *statically
proven safe* (i.e. `S` is not already known to satisfy `T`). The canonical case
is `S = Any`, `T = Int`. The compiler inserts a **cast** `⟨T⟩ᵖ e` at each such
point, where `p` is a blame label (§2.4).

The dual direction — a concrete value flowing *out* into an `Any` context
(`Int → Any`) — needs **no check** (every value is a valid `Any`), but the
boundary is still recorded so blame can point back to it.

### 2.2 Cast-insertion pass

A new compiler pass runs after type checking, consuming the static type the
checker computed for every expression, and emitting a cast **only where the
boundary is not statically proven**:

```
insert_cast(expr, expected T):
  S = static_type(expr)
  if S ⊑ T  (statically proven: S is T or a subclass, no Any involved):
      emit expr unchanged          # ELIDED
  elif S ~ T:
      emit ⟨T⟩ᵖ expr               # runtime cast with blame label p
  else:
      static error (JIT: warning; AOT: build error)
```

`⊑` is "statically proven to satisfy" (concrete subtype, no `Any` on the path);
`~` is consistency. The elision rule is what makes fully-typed code free.

### 2.3 Where casts are inserted

| Boundary | Existing mechanism | Change |
|---|---|---|
| `(var x: T e)` | `IkVar` arg1=TypeId (`exec.nim:785-788`) | emit only when `S ⋢ T`; attach blame label |
| call arg → param | `process_args` matcher type ids (`args.nim:104`) | elide proven args; cast the rest; blame = caller |
| return value → declared return | matcher return validation (`runtime_types.nim:537`) | blame = callee |
| `self` → method's class | `process_args` (self is first param) | nominal check |
| native / FFI arg & return | (this proposal's siblings) | the dynamic↔foreign boundary; always checked |
| member / field write typed `T` | — (new) | cast on write |
| element read from `(Array T)` | — (new, see §3.3) | transient element check |

Casts reuse the **one** runtime validator, `validate_type`
(`runtime_types.nim:891`) — the same call `IkVar` and `process_args` already make.
There is no second checking path.

### 2.4 Blame

Every inserted cast carries a **blame label** `p`: a `(source-span, party)` pair
stored in the compilation unit and referenced by index from the check. `party`
distinguishes the two sides of a contract:

- **positive** — the expression being cast (e.g. the callee returning a wrong
  value): "the value provider violated the type."
- **negative** — the context imposing the type (e.g. a caller passing a bad
  argument): "the consumer demanded a type the value can't meet."

On failure, the runtime raises a `TypeError` naming the responsible span and
party, not the internals of typed code. Example:

```gene
(fn add [a: Int b: Int] -> Int (+ a b))
(add (read-untyped) 2)
;=> TypeError: argument 'a' of add expected Int, got String
;   blame: <caller>:NN  (negative — call site provided the value)
```

This is what "typed regions cannot go wrong" means operationally: the only
failures are cast failures, and each is attributed to a specific boundary.

## 3. Hard Cases Under Soundness

Choosing sound gradual typing commits us to the cases where soundness is
expensive. v1 takes explicit, documented positions.

### 3.1 Higher-order boundaries (`Fn` types)

A value crossing into a slot typed `(Fn [Int] -> String)` cannot be checked by
inspecting it once — its type only manifests when called. Sound gradual typing
**wraps** it in a checking proxy that casts arguments (negative blame) and
results (positive blame) on each call:

```
⟨(Fn [Int]->String)⟩ᵖ g   ⟹   (fn [x] (⟨String⟩ᵖ (g (⟨Int⟩p̄ x))))
```

- **Cost & identity:** the proxy is a new closure (`wrapped ≠ original` under
  identity comparison). Acceptable because functions are rarely identity-compared.
- **Elision:** when `g`'s static type is already `(Fn [Int] -> String)` (no
  `Any`), no wrapper — the common fully-typed case is free.
- **v1 default:** wrap at dynamic `Fn` boundaries for soundness. A documented
  `^shallow` opt-out (check only callability+arity, defer to inner casts) is
  the explicit escape hatch for hot paths that accept the weaker guarantee.

### 3.2 Generics / type variables

`(fn f:T [x: T] -> T ...)` type-checks structurally (existing `type_vars`,
`matchers.nim:348`). At a dynamic boundary `T` behaves as `Any` (no runtime
identity to check), so instantiations collapse to `Any` for cast purposes.
Generic native signatures are deferred and rejected at native binding sites; use
concrete types or `Any` at native boundaries for now. AOT may **monomorphize**
hot fully-typed instantiations (Future Work); JIT does not.

### 3.3 Mutable collections

A deep `⟨(Array Int)⟩` cast is O(n) and, because arrays are mutable and shared,
a checking wrapper would break aliasing. v1 uses a **transient** compromise
*within* the otherwise boundary-based model:

- At the boundary: **shallow** check (the value is an `Array`/`Map`). O(1).
- At each typed **element access** (`arr[i]` where `arr: (Array Int)`): insert an
  element cast `⟨Int⟩`. Cost is per-use, only in typed code, elided when the
  source is statically `(Array Int)`.

This is a deliberate, documented soundness relaxation for mutable containers
(the same choice Reticulated Python's transient semantics makes), chosen over
deep-copy-check or identity-breaking wrappers. Immutable/value collections may
take the deep-check path in a later revision.

### 3.4 Nil

`Nil` is its own type. A non-nilable slot `T` does **not** admit `nil`; nilable
slots are `(T | Nil)`. The existing `strict_nil` flag (`type_defs.nim:1234`)
selects the default for legacy code: `strict_nil = true` enforces the sound rule;
`false` admits `nil` into any slot for migration. Sound mode is `strict_nil`.
A `T?` reader sugar for `(T | Nil)` is proposed as Future Work.

## 4. JIT Mode (open world)

Unchanged in structure from today, made precise:

- **Compile-on-import**, per module, streaming (`parse_and_compile`,
  `pipeline.nim:452`). Type checking is interleaved node-by-node
  (`type_check_node`, `pipeline.nim:509-526`).
- **Open world:** a referenced type from a not-yet-loaded module is unresolved →
  treated as `Any` → consistent with everything. The checker is **permissive**:
  consistency violations and unresolved names are **warnings**, not errors
  (`new_type_checker(strict = false …)`, `pipeline.nim:479`).
- **Conservative cast insertion:** boundaries the open world can't prove safe
  (cross-module, unresolved, `Any`) get runtime casts. Within-module typed↔typed
  proven boundaries are elided.
- **Authoritative runtime enforcement:** casts fire at runtime; by then imports
  are resolved in dependency order (`module.nim`), so cross-module references
  are concrete. The native tier (`NctFullyTyped`) machine-compiles fully-typed
  hot paths.
- **Escape hatch:** `--no-type-check` clears `vm.type_check`
  (`type_defs.nim:1233`), removing all casts. This **forfeits soundness** and is
  a profiling/debug tool, documented as such.

## 5. AOT Mode (closed world)

A new whole-module-graph build (`gene build`, or `gene compile --release`;
today's `gene compile` is per-file and stays as the bytecode-cache primitive):

1. **Load the whole graph.** Resolve every `import` transitively into one closed
   world with a complete type registry (the global `LoadedModuleTypeRegistry`,
   `module.nim:38`, populated fully rather than incrementally). Import cycles are
   reported as today (`raise_import_error`, `module.nim:85-98`).
2. **Strict checking — the gate.** Run the checker in **strict** mode: every
   consistency violation reachable in typed code, and every unresolved type name
   (a real error in a closed world), is a **build error**. This is the
   `strict = true` path of the existing checker (`new_type_checker`,
   `type_checker.nim:258`), never reached today.
3. **Closed-world cast elision.** With whole-graph type info, many boundaries
   that JIT must guard are now provably safe and their casts are **removed** —
   strictly more elision than JIT. Casts remain only at genuine residual `Any`
   boundaries (e.g. a value read from `eval`, deserialization, or FFI).
4. **Typed GIR.** Emit `.gir` carrying bytecode + resolved `type_descriptors` +
   signatures + an **elision record** (which boundaries were proven and dropped).
   GIR becomes a *typed artifact*, extending the current bytecode-only cache
   (`save_gir`/`load_gir`, `module.nim:1245-1277`).

AOT does **not** re-derive different semantics: it computes a *superset* of the
casts JIT would elide, and a *subset* of the programs JIT would run (it rejects
the statically-broken ones). See §6.

## 6. The Cross-Mode Guarantee

This is the invariant that makes two modes safe:

> **(Acceptance)** If AOT accepts program `P`, then JIT runs `P`.
> AOT-accepted ⊆ JIT-runnable.
>
> **(Equivalence)** For any `P` AOT accepts, AOT-compiled `P` and JIT-run `P` are
> **observably equivalent**: same result, same effects, same exceptions — except
> that a type violation AOT reports at build time would, under JIT, have either
> surfaced as a runtime cast failure on that path or never been reached.
>
> **(Optimization safety)** Every cast AOT elides is one whose success JIT could
> have proven too; elision removes only checks that cannot fail. Therefore
> elision never changes observable behaviour, only performance.

Consequences:
- A green JIT run is **not** a guarantee of AOT acceptance (JIT defers to runtime;
  AOT demands static consistency). This is intended: AOT is the stricter gate.
- An AOT build is a guarantee the program is type-consistent in all reachable
  typed regions; remaining runtime casts are exactly the residual dynamic
  boundaries the source chose to keep.

## 7. Type Registry

- **JIT:** the registry is built **incrementally** as modules load. Names resolve
  lazily by `(module_path, name)`; unresolved → `Any`. Cycle-safe by deferral
  (named types are expansion leaves; depth-guarded structural expansion,
  `runtime_types.nim:185`).
- **AOT:** the registry is built **completely** before checking. Every name must
  resolve; an unresolved name is a build error. This is the only place the two
  modes differ in *resolution*, and it is precisely what enables strict checking.

Both modes share one representation (`TypeId`/`TypeDesc`), so a typed GIR produced
by AOT loads under JIT and vice versa.

## 8. Performance

The "gradual typing tax" is concentrated where the design puts it — at dynamic
boundaries — and removed everywhere else:

- **Fully-typed code: zero overhead.** Typed↔typed proven boundaries are elided
  (§2.2); the native tier machine-compiles them (`NctFullyTyped`).
- **Dynamic boundaries: one `validate_type`** per crossing (shallow for
  collections, proxy for `Fn`). Unavoidable under soundness; this is the point.
- **AOT: fewer boundaries** than JIT via closed-world elision.
- **Opt-out:** `--no-type-check` (soundness off) for measurement.

The cost model is legible: a developer can see exactly which boundaries cost
checks (the cast-insertion record / `gene compile --format pretty`), and remove
cost by typing both sides of a boundary.

## 9. VM / Compiler Changes

- **Cast representation.** Reuse `validate_type` as the check core. Add a
  blame-label table to the `CompilationUnit` and let the existing typed sites
  (`IkVar`, `process_args` entries, return validation, native checks) carry a
  blame-label index. A small number of new boundaries (member write, element
  access, `Fn` proxy) get explicit check emission from the cast pass.
- **Cast-insertion pass.** New pass between type checking and final codegen,
  consuming static types, emitting checks per §2.2. In JIT it runs inside
  `parse_and_compile`; in AOT it runs over the whole graph with elision.
- **Strict mode wiring.** Expose the checker's existing `strict` flag through the
  AOT entry point (the flag exists, `type_checker.nim:258`; only the non-strict
  path is currently reachable).
- **Typed GIR.** Extend the GIR format with `type_descriptors` (already partly
  serialized for `ai-metadata`, `src/commands/compile.nim:219-237`), signatures,
  and the elision record.

## 10. Configuration & Migration

- Today's behaviour (gradual warnings + `IkVar`/`process_args` enforcement) is a
  **subset** of JIT mode here; this proposal adds blame, the cast pass, the
  collection/`Fn` boundary rules, AOT strict mode, and typed GIR.
- Defaults: JIT permissive (dev/REPL), AOT strict (release). `strict_nil` on in
  sound mode.
- `--no-type-check` retained as the soundness-off escape hatch.
- Native callables and FFI are typed via their sibling implemented design records
  ([`type-annotations.md`](../implemented/type-annotations.md),
  [`dynamic-library-binding.md`](../implemented/dynamic-library-binding.md)); this document
  defines the **boundary semantics** that enforce those signatures (the
  dynamic↔foreign boundary is always a checked cast).

## 11. Resolved Decisions

- **Higher-order blame default.** Sound by default. Dynamic `Fn` boundaries wrap
  callables in a proxy that checks arguments and returns on every call. `^shallow`
  is the explicit opt-out for hot paths that accept weaker result soundness.
- **Collection soundness depth.** The transient element-check model (§3.3) is the
  design for the foreseeable future. Deep boundary checks for immutable/value
  collections are deferred.
- **AOT closed-world vs `eval`/dynamic load.** AOT treats values from `eval` and
  dynamically-loaded modules as residual `Any`. Checked boundaries remain, and
  the closed-world guarantee covers only statically-reachable code.
- **Incremental AOT.** Yes, typed GIR plus per-module elision records should
  support incremental AOT. The first design can remain whole-graph; incremental
  invalidation is a follow-on design target.

## 12. Future Work

- Occurrence typing / flow narrowing (`(if x ...)` narrows `x: T | Nil` to `T`).
- `T?` sugar for `(T | Nil)`.
- Monomorphization of hot generic instantiations in AOT (§3.2).
- Confined/owned immutable collections enabling deep boundary checks without
  aliasing hazards.
- Effect checking (`! [throws async]`) promoted from annotation to enforced
  boundary, reusing the same cast/blame machinery.
