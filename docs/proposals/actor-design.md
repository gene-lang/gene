# Actor-Based Concurrency Model for Gene

Status: design approved. Ready for phased implementation.

## Motivation

The current concurrency model composes poorly. A user writing concurrent Gene
code today must keep track of: OS threads, a thread pool limit
(`GENE_MAX_THREADS`), message passing with string-round-trip serialization
(`serialize_literal`), the literal-only payload rule (no instances, no
closures, no handles), plus three documented-but-unimplemented extensions —
the `g_concurrent` flag (`docs/global-access.md:23-28`), per-method
`^thread-safe` annotations (`docs/global-access.md:46, 66`), a separate global
map type with per-key locks (`docs/global-access.md:32-35`), and a
package-level `global-access` manifest (`docs/global-access.md:48-60`). On top
of that, `docs/proposals/future/actor_support.md` layers an actor API that
inherits all of the above. This is **eight distinct concurrency concepts** for
a model that most programs would prefer to be: "spawn some work, send it a
message, get a reply."

Evidence the current scheme is already straining in practice:
`src/genex/llm.nim:13-14` hand-rolls its own `{.global.}: Lock` pair because
neither the thread API nor the proposed model serves the single-process-global
llama.cpp singleton.

This document describes a coherent replacement that targets three explicit
goals: **fast**, **easy to understand**, **no burden to the user.**

## Non-Goals

- Erlang-level fault tolerance (per-process heaps, supervision trees, hot code
  loading). Out of scope; considered but rejected for cost in the separate
  analysis (see "References" below).
- Compile-time effect tracking / capabilities. Gene has no type system deep
  enough to encode send-safety statically. Enforcement is runtime-physical.
- Distributed actors across machines. Single-process only.
- Preemptive scheduling. Cooperative-at-message-boundary is sufficient and
  matches the actor-handler model.

## The Model

Four rules, in priority order. Every other property follows from these.

### Rule 1: Actors are the only concurrency primitive

`(spawn handler)` produces an actor handle. An actor has a private state, a
mailbox, and a handler. No raw `Thread` API in user code. The runtime's
internal thread pool is a hidden implementation detail; the scheduler maps M
actors onto N OS worker threads (M:N, many-to-few).

Public API mirrors `docs/proposals/future/actor_support.md`:

- `(spawn ^state init handler)` → actor handle
- `(actor .send msg)` — fire-and-forget
- `(actor .send_expect_reply msg)` → Future
- `(actor .stop)` / `ctx/.stop` — stop after current message

### Rule 2: Data is mutable by default; `freeze` is opt-in

Gene keeps its character. Literal syntax `{...}`, `[...]`, gene forms, and
`new`-constructed instances produce **mutable** values, exactly as today.
Assignment and augmented-assignment (`=`, `+=`, `.put`, `.add`, `.set`,
`.delete`, `.clear`, `.merge`, `.pop`, `.push`) stay the idiomatic path for
data manipulation. No stdlib rename. No language-wide breaking change.

`(freeze v)` is an opt-in operation that produces a deep-frozen, shared-heap
snapshot of `v`. The snapshot is safe to share by pointer across actors.
Users call `freeze` when they know a value is (a) shared across actors and
(b) hot enough that the clone cost in Rule 3 matters.

The existing shallow `frozen` bit (`src/gene/types/core/value_ops.nim:145-176`)
is extended to a deep `deep_frozen` bit: a container is `deep_frozen` iff it
is frozen AND all reachable substructure is `deep_frozen`. Computed once at
`freeze` time; not walked on every check.

Mutable values stay **actor-local**: the runtime guarantees (via Rule 3) that
no mutable storage is ever observable from more than one actor.

### Rule 3: Cross-actor send is total on ordinary data; cost is tiered

`.send` succeeds unconditionally for **ordinary Gene data** — primitives,
arrays, maps, genes, bytes, strings, instances of pure-data classes, and
freezable closures. It routes on the payload's deep-frozen status:

| Payload | Transfer | Cost |
|---|---|---|
| Primitive (NaN-boxed int/float/bool/nil/char) | by value | free |
| Deep-frozen heap value | pointer + atomic refcount bump | O(1) |
| Mutable heap value | **deep-clone into receiver's heap** | O(payload) |

`.send` rejects (with a clear error naming the blocking kind)
**capability values** — raw `Pointer`, `Native`, `CFunc`, thread / actor
handles, futures, file descriptors, sockets, port handles, and any
user-registered native resource. Capabilities are actor-local by
construction and must be exposed across actors through a port actor
(Rule 4).

Structural sharing is automatic: when cloning a mutable value, any
deep-frozen subgraph is pointer-shared (refcount-bumped) rather than
re-cloned. Users who freeze their large read-only data (config, lookup
tables, model weights) pay the clone cost only on the mutable spine around
it. Example:

```gene
(def config (freeze {...large map...}))   # one-time deep-freeze cost
(def req    {:cfg config :id 42})          # mutable outer, frozen inner
(worker .send req)                         # clones 2-entry outer; pointer-shares config
```

This replaces the `serialize_literal` round-trip at
`src/gene/vm/thread_native.nim:258-317`. The clone path is O(payload) with a
low constant (field-copy, no text formatting, no parser) — ~5-20× faster
than the current serialize round-trip even before the freeze fast path
applies. Serialization stays in `serdes.nim` for persistence and file I/O.

**Race-freedom note**: sender and receiver hold distinct mutable storage
after a clone. No raw pointer to mutable state ever crosses a boundary;
frozen values, which do cross by pointer, cannot be mutated by anyone (I3).

### Rule 4: Shared resources are port actors

