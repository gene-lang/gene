# Design: Scheduler-Driven Pub/Sub

## Context

Gene already has a scheduler-owned runtime path for async and callback execution, but it does not yet expose a first-class in-process event bus. The requested behavior is explicitly scheduler-driven:

- code can publish from ordinary execution contexts,
- publications do not synchronously execute subscribers,
- redundant pending events can be merged before delivery,
- callback delivery follows the same async-style scheduling rules already being standardized elsewhere.

This change therefore adds pub/sub as another scheduler-managed work source rather than a separate loop or direct call path.

## Goals

- Provide a simple in-process pub/sub API: `genex/pub`, `genex/sub`, `genex/unsub`.
- Allow publication from normal Gene execution contexts without requiring a bus object.
- Deliver subscriber callbacks through the same scheduler-owned nested VM execution path as async callbacks.
- Coalesce redundant pending events efficiently before dispatch.
- Support both simple symbols and complex symbols as event types.

## Non-Goals

- Cross-process or durable messaging.
- Wildcard, prefix, or pattern subscriptions.
- Priority queues or QoS semantics.
- A second event loop distinct from the VM scheduler.

## Decisions

### 1. API Surface

Proposed public API:

- `(genex/pub event_type)`
- `(genex/pub event_type payload)`
- `(genex/pub event_type payload ^combine true)`
- `(genex/sub event_type callback)`
- `(genex/unsub subscription_handle)`

`genex/sub` returns a subscription-handle runtime value so removal is deterministic even if multiple callbacks subscribe to the same event type. The handle exposes a no-argument `.unsub` method, and `genex/unsub` is an equivalent convenience wrapper.

`genex/unsub` is idempotent:

- removing an active handle detaches that subscription,
- removing an already-removed or unknown handle is a no-op,
- `genex/pub` returns `nil` because publication is fire-and-forget in v1.

Equivalent unsubscribe forms:

- `(genex/unsub subbed)`
- `(subbed .unsub)`
- `subbed/.unsub`

Subscriber callbacks receive a single argument:

- the provided payload for payloaded publications,
- `nil` for payloadless publications.

For coalescing purposes, any provided second positional argument counts as a payloaded publication, even when the payload value is `nil`. Code that wants payloadless combine-by-default behavior should use the one-argument `genex/pub` form.

### 2. Per-VM Queue and Registry

Pub/sub state is per VM:

- a subscription registry keyed by exact event type,
- a pending event queue owned by the scheduler,
- an auxiliary lookup structure for coalescible pending events.

Per-VM storage keeps pub/sub aligned with the existing runtime ownership model and avoids introducing cross-thread global mutation in this change.

### 3. Coalescing Model

Coalescing rules:

- payloadless publication: coalesce by exact event type by default,
- payloaded publication without `^combine true`: never coalesce by default,
- payloaded publication with `^combine true`: coalesce only when exact event type and payload are both equal.

Coalescing happens at publication time:

- `genex/pub` checks the current pending-event structures before appending a new queued entry,
- if a matching coalescible event is already pending, `genex/pub` merges into that existing pending entry instead of enqueueing another one,
- the scheduler drains an already-coalesced queue and does not perform a second deduplication pass.

Queue ordering is stable:

- the first retained occurrence determines the event's position in the pending queue,
- later publications that merge into the same pending entry do not move it.

To keep coalescing efficient, implementation should use an indexed lookup for coalescible entries and confirm payload equality with normal Gene value equality before merging.
Reference equality should be used as a fast path before falling back to structural value equality for payload comparisons.

### 4. Scheduler Integration

`genex/pub` only enqueues work and makes it visible to the scheduler. It never invokes subscribers inline.

The scheduler drains queued events through the same nested VM execution path used for async callbacks so that:

- execution context save/restore rules stay unified,
- callback timing stays consistent with async behavior,
- pub/sub does not create a second callback dispatch authority.

Publications made while the scheduler is already draining queued pub/sub events are appended to a later batch and are not re-entered into the current drain pass.

### 5. Delivery Semantics

Delivery is based on exact event-type match only. When one queued event is drained:

- a snapshot of the active subscribers for that exact type is taken at the start of that event's fan-out,
- the snapshotted subscribers are invoked in subscription order,
- each matching subscriber is invoked once for that queued event,
- coalescing affects queued events, not subscriber lists.

This keeps the model simple: one retained event fan-outs to all subscribers captured for that event. Mid-delivery `sub`/`unsub` mutations only affect later queued events.

### 6. Error Handling

This change does not introduce a separate pub/sub error model. Subscriber callback failures should use the same scheduler/nested-execution exception handling path used for async callbacks so pub/sub does not invent divergent callback behavior.

## Risks / Trade-offs

- Structural payload equality can be expensive for large payloads.
- Delivery-time batching means non-coalesced payloaded event storms can still grow the queue.
- Subscriptions persist until explicitly removed. v1 does not add weak references or bulk cleanup helpers, so long-lived code must manage `unsub` correctly to avoid subscriber leaks.

## Migration Plan

1. Add runtime types and per-VM storage for subscriptions and pending events.
2. Expose `genex/pub`, `genex/sub`, and `genex/unsub` in the `genex` namespace.
3. Integrate event draining into the scheduler callback path.
4. Add tests for coalescing, ordering, and reentrancy.

## Open Questions

- Should a future change add wildcard subscriptions such as `app/tasks/*`?
  - Not in this change.
