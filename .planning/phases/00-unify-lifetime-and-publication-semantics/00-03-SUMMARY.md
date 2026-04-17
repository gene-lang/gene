---
phase: 00-unify-lifetime-and-publication-semantics
plan: 03
subsystem: infra
tags: [threading, async, callbacks, worker-vm]
requires: []
provides:
  - Per-thread reply polling now uses the caller's channel instead of thread 0
  - Target-worker callback registration for `.on_message` via a dedicated control message
  - Regression coverage for nested worker replies and remote native callback registration
affects: [phase-0, actor-runtime, thread-runtime, send_expect_reply]
tech-stack:
  added: []
  patterns:
    - "Cross-thread control messages use explicit ThreadMessageType variants"
    - "Remote callback registration is restricted to native callbacks until callable ownership is made thread-safe"
key-files:
  created: []
  modified:
    - src/gene/types/type_defs.nim
    - src/gene/vm/async_exec.nim
    - src/gene/vm/runtime_helpers.nim
    - src/gene/vm/thread_native.nim
    - tests/integration/test_thread.nim
key-decisions:
  - "Added MtRegisterCallback instead of overloading send/reply semantics"
  - "Remote on_message registration is native-function-only; same-thread function/block callbacks remain unchanged"
patterns-established:
  - "Worker-thread replies must always be polled from current_thread_id's channel"
  - "Thread-runtime regressions are covered in tests/integration/test_thread.nim with timeout-bounded awaits"
requirements-completed: [THR-01, THR-02]
duration: unknown
completed: 2026-04-17
---

# Phase 0 / Plan 00-03 Summary

**Thread replies now resolve on the caller's worker VM, and target workers can accept remote native `.on_message` registration**

## Performance

- **Duration:** not recorded
- **Started:** 2026-04-17
- **Completed:** 2026-04-17
- **Tasks:** 3
- **Files modified:** 5

## Accomplishments
- Fixed `poll_event_loop` so worker threads poll their own channel instead of hard-coding thread 0.
- Added a dedicated `MtRegisterCallback` control message so target workers can install message callbacks.
- Added regression coverage for nested worker reply polling and remote target-worker callback registration.

## Task Commits

None - changes are currently uncommitted in the working tree.

## Files Created/Modified
- `src/gene/types/type_defs.nim` - Added `MtRegisterCallback` to the thread message protocol.
- `src/gene/vm/async_exec.nim` - Switched reply polling from thread 0 to `current_thread_id`.
- `src/gene/vm/runtime_helpers.nim` - Taught the worker thread handler to consume callback-registration control messages.
- `src/gene/vm/thread_native.nim` - Routed `.on_message` to the target thread and added the native-only remote registration guard.
- `tests/integration/test_thread.nim` - Added regression tests for worker-local reply polling and remote target-worker callback registration.

## Decisions Made
- Remote `.on_message` registration is restricted to `VkNativeFn` callbacks for now because function/block values still capture thread-owned scope or frame state.
- The target-worker registration path uses an explicit control message instead of piggybacking on `MtSend`, which keeps reply semantics unchanged.

## Deviations from Plan

### Auto-fixed Issues

**1. Cross-thread callable safety narrowed during implementation**
- **Found during:** Task 2 (target-VM callback registration)
- **Issue:** Arbitrary function/block values are not safe to share across worker VMs because they capture thread-owned scope/frame state.
- **Fix:** Limited remote registration to native callbacks and left same-thread function/block registration unchanged.
- **Files modified:** `src/gene/vm/thread_native.nim`
- **Verification:** `tests/integration/test_thread.nim` passes with remote native callback registration and existing same-thread function callback tests still pass.

---

**Total deviations:** 1 auto-fixed
**Impact on plan:** Kept the runtime fix safe without weakening the targeted regression coverage.

## Issues Encountered

The `.on_message` bug was straightforward to reproduce conceptually, but the safe fix depended on callback ownership. The final implementation avoids unsafe cross-thread closure sharing while still fixing the target-worker routing bug for native callbacks.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

Thread runtime behavior is now covered for both same-thread callback handling and worker-local reply polling. The remaining independent Phase 0 entry points are still `00-01` (RC unification) and `00-02` (publication safety).

---
*Phase: 00-unify-lifetime-and-publication-semantics*
*Completed: 2026-04-17*
