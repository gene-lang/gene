# Roadmap: Gene Actor Runtime Migration

## Overview

This roadmap captures only the approved actor-design Phase 0 from
`docs/proposals/actor-design.md`. Later actor phases stay deferred in the
proposal until the runtime's lifetime and publication foundation verifies
cleanly. Existing `.planning/phases/01-architecture-comparison/` artifacts are
preserved as historical exploratory material and are intentionally not part of
this roadmap.

## Phases

**Phase Numbering:**
- Proposal numbering is preserved for this actor-runtime track.
- Only Phase 0 is tracked here until the current foundation work completes.

- [ ] **Phase 0: Unify lifetime and publication semantics** - Repay
  correctness debt in ref-counting, publication, thread messaging, string
  semantics, and bootstrap sharing before actor primitives land

## Phase Details

### Phase 0: Unify lifetime and publication semantics
**Goal**: Remove the current runtime ownership and publication hazards that would compound under actor concurrency, while keeping the only approved user-visible break limited to the string mutator cut.
**Depends on**: Nothing (active foundation phase)
**Requirements**: [LIFE-01, PUB-01, PUB-02, PUB-03, THR-01, THR-02, STR-01, STR-02, BOOT-01]
**Success Criteria** (what must be TRUE):
  1. Ref-counting and `Value` assignment semantics are uniform enough that scope, async, and native-boundary tests do not depend on mixed manual and hook-based ownership rules.
  2. Lazy publication points for compiled bodies, inline caches, and native entry state are synchronized or eagerly initialized with regression coverage.
  3. Thread replies and message callback registration work on the intended worker VM, not just thread 0 or the calling VM.
  4. Strings are immutable by default, `String.append` no longer mutates shared storage, and `IkPushValue` stops copying string literals defensively.
  5. Bootstrap-shared runtime artifacts have an explicit publication boundary that later actor/shared-heap work can rely on.
**Plans**: 5 plans

Plans:
- [ ] 00-01: Unify ref-counting paths around managed `Value` hooks
- [ ] 00-02: Fix lazy publication for compiled bodies, inline caches, and
  native entry
- [ ] 00-03: Repair thread reply polling and target-VM callback registration
- [ ] 00-04: Cut over to immutable strings and delete literal push copies
- [ ] 00-05: Enforce bootstrap publication discipline and run phase acceptance
  sweep

## Progress

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 0. Unify lifetime and publication semantics | 0/5 | Not started | - |
