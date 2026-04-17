# Gene Actor Runtime Migration

## What This Is

This workstream ports the approved actor-based concurrency design in
`docs/proposals/actor-design.md` into the existing `gene-old` runtime. The
current tracked scope is Phase 0 only: unify lifetime and publication
semantics so later actor primitives land on a stable substrate instead of
stacking new races on top of the current runtime.

## Core Value

Phase 0 must make Gene's runtime ownership and publication semantics safe
enough for later actor work without destabilizing the existing VM.

## Requirements

### Validated

- ✓ Bytecode execution, async futures, thread messaging, native trampoline
  compilation, and stdlib string operations already exist in the current
  runtime.
- ✓ Brownfield planning context already exists in `.planning/codebase/` and the
  exploratory `.planning/phases/01-architecture-comparison/` draft.

### Active

- [ ] Unify `Value` ownership around one ref-counting model across manual VM
  writes and Nim-managed assignment hooks.
- [ ] Remove unsynchronized publication paths for lazy body compilation, inline
  caches, and native code entry.
- [ ] Fix thread reply polling and `.on_message` registration so non-main worker
  paths behave correctly.
- [ ] Make strings immutable and remove defensive string-literal copies from
  `IkPushValue`.
- [ ] Add explicit bootstrap publication discipline for the narrow set of shared
  runtime artifacts needed by later actor phases.

### Out of Scope

- Deep-frozen/shared heap support and `(freeze v)` - deferred until after Phase
  0 lands cleanly.
- Actor scheduler, mailbox send tiers, port actors, and thread API deprecation -
  follow-on actor phases, not this track.
- Distributed actors, supervision trees, hot code loading, and compile-time
  effect typing - explicitly rejected by the approved proposal.

## Context

`gene-old` is a brownfield Nim runtime with a bytecode VM, async futures,
thread messaging, extension loading, native compilation, AOP, and a broad
stdlib surface. The approved actor design proposal identifies current
correctness debt in ref-counting, lazy publication, thread APIs, mutable
strings, and bootstrap sharing as the blocking substrate for every later actor
phase.

Existing codebase analysis in `.planning/codebase/CONCERNS.md` flags scope
lifetime, thread lifecycle, and monolithic VM execution as fragile areas. This
track intentionally leaves the older `.planning/phases/01-architecture-
comparison/` material untouched so current work can focus on the proposal's
Phase 0 without renumbering or rewriting historical exploratory docs.

## Constraints

- **Tech stack**: Keep the existing Nim runtime and test harness - no new
  dependencies without explicit request.
- **Compatibility**: Preserve existing behavior except for the proposal-approved
  string mutator break in P0.4.
- **Validation**: Lock behavior with targeted runtime tests before cleanup-style
  refactors in hot paths.
- **Planning**: Track only proposal Phase 0 in GSD for now to avoid colliding
  with the preserved legacy `01-architecture-comparison` directory.
- **Performance**: Do not regress hot paths without measurement; removing the
  `IkPushValue` string copy is the only expected perf win in this phase.

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Track only proposal Phase 0 in ROADMAP.md for now | Avoids phase-number collisions with preserved legacy planning and keeps the work bounded | - Pending |
| Mirror P0.1-P0.5 as five executable plans | Preserves proposal rollback boundaries and keeps verification focused | - Pending |
| Resolve P0.4 with return-new-string semantics for `String.append` | Smallest immutable-string cut that removes the current literal-copy workaround | - Pending |

## Evolution

This document evolves at phase transitions and milestone boundaries.

**After each phase transition:**
1. Requirements invalidated? -> Move to Out of Scope with reason
2. Requirements validated? -> Move to Validated with phase reference
3. New requirements emerged? -> Add to Active
4. Decisions to log? -> Add to Key Decisions
5. "What This Is" still accurate? -> Update if drifted

**After each milestone:**
1. Full review of all sections
2. Core Value check - still the right priority?
3. Audit Out of Scope - reasons still valid?
4. Update Context with current state

---
*Last updated: 2026-04-17 after actor-design Phase 0 bootstrap*