Process-global resources — database connection pools, LLM models, HTTP
sockets, native libraries — live behind **port actors**. A port actor is an
actor whose handler is implemented in native code (Nim). The VM spawns one
port actor per registered extension at startup. User code interacts with
extensions only by sending messages to ports.

This replaces the ad-hoc global-lock pattern in `src/genex/llm.nim:13-14,
780-868`. The lock becomes the mailbox; the contract is the same
(serialized access) but uniform across the system.

Consequences:

- No "global map" type. Shared read-only config is a frozen value passed at
  startup. Shared mutable state is an actor.
- No `^thread-safe` method annotation. A method runs inside one actor at a
  time (by I1), so intra-actor calls are single-threaded by construction.
- No `g_concurrent` flag. No single-threaded special case.
- No package-level `global-access` manifest.
- No mutability flip. Gene's surface syntax and stdlib API stay as-is.



## The Six Invariants

Race freedom for actors-on-native-threads is guaranteed by six physical
invariants. Each is runtime-enforced, not developer-promised.

### I1. One worker per actor at a time

The scheduler holds each actor in a state machine `{Ready, Running, Waiting}`.
Dispatch is an atomic CAS `Ready → Running`. A `Running` actor is not
dispatchable. On handler return: `Running → Ready` (mailbox non-empty) or
`Running → Waiting` (mailbox empty).

- **Enforcement**: one atomic CAS per dispatch.
- **Failure mode**: same actor runs on two workers → private-state race.
- **Test**: stress test attempts double-dispatch; CAS must fail.

### I2. No raw pointer to mutable storage crosses a boundary

`.send` inspects the payload's `deep_frozen` bit.
- If set, the pointer is enqueued on the receiver's mailbox and the refcount
  is atomically bumped.
- If not set, the runtime performs a deep-clone into shared-heap storage
  owned by the receiver; the sender's original is untouched; frozen
  subgraphs are pointer-shared, not re-cloned.

Either way, the invariant holds: sender and receiver never share mutable
storage. Mutable storage is only ever read and written by its owning actor.

- **Enforcement**: bit-test + clone routine at `.send`.
- **Failure mode**: a bug in the clone routine leaks a pointer to
  caller-owned mutable storage → concurrent writes. Contained by a single
  code path (`send`), unit-testable.
- **Sharp edge**: cycles in the mutable graph. The clone routine uses a
  visited-set to handle cycles without infinite recursion.

### I3. Frozen values are genuinely immutable

Once `deep_frozen` is set, the value's contents cannot be mutated via any
path. Every mutator (`.put`, `.add`, `.set`, `.delete`, field-set, `[]=`)
checks the bit and raises on a frozen target.

- **Enforcement**: branch in every mutator. Gene already does this for the
  shallow `frozen` bit (`src/gene/types/core/value_ops.nim:149, 166, 174`);
  extension to `deep_frozen` is structural, not algorithmic.
- **Failure mode**: backdoor mutator corrupts shared state.

### I4. Refcount is atomic for shared values, plain for owned values

Only deep-frozen values ever cross a boundary by pointer (by I2). Frozen
values are allocated on the shared heap with `allocShared0` at `freeze`
time; their `shared` flag is set on first send. `retain`/`release` branches
on `shared`: shared → `atomicInc`/`atomicDec` with release-acquire ordering;
owned → plain `inc`/`dec` (current behavior at
`src/gene/types/core/value_ops.nim:57-134`).

- **Single-threaded cost**: zero additional atomic ops. Most values never
  get sent and stay `shared=false`.
- **Mutable values**: always live on the thread-local heap of their owning
  actor. Cloned into the receiver's thread-local heap on send; the clone is
  the receiver's to mutate.

### I5. Bootstrap and code images are read-only after publication

Narrow, enforceable version of this invariant. Once initialization
completes, the only shared pointers from which all workers may read are
these five:

- `CompilationUnit.instructions` — the bytecode array itself.
- Published JIT code pages. `Function.native_entry` is publishable only
  via a release store on `native_ready`; readers use an acquire load
  (`src/gene/vm/native.nim:98-110`).
- Bootstrap type registry and primitive opcode tables.
- `App.app.gene_ns` / `App.app.genex_ns` **as they existed at end of
  init** — treated as a frozen snapshot. Entries added at user runtime
  are not in this snapshot and are not I5-shared.
- Interned string constants in `CompilationUnit` (only valid once
  strings become immutable; see P0.4).

Everything that mutates at user-program runtime is actor-local or
synchronized through a specific protocol:

- `Function.body_compiled` / `Block.body_compiled` — lazy publication;
  gated by CAS or moved to compile time (P0.2). Sites:
  `src/gene/vm/exec.nim:467, 503, 2146, 2274, 2298, 3395, 4705, 4767,
  4808`.
- `CompilationUnit.inline_caches` — per-worker storage, or atomic slot
  updates; pre-existing hazard at `src/gene/vm/exec.nim:4-12`.
- Classes and namespaces created at runtime via `class` / `ns` forms —
  actor-local unless explicitly published through the port protocol.
  `Namespace.version` / `Class.version` bumps at
  `src/gene/types/type_defs.nim:487, 502` are actor-local writes on
  actor-local objects.
- Instance fields, method caches, per-frame state — actor-local by
  construction.

- **Enforcement**: a `bootstrap_frozen: bool` flag set at end of
  `init_app_and_vm` (`src/gene/types/helpers.nim`) guards the five
  shared targets. Mutators that attempt to extend the frozen snapshot
  after the flag flips assert or no-op; zero cost in release builds.
- **What changed from the previous draft.** The earlier wording
  ("runtime infrastructure is read-only after init") implied that lazy
  `body_compiled`, JIT publication, and runtime-defined classes /
  namespaces were immutable. The source shows they demonstrably are
  not. This version draws the line at the snapshot boundary instead of
  the "infrastructure" label.

