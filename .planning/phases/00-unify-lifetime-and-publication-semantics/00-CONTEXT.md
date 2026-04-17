# Phase 0: Unify lifetime and publication semantics - Context

**Gathered:** 2026-04-17
**Status:** Ready for planning

<domain>
## Phase Boundary

Phase 0 repays current correctness debt in ref-counting, lazy publication,
thread API behavior, string semantics, and bootstrap sharing. It does not add
the actor scheduler, shared heap, deep-freeze/send tiers, or port actors; it
only establishes the runtime substrate those later phases depend on.

</domain>

<decisions>
## Implementation Decisions

### Scope and sequencing
- **D-01:** This GSD track covers only proposal Phase 0; future actor phases
  remain deferred in `docs/proposals/actor-design.md` until Phase 0 verifies
  cleanly.
- **D-02:** Preserve proposal numbering and execute P0 as five plans that mirror
  P0.1-P0.5.
- **D-03:** Leave `.planning/phases/01-architecture-comparison/` untouched and
  treat it as historical exploratory context, not active roadmap state.

### Compatibility guardrails
- **D-04:** Lock current behavior with targeted runtime tests before
  cleanup-style refactors in RC, publication, thread, and string hot paths.
- **D-05:** No new dependencies or parallel infrastructure changes; use the
  existing Nim runtime, test harness, and codegen paths.

### String cut
- **D-06:** Resolve P0.4 with return-new-string semantics for `String.append`
  and matching helper paths in `stdlib/core.nim`.
- **D-07:** Delete the `IkPushValue` string literal copy once strings are
  immutable; this is the only approved hot-path behavior change in Phase 0.

### Bootstrap sharing
- **D-08:** Bootstrap publication discipline applies only to bytecode/code-image
  artifacts, published JIT entry, bootstrap registries, init-time `gene_ns` /
  `genex_ns` snapshot, and interned strings.
- **D-09:** Runtime-created namespaces and classes stay actor-local; do not gate
  `Namespace.version` or `Class.version` mutations behind bootstrap sharing
  rules.

### the agent's Discretion
- Exact helper/API shapes for RC ownership normalization, publication guards,
  and bootstrap assertions.
- Whether publication hazards are fixed via eager initialization or explicit
  release/acquire/CAS, so long as the resulting invariant matches the proposal.

</decisions>

<specifics>
## Specific Ideas

- The proposal already pinpoints the exact P0 touch points in `value_ops.nim`,
  `memory.nim`, `exec.nim`, `native.nim`, `async_exec.nim`,
  `thread_native.nim`, `strings.nim`, and `helpers.nim`.
- Existing tests already exercise scope lifetime, thread messaging, string
  stdlib behavior, native trampoline publication, and GIR lazy compilation.

</specifics>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Approved design
- `docs/proposals/actor-design.md` — Approved target model, phased migration,
  and phase 0 sub-phase definitions.
- `docs/proposals/actor-design.md` §§ "Phase 0" and "References" — Concrete
  touch points for P0.1-P0.5 and the narrowed bootstrap invariant.

### Existing implementation hot spots
- `src/gene/types/core/value_ops.nim` — Manual `retain` / `release` path and
  frozen checks.
- `src/gene/types/memory.nim` — Managed `retainManaged` / `releaseManaged` and
  `=copy` / `=destroy` / `=sink`.
- `src/gene/vm/exec.nim` — Inline cache growth, lazy `body_compiled`, and
  `IkPushValue` string copying.
- `src/gene/vm/native.nim` — `native_ready` / `native_entry` publication.
- `src/gene/vm/async_exec.nim` — Thread reply polling path.
- `src/gene/vm/thread_native.nim` — Thread send path and `.on_message`
  registration.
- `src/gene/stdlib/strings.nim` — Current in-place string mutation surface.
- `src/gene/stdlib/core.nim` — Duplicate string helper paths that must match the
  stdlib class implementation.
- `src/gene/types/helpers.nim` — App / namespace bootstrap and VM init path.

### Existing regression coverage
- `tests/integration/test_scope_lifetime.nim` — Scope and async lifetime
  baseline.
- `tests/integration/test_thread.nim` — Thread send/reply and keep-alive
  behavior.
- `tests/integration/test_stdlib_string.nim` — Stdlib string surface.
- `tests/test_native_trampoline.nim` — Native compile/publish behavior.
- `tests/integration/test_cli_gir.nim` — Lazy compile and GIR load behavior.

### Known fragility
- `.planning/codebase/CONCERNS.md` — Scope lifetime, thread lifecycle, and
  monolithic VM execution risks that Phase 0 must respect.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `tests/integration/test_scope_lifetime.nim`: fast regression harness for
  scope and async ownership behavior.
- `tests/integration/test_thread.nim`: already covers `.on_message` and
  `send_expect_reply`; extend it instead of creating a parallel thread suite.
- `tests/integration/test_stdlib_string.nim`: broad string API baseline for the
  immutability cut.
- `tests/test_native_trampoline.nim`: focused native publication assertions for
  `native_ready` and `native_entry`.

### Established Patterns
- VM hot paths live in include-based monoliths under `src/gene/vm/*.nim`; keep
  changes local and test-driven because extraction is incomplete.
- The compiler already sizes `inline_caches` eagerly in some paths; Phase 0
  should normalize around that rather than inventing a second cache strategy.
- Runtime tests typically compile Gene snippets and execute them directly; use
  that style for new regression coverage.

### Integration Points
- P0.1 joins `types/core/value_ops.nim`, `types/memory.nim`, frame ownership,
  and native trampoline descriptor lifetimes.
- P0.2 spans compiler output, exec-loop consumption, GIR load, and native code
  publish state.
- P0.3 lives in thread/async runtime plus thread integration tests.
- P0.4 crosses stdlib string methods and VM literal loading.
- P0.5 touches VM/app bootstrap plus a cross-phase regression sweep.

</code_context>

<deferred>
## Deferred Ideas

- Deep-frozen/shared heap `(freeze)` support and actor send tiers.
- Port actors for LLM and other process-global resources.
- Thread API deprecation and `GENE_WORKERS` rename.

</deferred>

---

*Phase: 00-unify-lifetime-and-publication-semantics*
*Context gathered: 2026-04-17*
