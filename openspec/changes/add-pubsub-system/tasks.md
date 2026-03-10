## 1. Runtime Model

- [ ] 1.1 Add per-VM subscription and pending-event runtime structures.
- [ ] 1.2 Represent queued events with event type, payload-presence, payload value, combine flag, and stable insertion order.
- [ ] 1.3 Add efficient pending-event lookup for coalescing without scanning the full queue on every duplicate publication.

## 2. API Surface

- [ ] 2.1 Expose `genex/pub`, `genex/sub`, and `genex/unsub` APIs.
- [ ] 2.2 Validate that event types are symbols or complex symbols.
- [ ] 2.3 Return a subscription handle from `genex/sub`, expose handle `.unsub`, and support deterministic removal via `genex/unsub`.

## 3. Scheduler Integration

- [ ] 3.1 Drain queued pub/sub events from the same scheduler authority used for async callback dispatch.
- [ ] 3.2 Ensure `genex/pub` never executes subscriber callbacks synchronously.
- [ ] 3.3 Ensure events published while draining a batch are deferred to a later scheduler cycle.

## 4. Coalescing Semantics

- [ ] 4.1 Coalesce payloadless publications on the `pub` path by event type by default.
- [ ] 4.2 Keep payloaded publications distinct by default.
- [ ] 4.3 Support `^combine true` on the `pub` path for payloaded publications using event type plus payload equality.
- [ ] 4.4 Preserve first-publication order for retained queue entries after coalescing.

## 5. Tests

- [ ] 5.1 Add tests for symbol and complex-symbol event types.
- [ ] 5.2 Add tests for payloadless coalescing.
- [ ] 5.3 Add tests proving payloaded events stay distinct by default.
- [ ] 5.4 Add tests for `^combine true` with equal and non-equal payloads.
- [ ] 5.5 Add tests for subscriber ordering, idempotent unsubscribe behavior, handle `.unsub`, and publish-during-callback deferral.
- [ ] 5.6 Add tests for snapshot semantics when callbacks subscribe or unsubscribe during delivery.
- [ ] 5.7 Add regression tests proving pub/sub callbacks use scheduler timing instead of synchronous dispatch.

## 6. Validation

- [ ] 6.1 Run targeted async, scheduler, and pub/sub tests.
- [ ] 6.2 Run `openspec validate add-pubsub-system --strict`.