### I6. Native code participates via the port protocol

Extensions hold process-global state and thread-unsafe libraries. They do not
receive raw `Value` pointers from arbitrary worker threads. Each extension
registers a port-actor handler; the VM spawns one port actor per extension
at startup. User code calling an extension method actually sends a message
to the port and awaits the reply.

- **Enforcement**: extension call-dispatch routes through the port mailbox.
- **Reference case**: `src/genex/llm.nim` — current `global_llm_op_lock`
  becomes the port's mailbox discipline.
- **Contract for extension authors**: `handle_message` is called from exactly
  one OS thread (the port's worker). You may hold thread-unsafe state. You
  may not retain `Value` pointers across message calls.

### Memory ordering

On weak-memory hardware (ARM, POWER), send is a release-acquire
synchronization point. The mailbox enqueue/dequeue at
`src/gene/vm/thread_native.nim:35-73` already uses `Lock + Cond`, which
provides full fences. All writes before send happen-before all reads after
receive. No additional fences are required in value construction or in user
code.


## Required Architectural Changes

Ordered from structural prerequisites to surface-level API changes.

### A. Data model: deep-frozen bit and user-facing `freeze`

**Change**: add `deep_frozen: bool` to every heap value kind that currently
carries the shallow `frozen` bit (Array, Map, Gene) and to the kinds that
don't (Instance, Reference-backed HashMap/Set, Class, BoundMethod, closures).
Literal construction is unchanged: mutable by default, `frozen=false`,
`deep_frozen=false`.

**Files affected**:
- `src/gene/types/type_defs.nim:347-353` (Gene), the corresponding ArrayObj /
  MapObj / InstanceObj definitions, and the `Reference` union for
  HashMap/Set/Closure.
- `src/gene/types/core/value_ops.nim:145-176` — add deep variants of
  `array_is_frozen`, `map_is_frozen`, `gene_is_frozen`; the existing shallow
  `ensure_mutable_*` checks continue to guard `.put`/`.add`/`[]=` paths.
- `src/gene/types/core/constructors.nim` — no change to default construction.
  A new `freeze` routine walks `v` once, allocates a deep-frozen graph in
  the shared heap, sets `deep_frozen` and `shared`. Idempotent on
  already-deep-frozen values.

**User API**: `(freeze v)` is a stdlib function, not syntax. There is **no
mutable-literal marker**; literals are already mutable. Existing Gene
programs compile and run unchanged.

**Class-level opt-in** (deferred decision, Open Question #1): a
`^frozen-default` class annotation could make instances of a class
deep-frozen at construction time. Useful for value types (Point, Vector).
Not required for MVP.

### B. Heap allocation: shared-heap path and atomic refcount

**Change**: introduce a second allocation path for values produced by
`freeze`.

**Files affected**:
- `src/gene/types/core/constructors.nim:64, 134, 203, 248, 434` — current
  `alloc0` (thread-local) paths unchanged for default construction. Add
  shared-heap variants used by `freeze` and by the clone routine in D.
- `src/gene/types/core/value_ops.nim:57-134` — `retain`/`release` branch on
  `shared` flag: atomic for shared, plain for owned.

**Allocation strategy**:
- Mutable values → thread-local (`alloc0`). Never escape by pointer.
- Deep-frozen values (produced by `freeze`) → shared heap (`allocShared0`).
  Any frozen subgraph embedded in a mutable value is already shared-heap
  (must be — it was produced by a prior `freeze`), so clone only walks the
  mutable spine.

**No rehome cost**: a value becomes shared only by going through `freeze`,
which allocates in the shared heap from the start. The runtime never
re-homes an existing value between heaps.

### C. Scheduler: actor state machine on top of existing thread pool

**Change**: repurpose the existing thread pool
(`src/gene/vm/thread_native.nim:107-178`) as a worker pool; add an actor
registry on top.

**New data structures**:
- `Actor` record: `{ id, state: Atomic[ActorState], mailbox: Channel,
  private_state: Value, handler: Value, pinned_worker: int }`.
- Per-worker ready-queue (local queue of ready actors).
- Global steal-victim list for work-stealing.

**Scheduler loop** (per worker):
1. Pop actor from local ready-queue; if empty, steal from another worker.
2. CAS actor state `Ready → Running`. If CAS fails, actor is running
   elsewhere or already taken; skip.
3. Pop one message from mailbox.
4. Invoke handler with `(ctx, msg, state)`; handler return is next state.
5. CAS actor state `Running → Ready` (mailbox non-empty) or `Running →
   Waiting` (empty). Push to ready-queue if Ready.

**Pinning**: in the MVP, pin each actor to the worker it was spawned on
(already recommended in `docs/proposals/future/actor_support.md:189-196`).
Work-stealing is a later phase.

### D. Send path: tiered clone-or-pointer-pass

**Change**: rewrite `thread_send_internal`
(`src/gene/vm/thread_native.nim:258-317`) as a tiered dispatch:

```
send(dst, v):
  if is_primitive(v):           enqueue_value(dst, v)            # by value
  elif v.deep_frozen:            atomic_retain(v); enqueue(dst, v)# pointer
  else:                          enqueue(dst, deep_clone(v))      # clone
```

**`deep_clone(v)`** walks the mutable spine of `v`:
- Allocates new shared-heap cells for the spine of the payload (the receiver
  takes ownership; see I4 — a cloned mutable payload must be allocated in
  shared-heap so the receiver's thread can free it).
- For each frozen subgraph encountered, pointer-shares it (atomic refcount
  bump on the subgraph root) instead of re-cloning.
- Uses a **memo table** `Table[ptr Ref, ptr Ref]` mapping each visited
  source pointer to its freshly allocated destination pointer. This is
  required for correctness, not just cycle handling: if two fields of a
  parent both point to the same mutable child, the clone must preserve
  that aliasing — both destination fields point to the *same* cloned
  child, not to two independent copies. A plain visited-set would either
  skip the second visit (leaking a source-actor pointer into the receiver
  — I2 violation) or re-clone (silently splitting aliased objects).
  Cycles fall out of the same mechanism: on re-entry the memo returns
  the in-progress destination pointer.
- Rejects values that cannot be meaningfully cloned, matching the Rule 3
  capability list: raw `Pointer`, `Native`, `CFunc`, thread / actor
  handles, futures, OS resource handles (file descriptors, sockets),
  port handles. These must be wrapped in a port actor.

**Delete** (or restrict to persistence): `serialize_literal` /
`deserialize_literal` for cross-thread use
(`src/gene/serdes.nim:776-785`). The persistence variant stays for
`(serialize …)` and file I/O.

**Wins**:
- Primitive sends: O(1), unchanged.
- Frozen sends: O(1) regardless of payload size (new fast path).
- Mutable sends: O(payload) × clone-constant — ~5-20× faster than the
  current serialize round-trip because there is no text formatting or
  parser.
- Automatic structural sharing: mutable-outer-with-frozen-inner payloads
  pay only for the mutable spine.

**Subtlety — clone heap ownership**: a cloned mutable value must be readable
and writable by the receiver's OS thread. The simplest correct rule: clone
into shared heap (`allocShared0`) with `shared=false` (so retain/release
stay non-atomic on the receiver side after transfer). The value is
logically owned by the receiver; no other actor ever sees the pointer.
Alternative: clone into receiver's thread-local heap by briefly acquiring
that thread's allocator. Requires scheduler coordination; defer to MVP+1.

### E. Runtime freeze discipline

**Change**: add `runtime_frozen: bool {.global.}` flag. Set at end of
`init_app_and_vm` (`src/gene/types/helpers.nim`).

**Files affected**:
- Every `Namespace.[]=` call site (grep `.ns\[.*\]\s*=` in `src/`).
- `Class.methods[...] = ...` at `src/gene/stdlib/classes.nim:333-338` and
  every `def_native_method` call (~440 sites across `src/gene/stdlib/*.nim`
  — all run during init, so they just need to run before the freeze flag
  flips; no per-site changes required if freeze happens at the right time).
- `Namespace.version` / `Class.version` increments
  (`src/gene/types/type_defs.nim:487, 502`) — must be no-op after freeze.

**Debug assertions**: in debug builds, mutators assert
`not runtime_frozen`. In release, the assertions compile out. CI runs the
debug build.

### F. Inline-cache race fix

**Change**: either per-worker or atomic inline caches.

**Option F1 (per-worker)**: move `inline_caches` off `CompilationUnit` into
the per-thread VM state. Each worker has its own cache keyed by (cu.id, pc).
Memory cost: caches are duplicated per worker. Cache misses on actor
migration between workers.

**Option F2 (atomic slots)**: keep `inline_caches` on `CompilationUnit` but
pre-size to `instructions.len` at compile time
(`src/gene/compiler.nim:620, 703, 759` already do this). Remove the lazy
`setLen`/`add` path at `src/gene/vm/exec.nim:10-12`. Cache slots are
updated with atomic writes; reads are plain loads (stale reads are
acceptable since caches are advisory).

**Recommendation**: F2. Less memory, simpler API, matches JIT inline-cache
patterns in other runtimes.

### G. Port-actor protocol for extensions

**Change**: define a new Nim-side extension API. An extension registers
**one or more** ports; the right topology depends on the resource shape.

**Three port patterns**:

1. **Singleton port** — one mailbox, all calls serialized. The right
   choice for a genuine process-global singleton (one `llama.cpp` runtime,
   one hardware device, one global telemetry collector). Reference case:
   `src/genex/llm.nim`.
2. **Port pool** — extension registers N ports; extension-level routing
   picks one per message (round-robin, least-loaded, or hashed by key).
   The right choice for scalable resources where independent units share
   nothing across units (database connection pools, HTTP clients). Avoids
   the single-mailbox bottleneck.
3. **Port factory** — extension dynamically spawns a port actor per
   user-facing resource handle; tears it down when the handle closes. The
   right choice for per-instance state (one open socket, one file
   descriptor, one parser state machine).

**Protocol**:
```nim
# Singleton
register_port("llm", llm_port_handler)

# Pool
register_port_pool("db", pool_size = 8, db_port_handler)

# Factory: extension exposes a constructor that spawns a port per handle.
proc open_socket(host: string, port: int): Value =
  spawn_port(socket_port_handler, init_state = connect(host, port))
```

**Handler contract** (all patterns):
```nim
proc my_port_handler(msg: Value): Value {.gcsafe.} =
  # Runs on the port's dedicated worker. Thread-unsafe libraries OK here.
  # Must not retain `msg` or its pointers beyond this call.
  ...
```

**VM integration**: at startup, singleton and pool ports spawn their
actors; factory ports spawn on-demand when user code invokes the
extension's constructor. Symbols referring to a singleton extension
(e.g. `llm/generate`) compile to `(my-port .send {:op ...})`. Pool and
factory handles are first-class port actors that user code sends to
directly.

**Migration of existing extensions**: `src/genex/llm.nim` is the
singleton reference. Replace the `global_llm_op_lock` pattern with
`register_port`. Extensions with pool-shaped resources (HTTP, DB) use
`register_port_pool` when they arrive.

## Implications

### For users

- **Concurrency is one concept, not eight.** Spawn an actor, send a message,
  optionally await a reply. Every other concurrency facility in the current
  and proposed models goes away.
- **Gene's data-manipulation style is preserved.** Literals remain mutable.
  `(i = 20)`, `(i += 5)`, `.put`, `.add`, `.set`, `.delete`, `.merge`
  continue to work exactly as today. No language-wide breaking change.
- **`.send` never fails on a value-kind check.** Any value can be sent; the
  runtime picks the right transfer strategy (pass by value, pointer-share,
  or clone).
- **`freeze` is a performance tool.** Call `(freeze v)` when sending the
  same large read-only payload repeatedly (config, lookup tables, model
  weights). The freeze is a one-time cost; subsequent sends are O(1).
- **Mutable sends have visible cost.** Sending a 10 MB mutable map clones
  10 MB. Still much faster than today's serialize round-trip (no text
  formatting or parsing), but not free. A future `send!` (deferred, Open
  Question) would offer O(1) move-semantics for hot paths.
- **No lock APIs.** If a user reaches for a lock, they're writing a port
  actor instead. Shared mutable state across actors is a state actor; each
  message is one transaction against that actor's private state.
- **Instances work like any other value.** `(def p (Point/new 1 2))`
  produces a mutable instance sent by clone. `(freeze (Point/new 1 2))`
  produces a shareable snapshot. Classes can opt into frozen-by-default
  via a class annotation (Open Question #1).

### For the language and ecosystem

- **No stdlib rename.** Existing method names (`"add"`, `"put"`, `"set"`,
  `"delete"`, `"merge"`, `"pop"`, `"push"`, `"clear"`) stay. Mutators
  operate on mutable values as today; they raise on frozen values.
- **No persistent data structures required.** Mutable collections remain
  the idiom. A persistent HAMT/RRB is a nice-to-have for users who want
  cheap copy-on-update, not a prerequisite.
- **No source-compat break.** The mutability-flip phase that an immutable-
  by-default design would have required is not in this plan. The language
  ships the actor model without breaking existing Gene code.
- **Closures as values.** A closure is deep-freezable iff its code is
  immutable (always true) and all its captured free variables are
  deep-frozen. An unfrozen closure is cloneable when its captured env is
  itself cloneable; otherwise `.send` raises with a clear message about
  which capture blocked the send (e.g. file handles, port refs).

### For the runtime

- **`GENE_MAX_THREADS` becomes `GENE_WORKERS`.** Same knob, different
  meaning: the size of the worker pool that runs actors.
- **Serialization is for persistence only.** `serialize` / `deserialize`
  stay for files, the gdat format, and any future IPC. `.send` no longer
  touches them.
- **GC story simplifies.** Each actor's thread-local heap is reclaimed en
  masse when the actor dies. Shared-heap values (only frozen values, plus
  clones-in-transit briefly) use atomic refcount. Cross-heap cycles cannot
  form: frozen values cannot reference mutable (frozen is deep-closed);
  mutable values may reference frozen, but that's a one-way edge that does
  not create cross-heap cycles.

## Tradeoffs

| Axis | Gain | Cost |
|------|------|------|
| Mental model | 8 concepts → 1 (actor) | Users learn when to `freeze` hot payloads |
| Language feel | Gene stays Gene; no syntax or stdlib rename | Send cost is visible, not hidden |
| Default send cost | O(N) × clone; 5-20× faster than today's serialize round-trip | O(N), not O(1); large mutable payloads still pay |
| Hot-path send cost | O(1) via explicit `freeze` | Users must profile and opt in |
| Single-threaded perf | Same as today on owned values | +1 branch on retain/release for the `shared` check |
| Memory | Owned heap unchanged; shared heap grows with frozen footprint | Clones briefly double memory during send; typically short-lived |
| Extension authors | Uniform port protocol replaces ad-hoc locks | Existing extensions (`llm.nim`, future DB clients) rewritten to port style |
| Source compat | **No breaking change.** All existing Gene programs run unchanged | Send performance tunable, not automatic |
| Scheduler | M:N scales to core count without user tuning | One atomic CAS per dispatch; mailbox contention on hot actors |
| Debuggability | Deterministic within an actor; no cross-actor state races | Stack traces span actor boundaries; needs distributed-trace-style tooling |

### Alternatives considered

- **Real share-nothing (BEAM-style)**: per-actor heaps, per-actor symbol
  tables, full copy on send. Rejected: ~8 ms spawn latency, duplicated
  stdlib per actor, memory blow-up with many small actors.
- **Immutable-by-default** (earlier draft of this document): literal `{}`
  produces a deep-frozen value, mutation via explicit opt-in. Rejected:
  breaks Gene's demonstrated mutation-first identity (`examples/full.gene`,
  all stdlib mutator names), forces a stdlib rename, requires HAMT/RRB
  implementation before the model can ship, makes every existing program a
  migration target.
- **Serialization (status quo)**: text round-trip at send. Rejected: slow
  and literal-only; leaves the eight-concept surface in place.
- **Shared-memory with locks**: gives up actor isolation, keeps the current
  burden of lock discipline. Rejected: fails the "no burden" goal.
- **Software transactional memory (STM)**: composable but slow on
  contention, complex runtime. Rejected: overkill for the problem and
  orthogonal to actor isolation.
- **Move-semantics send** (`send!`): sender loses access, O(1) transfer.
  **Deferred** (Open Question #10) — valuable for hot paths but adds a
  second send primitive and an ownership check. Revisit once profiling on
  Phase 2 identifies the need.

## Migration Path

No source-compat break at any phase. Stageable as follows:

**Phase 0: unify lifetime and publication semantics** (weeks 1–6)

Phase 0 is the gate for everything downstream. It repays correctness debt
in the existing runtime that would otherwise compound once shared-heap
values, atomic refcounts, and the actor scheduler are layered on. Each
sub-phase below is independently shippable and delivers value on its own
even if the larger actor work is paused.

**P0.1 — Unify RC paths.** Today two lifetime machines coexist:

- Manual `retain` / `release` called from VM opcodes
  (`src/gene/types/core/value_ops.nim:57, 85`).
- Nim-hook driven `retainManaged` / `releaseManaged` via `=copy` /
  `=destroy` / `=sink` on the `Value` distinct type
  (`src/gene/types/memory.nim:78, 118, 186-213`).

Any `Value` that crosses between VM-opcode ownership and `var Value`
bindings in Nim is refcounted by both. Collapse to a single source of
truth before adding an atomic-vs-plain branch in Phase 1. Recommended
direction: keep the managed hooks (they are correct by construction at
every Nim assignment site) and audit all manual call sites to use the
same protocol, or remove them where the hook already covers the write.

**P0.2 — Fix lazy-publication races.** Four publication points write a
shared slot without synchronization today. All must use release-store on
publish / acquire-load on read, or be moved to compile time:

- `Function.body_compiled` / `Block.body_compiled` — assigned on first
  invocation at `src/gene/vm/exec.nim:467, 503, 2146, 2274, 2298, 3395,
  4705, 4767, 4808`. Two actors calling the same function for the first
  time concurrently can both compile and both write, tearing the slot.
- JIT `native_ready` / `native_entry` at `src/gene/vm/native.nim:98-110`.
  Same hazard; readers must observe the entry only after the flag is
  visible.
- `CompilationUnit.inline_caches` lazy growth at
  `src/gene/vm/exec.nim:4-12`. Per-worker cache, or pre-sized at compile
  time with atomic slot updates.
- Any runtime-published bootstrap namespace entry — if Phase 1 later
  supports `(publish! ns key value)` for explicit post-init sharing, it
  must use the same protocol.

**P0.3 — Fix thread API correctness bugs.** Two pre-existing bugs in
today's thread runtime, independent of the actor work:

- `src/gene/vm/async_exec.nim:147-150` — `poll_event_loop` always drains
  `THREAD_DATA[0].channel`, regardless of which thread is polling. Every
  worker thread other than thread 0 never processes its replies. Fix:
  index by the caller's own thread slot.
- `src/gene/vm/thread_native.nim:337-358` — `thread_on_message` stores
  the callback on `vm.message_callbacks`, which is the **caller's** VM,
  not the target thread's. Fix: dispatch the registration to the target
  thread's VM (e.g., via a control message on that thread's channel).

**P0.4 — Strings become immutable.** Per the recorded decision. Today
`String.append` mutates in place (`src/gene/stdlib/strings.nim:38-58`)
and `IkPushValue` copies every string literal for mutation safety
(`src/gene/vm/exec.nim:1518-1523`). Changes:

- Remove or reshape `String.append` and related mutators to return new
  strings (or move bulk-building to a `StringBuilder` type); audit other
  in-place paths surfaced during the cut.
- Delete the `IkPushValue` copy — string literals can then be shared by
  pointer directly, which is a material perf improvement independent of
  actors.
- Interned string constants in `CompilationUnit` become eligible for the
  I5 "code image" invariant.

This is a user-visible breaking change on the string API surface; it is
scheduled in Phase 0 because (a) it is cheaper to do before actors than
after, (b) it unlocks I5's "code images read-only" for strings, and (c)
it removes a per-push allocation from the hot path.

**P0.5 — Bootstrap freeze discipline.** Introduce the `bootstrap_frozen`
flag per the revised I5. Guard only the five listed shared targets
(bytecode, published JIT, bootstrap types, init-time `gene_ns` /
`genex_ns` snapshot, interned strings). Runtime-created classes and
namespaces are actor-local in Phase 2 and are not gated by this flag.

Deliverable: single RC path in place as the substrate for Phase 1; four
lazy-publication races fixed; two thread-API correctness bugs fixed;
strings are immutable and shared by pointer; bootstrap freeze invariant
enforced on the narrowed scope. User-visible change limited to the
string API cut.

**Phase 1: deep-frozen bit, shared heap, `freeze` — narrow freeze scope**
(weeks 3–5)

- Add `deep_frozen` and `shared` flags (I2/I3/A/B).
- Shared-heap allocation path for frozen values (B).
- Atomic retain/release branch on `shared` (I4/B).
- Stdlib `(freeze v)` operation.

**Phase 1 freeze scope (MVP)**: arrays, maps (map and hash_map), genes,
bytes. Strings are already immutable after P0.4 and are trivially
pointer-shareable — no `freeze` call required. All other kinds are
initially non-freezable and therefore clone-on-send.

Deferred to **Phase 1.5** (between Phase 1 and Phase 2, before the actor
API ships): freezable closures, gated on the captured environment being
itself freezable. This is a hard prerequisite for Phase 2 — without
freezable closures, `(spawn ^state ... handler)` cannot receive a shared
handler from another actor.

Deferred to later phases: `Instance` freezing (instance writes are
scattered across `IkSetMember` / `IkSetProperty` opcodes in
`src/gene/vm/exec.nim` with no single mutator gate; needs design work
before a freeze bit is meaningful); `Class` and `BoundMethod` freezing
(collides with I5's "actor-local runtime-defined classes" — needs
publication-protocol design first).

The two-freeze-level naming (shallow "sealed" for existing `#[]` /
`#{}` / `#()`, deep "frozen" for `(freeze v)` output) is finalized in
this phase.

Deliverable: programs can opt into frozen values over the container
spine. No new concurrency API yet. Existing thread code unaffected.

**Phase 2: actor scheduler and tiered send** (weeks 6–10)
- Actor record, state machine, worker pool (C).
- Mailbox as typed channel (reuse `src/gene/vm/thread_native.nim:35-73`).
- `(spawn)`, `.send`, `.send_expect_reply`, `.stop` APIs.
- **2a — tiered send**: primitive by value, frozen by pointer, mutable by
  `deep_clone` (D).
- Benchmarks: compare `.send` latency to current `serialize_literal` round
  trip. Target ≥ 5× speedup on mutable payloads, ≥ 100× on frozen payloads.

Deliverable: actors work with full send-tier performance. Old thread API
still present in parallel.

**Phase 3: port-actor protocol** (weeks 11–12)
- Extension registration API (G).
- Migrate `src/genex/llm.nim` as proof (G).
- Migrate other extensions with process-global state.

Deliverable: extensions uniform; no hand-rolled global locks.

**Phase 4: deprecate thread API** (week 13+)
- Mark `(spawn_thread)` deprecated. Keep working for one release.
- Remove in the following release.
- Rename `GENE_MAX_THREADS` → `GENE_WORKERS`.

Deliverable: one concurrency primitive.

**Future (deferred, not scheduled)**:
- Move-semantics `send!` for O(1) mutable transfers (Open Question #10).
- Class-level `^frozen-default` annotation for value-type classes (Open
  Question #1).
- Work-stealing scheduler (pinning is the MVP).

### Rollback plan

Every sub-phase is independently revertable. P0.1–P0.3 and P0.5 only add
code paths or substitute equivalent implementations; they do not change
user-observable behavior. P0.4 (string-immutability cut) is the only
user-visible break in the plan and has its own deprecation window: ship
`String.append` returning a new value first, emit a deprecation warning
one release before removing the in-place mutator. Phase 1–2 only add
code paths. Phase 3 is extension-local. Phase 4 has a one-release
deprecation window for the old thread API.

## Open Questions

These require explicit decisions before or during implementation.

1. **Class-level frozen-default.** Should classes be able to opt in to
   deep-frozen instances via a `^frozen-default` or `^value` annotation,
   useful for Point/Vector/Date value types? Recommend: add in a later
   phase; MVP uses explicit `(freeze ...)` per instance.
2. **String semantics.** **Resolved: immutable with shared-by-pointer.**
   Today strings are mutable via `String.append`
   (`src/gene/stdlib/strings.nim:38-58`) and `IkPushValue` copies every
   string literal on push for mutation safety
   (`src/gene/vm/exec.nim:1518-1523`). Scheduled as P0.4. Remaining
   detail: pick between returning-new-string for `String.append` or
   removing it in favor of `StringBuilder` — decide before P0.4 lands.
3. **Channels as separate primitive, or just actor mailboxes?** BEAM has
   only mailboxes. Go has only channels. Hybrid models (Pony, Akka Typed)
   have both. Recommend: mailboxes only for MVP; add `(channel)` later if
   request/response pipelines demand it.
4. **Selective receive vs FIFO mailbox.** Erlang has selective receive;
   modern actor systems (Akka Typed, Pony) discourage it. Recommend:
   FIFO only in MVP; revisit if user demand surfaces.
5. **Reply mechanism.** `.send_expect_reply` returns a Future. How is the
   Future fulfilled — dedicated one-shot mailbox, or a special reply slot
   on the caller actor's mailbox? Recommend: one-shot reply channel
   allocated per call, GC'd after resolution.
6. **Actor GC.** When is an actor reclaimed? Options: (a) explicit `.stop`
   required; (b) GC when no handles exist and mailbox empty; (c) linked
   actors die with their parent (Erlang `link`). Recommend: (a) for MVP,
   (c) later with explicit `link` API.
7. **Fairness and backpressure.** If one actor floods another's mailbox,
   should the scheduler throttle? Recommend: bounded mailbox with
   **non-blocking** backpressure — a full mailbox never blocks the worker
   thread executing the sender's turn. Options:
   - **(a, default) Park the sender actor.** `.send` to a full mailbox
     returns sender's turn as "waiting on B"; worker picks the next
     Ready actor. When B drains below threshold, A becomes Ready again.
     Transparent to user code; scheduler handles it.
   - **(b) `try_send` variant** returning `Sent | Overflow` for callers
     that want explicit overflow policy (drop, log, escalate).
   - **(c) Blocking is permissible only from non-actor entrypoints**
     (main thread, FFI callback), because there is no actor turn to
     stall.
   Blocking the worker thread on a full mailbox would stall every other
   Ready actor currently queued on that worker — a scheduler-wide
   latency hit for a single mailbox's pressure. Unbounded mailboxes are
   still the worse failure mode and remain rejected.
8. **Error handling.** What happens when a handler throws? Options:
   (a) actor dies, message lost, caller notified; (b) retry; (c) supervisor
   pattern. Recommend: (a) with a `monitor` API to observe deaths.
9. **Existing thread tests.** `tests/test_threads.nim` (and related) — do
   they migrate to actor-based equivalents, or stay until Phase 4 removes
   the thread API? Recommend: keep as-is through Phase 3; rewrite in
   Phase 4.
10. **Move-semantics `send!` (deferred).** An O(1) send that transfers
    ownership of a mutable value: sender loses access, receiver gains it,
    no clone. Valuable for hot paths that send large mutable payloads.
    Cost: second send primitive; runtime ownership tracking (linearity
    check). **Deferred.** Revisit when Phase 2 profiling identifies a
    specific hot path that would benefit.
11. **Performance targets.** Acceptance criteria for Phase 2. Suggested
    baseline: "spawn < 10 µs, send < 1 µs for primitives and frozen
    values, clone-send throughput ≥ 5× current `serialize_literal` path,
    100k actors on 8 cores at ≥ 1M msg/sec aggregate for small-message
    ping-pong." Without numbers, tradeoffs are unverifiable.

## References

- `docs/global-access.md` — current global-access proposal, superseded by
  this document.
- `docs/thread_support.md` — current thread implementation details.
- `docs/proposals/future/actor_support.md` — earlier actor proposal; this
  document extends and supersedes it by making actors the only primitive
  and adding the six-invariant race-freedom argument.
- `src/gene/vm/thread_native.nim:35-73` — existing mailbox (Lock + Cond);
  reused as the actor mailbox substrate.
- `src/gene/vm/thread_native.nim:258-317` — current send path
  (`serialize_literal` round-trip); replaced in Phase 2.
- `src/gene/types/core/value_ops.nim:57, 85` — manual `retain` /
  `release`; unified with managed path in P0.1.
- `src/gene/types/memory.nim:78, 118, 186-213` — managed
  `retainManaged` / `releaseManaged` and `=copy` / `=destroy` / `=sink`
  hooks; sole RC source of truth after P0.1.
- `src/gene/types/core/value_ops.nim:145-176` — shallow frozen checks;
  generalized to deep-frozen in Phase 1.
- `src/gene/types/core/constructors.nim:64, 134, 203, 248, 434` — all
  `alloc0` sites; shared-heap variants added in Phase 1.
- `src/gene/vm/exec.nim:4-12` — lazy inline-cache growth (race hazard);
  fixed in P0.2.
- `src/gene/vm/exec.nim:467, 503, 2146, 2274, 2298, 3395, 4705, 4767,
  4808` — `Function.body_compiled` / `Block.body_compiled` lazy
  assignment; gated in P0.2.
- `src/gene/vm/native.nim:98-110` — JIT `native_ready` / `native_entry`
  lazy publication; release-store / acquire-load fix in P0.2.
- `src/gene/vm/async_exec.nim:147-150` — `poll_event_loop` drains only
  thread-0 channel regardless of caller; fixed in P0.3.
- `src/gene/vm/thread_native.nim:337-358` — `thread_on_message`
  registers callback on caller's VM, not target's; fixed in P0.3.
- `src/gene/stdlib/strings.nim:38-58` — `String.append` mutates in
  place; reshaped or removed in P0.4.
- `src/gene/vm/exec.nim:1518-1523` — `IkPushValue` copies string
  literals for mutation safety; copy deleted in P0.4.
- `src/gene/types/type_defs.nim:487, 502` — `Namespace.version` /
  `Class.version` mutation. Per revised I5, these are actor-local writes
  on actor-local objects once Phase 2 lands; no `bootstrap_frozen` gate
  required.
- `src/gene/vm/module.nim` — ModuleCache race hazard; flagged in
  `docs/thread_support.md:107-109`. Scheduled under P0.2 if it shares a
  publication slot with bootstrap; otherwise actor-local per revised I5.
- `src/gene/parser.nim:1045, 1088`;
  `src/gene/types/core/constructors.nim:452, 455` — existing
  shallow-frozen `#[]` / `#{}` / `#()` literals; retained as sealed
  (shallow) under the two-level decision below.
- `src/genex/llm.nim:13-14, 780-868` — current hand-rolled global-lock
  pattern; reference case for port-actor migration in Phase 3.

## Decisions

Sign-off recorded:

- **Approved.** Four-rule model as the target architecture — actors as only
  primitive; mutable-by-default data; tiered send (primitive by value,
  frozen by pointer, mutable by deep-clone); port actors for extensions.
- **Approved.** Phased migration plan (Phase 0 → Phase 4). Phase 0 is
  expanded to cover RC unification, lazy-publication races, two
  thread-API correctness bugs, the string-immutability cut, and the
  narrowed bootstrap-freeze invariant. Source-compat break is limited
  to the string mutator API (P0.4).
- **Approved.** Two freeze levels. Existing `#[]` / `#{}` / `#()` keep
  their current shallow-frozen semantics ("sealed": the container is
  immutable but children may mutate through aliases). The new
  `(freeze v)` operation produces deep-frozen values. Only deep-frozen
  values are sendable by pointer across actors; sealed-but-not-frozen
  values go through `deep_clone`. Naming ("sealed" vs "frozen", or a
  single word with a `deep` qualifier) to be finalized in Phase 1.
- **Approved.** Strings become immutable with shared-by-pointer
  semantics. Scheduled as P0.4 because (a) it is cheaper before actors
  than after, (b) it unlocks I5's "code images read-only" for interned
  strings, and (c) removing the `IkPushValue` copy is a hot-path win
  independent of actors. Remaining sub-decision: return-new-string vs
  `StringBuilder` for bulk concat — resolve before P0.4 lands.
- **Deferred (not dropped).** `send!` move-semantics (Open Question #10);
  revisit when Phase 2 profiling identifies hot paths that would benefit.
- **Deferred (not dropped).** Class-level `^frozen-default` annotation for
  value types (Open Question #1); add in a later phase once the MVP
  stabilizes.

Outcome: Gene's concurrency story reduces from eight concepts to one,
on top of a runtime whose lifetime and publication semantics are uniform
by construction. The only user-visible break is the string mutator API
cut (P0.4). Hot paths opt into O(1) sends via `freeze`; extensions
migrate to a uniform port protocol.

Remaining Open Questions (#3–#9, #11) still need answers but do not block
Phase 0 kickoff. They are scoped to their respective phases in the
migration plan.

