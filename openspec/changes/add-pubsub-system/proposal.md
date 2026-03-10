## Why

Gene has scheduler and async callback infrastructure, but it does not have a first-class in-process pub/sub mechanism. Publishers currently have to call subscribers directly or reimplement ad-hoc debounce/coalescing logic, which makes callback timing inconsistent and does unnecessary repeated work.

An efficient scheduler-owned pub/sub system would let code publish events from ordinary Gene execution contexts, defer callback delivery to the existing scheduler, and coalesce redundant pending events before they are handled.

## What Changes

- Add a runtime pub/sub capability with `genex/pub`, `genex/sub`, and `genex/unsub` APIs.
- Route pub/sub callback delivery through the same scheduler-owned nested VM execution path used for async callbacks.
- Support symbol and complex-symbol event types.
- Coalesce payloadless events by default by event type.
- Keep payloaded events distinct by default, with opt-in `^combine true` coalescing when both event type and payload are equal.
- Define deterministic ordering and reentrancy rules for queued event delivery.

## Impact

- Affected specs: `pubsub`
- Affected code:
  - `src/gene/types/type_defs.nim`
  - `src/gene/stdlib/core.nim`
  - `src/gene/vm/async_exec.nim`
  - `src/gene/vm/async.nim`
  - runtime tests covering async, scheduler, and callback behavior
- Related changes:
  - `update-vm-scheduler-loop`
  - `update-async-thread-runtime-contract`
  - `implement-complex-symbol-access`
