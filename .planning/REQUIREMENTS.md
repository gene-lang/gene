# Requirements: Gene Actor Runtime Migration

**Defined:** 2026-04-17
**Core Value:** Phase 0 must make Gene's runtime ownership and publication
semantics safe enough for later actor work without destabilizing the existing
VM.

## v1 Requirements

### Lifetime Semantics

- [ ] **LIFE-01**: `Value` ownership uses a single ref-counting source of truth
  across manual VM writes, Nim `=copy` / `=destroy` hooks, and
  function/native-trampoline boundaries.

### Publication Safety

- [ ] **PUB-01**: Lazy function and block compilation no longer publish
  `body_compiled` through unsynchronized writes.
- [ ] **PUB-02**: Inline cache storage is pre-sized or synchronized so runtime
  execution does not grow `inline_caches` opportunistically.
- [ ] **PUB-03**: Native code publication exposes `native_entry` only after
  `native_ready` is visible with release/acquire semantics or an equivalent
  eager-initialization guarantee.

### Thread Correctness

- [ ] **THR-01**: `poll_event_loop` drains the caller's thread channel rather
  than hard-coding thread 0.
- [ ] **THR-02**: `Thread.on_message` installs callbacks on the target thread VM
  rather than the caller VM.

### String Immutability

- [ ] **STR-01**: `String.append` and related mutators stop mutating shared
  storage in place and return new strings instead.
- [ ] **STR-02**: `IkPushValue` no longer copies string literals defensively
  before pushing them on the VM stack.

### Bootstrap Publication

- [ ] **BOOT-01**: Bootstrap-shared runtime artifacts have an explicit
  publication/freeze boundary that excludes runtime-created namespaces and
  classes.

## v2 Requirements

### Actor Runtime

- **ACT-01**: Add deep-frozen/shared heap support and `(freeze v)` for
  pointer-shareable cross-actor data.
- **ACT-02**: Add actor scheduler, tiered send, reply futures, and actor stop
  semantics.
- **ACT-03**: Migrate process-global native resources behind port actors.
- **ACT-04**: Deprecate the legacy thread API after the actor API is verified.

## Out of Scope

| Feature | Reason |
|---------|--------|
| Distributed actors / multi-process runtime | Proposal explicitly scopes work to single-process concurrency |
| Erlang-style supervision / hot code reload | Not required for the current runtime migration |
| Compile-time capability typing | Runtime-only enforcement is the approved design |
| `StringBuilder` optimization work | Deferred until immutable string semantics land and need profiling |

## Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| LIFE-01 | Phase 0 | Pending |
| PUB-01 | Phase 0 | Pending |
| PUB-02 | Phase 0 | Pending |
| PUB-03 | Phase 0 | Pending |
| THR-01 | Phase 0 | Pending |
| THR-02 | Phase 0 | Pending |
| STR-01 | Phase 0 | Pending |
| STR-02 | Phase 0 | Pending |
| BOOT-01 | Phase 0 | Pending |

**Coverage:**
- v1 requirements: 9 total
- Mapped to phases: 9
- Unmapped: 0

---
*Requirements defined: 2026-04-17*
*Last updated: 2026-04-17 after actor-design Phase 0 bootstrap*
