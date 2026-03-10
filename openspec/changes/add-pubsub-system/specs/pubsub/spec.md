# Pub/Sub Capability Specification

## ADDED Requirements

### Requirement: `genex` Pub/Sub API
The runtime SHALL expose `genex/pub`, `genex/sub`, and `genex/unsub` functions that can be called from ordinary Gene execution contexts without requiring a separate event-bus object.

#### Scenario: Publish from ordinary Gene code
- **WHEN** `(genex/pub do_this)` is evaluated from Gene code
- **THEN** the publication SHALL be accepted without requiring any special bus instance
- **AND** `genex/pub` SHALL return without waiting for subscriber callbacks to finish

#### Scenario: Subscribe and unsubscribe
- **WHEN** `(var token (genex/sub do_this callback))` is evaluated and later `(genex/unsub token)` is called
- **THEN** `genex/sub` SHALL return a subscription handle value
- **AND** subsequent `do_this` publications SHALL NOT invoke `callback`

#### Scenario: Subscription handle supports method unsubscribe
- **WHEN** `(var subbed (genex/sub a/b callback))` returns a subscription handle
- **THEN** `(subbed .unsub)` and `subbed/.unsub` SHALL detach that subscription
- **AND** they SHALL be equivalent to `(genex/unsub subbed)`

#### Scenario: Double unsubscribe is a no-op
- **WHEN** `(genex/unsub token)` is called for a handle that has already been removed or was never active
- **THEN** the runtime SHALL treat the call as a no-op
- **AND** it SHALL NOT raise an error solely because the handle is inactive

#### Scenario: Publish returns nil
- **WHEN** `genex/pub` accepts a publication
- **THEN** it SHALL return `nil`

### Requirement: Event Type Contract
Event types used with `genex/pub` and `genex/sub` SHALL be either a symbol or a complex symbol, and matching SHALL use exact event-type equality.

#### Scenario: Simple symbol event type
- **WHEN** `(genex/sub do_this callback)` is registered and `(genex/pub do_this)` is later published
- **THEN** `callback` SHALL be considered a matching subscriber for that queued event

#### Scenario: Complex symbol event type
- **WHEN** `(genex/sub app/tasks/do_this callback)` is registered and `(genex/pub app/tasks/do_this)` is later published
- **THEN** `callback` SHALL be considered a matching subscriber for that queued event
- **AND** a different complex symbol SHALL NOT match unless it is exactly equal

#### Scenario: Invalid event type rejected
- **WHEN** `genex/pub` or `genex/sub` receives an event type that is neither a symbol nor a complex symbol
- **THEN** the runtime SHALL raise a clear runtime error instead of registering or publishing the event

### Requirement: Scheduler-Driven Delivery
Queued pub/sub events SHALL be delivered by the same scheduler-owned nested VM execution path used for async callbacks, and `genex/pub` SHALL NOT invoke subscribers synchronously.

#### Scenario: Publish returns before callback execution
- **WHEN** `(genex/pub do_this)` is called and at least one matching subscriber exists
- **THEN** no subscriber callback SHALL run before `genex/pub` returns
- **AND** delivery SHALL occur only when the scheduler drains queued events

#### Scenario: Publish during callback is deferred
- **WHEN** a subscriber callback publishes another event while the scheduler is draining the current pub/sub batch
- **THEN** the newly published event SHALL be queued for a later scheduler cycle
- **AND** it SHALL NOT be delivered re-entrantly within the same drain pass

### Requirement: Subscriber Delivery Contract
When a queued event is drained, the runtime SHALL snapshot the active subscribers for that exact event type, invoke that snapshot in subscription order, and pass the event payload as the single callback argument; payloadless publications SHALL pass `nil`.

#### Scenario: Multiple subscribers run in subscription order
- **WHEN** two callbacks subscribe to `do_this` in that order and one `do_this` event is drained
- **THEN** both callbacks SHALL be invoked once
- **AND** the first subscriber SHALL run before the second subscriber

#### Scenario: Payloadless publication passes nil
- **WHEN** `(genex/sub do_this callback)` is registered and `(genex/pub do_this)` is drained
- **THEN** `callback` SHALL receive `nil` as its single argument

#### Scenario: Payloaded publication passes payload
- **WHEN** `(genex/sub do_this callback)` is registered and `(genex/pub do_this {^id 42})` is drained
- **THEN** `callback` SHALL receive `{^id 42}` as its single argument

#### Scenario: Unsubscribe during delivery affects later events only
- **WHEN** subscribers `a`, `b`, and `c` are snapshotted for one drained `do_this` event and callback `a` unsubscribes `c`
- **THEN** `c` SHALL still be invoked for that already-draining event
- **AND** `c` SHALL NOT be invoked for later `do_this` events unless it is subscribed again

#### Scenario: Subscribe during delivery affects later events only
- **WHEN** one `do_this` event is already draining and a callback subscribes a new `d` callback to `do_this`
- **THEN** `d` SHALL NOT be invoked for that already-draining event
- **AND** `d` MAY be invoked for later `do_this` events

### Requirement: Payloadless Event Coalescing
Multiple payloadless publications of the same event type SHALL coalesce at publication time into one pending delivery before the scheduler drains them.

#### Scenario: Duplicate payloadless events combine by default
- **WHEN** `(genex/pub do_this)` is called three times before the scheduler drains queued pub/sub events
- **THEN** only one pending `do_this` delivery SHALL be retained
- **AND** each matching subscriber SHALL be invoked once for that retained event

#### Scenario: Duplicate payloadless event is merged during publish
- **WHEN** one payloadless `do_this` event is already pending and `(genex/pub do_this)` is called again
- **THEN** `genex/pub` SHALL merge with the existing pending delivery instead of enqueueing a second one
- **AND** the scheduler SHALL later drain the single retained pending delivery

### Requirement: Payloaded Event Coalescing Opt-In
Publications with a provided payload SHALL remain distinct by default. When `^combine true` is provided, publication SHALL coalesce queued publications only when both event type and payload are exactly equal.

#### Scenario: Payloaded events stay distinct by default
- **WHEN** `(genex/pub do_this {^id 42})` is called twice before the scheduler drains queued pub/sub events
- **THEN** two pending deliveries SHALL be retained by default
- **AND** each matching subscriber SHALL be invoked once for each retained delivery

#### Scenario: Equal payloaded events combine when requested
- **WHEN** `(genex/pub do_this {^id 42} ^combine true)` is called twice before the scheduler drains queued pub/sub events
- **THEN** only one pending delivery SHALL be retained

#### Scenario: Equal payloaded event is merged during publish
- **WHEN** one `(genex/pub do_this {^id 42} ^combine true)` delivery is already pending and the same publication happens again
- **THEN** `genex/pub` SHALL merge with the existing pending delivery instead of enqueueing a second one

#### Scenario: Different payloads do not combine
- **WHEN** `(genex/pub do_this {^id 42} ^combine true)` and `(genex/pub do_this {^id 43} ^combine true)` are called before the scheduler drains queued pub/sub events
- **THEN** two pending deliveries SHALL be retained because the payloads are not equal

#### Scenario: Explicit nil payload is payloaded for coalescing
- **WHEN** `(genex/pub do_this nil)` is called twice before the scheduler drains queued pub/sub events
- **THEN** two pending deliveries SHALL be retained by default
- **AND** callers that want payloadless coalescing SHALL omit the payload argument instead

### Requirement: Retained Event Ordering
The scheduler SHALL preserve the first-publication order of retained pending events after coalescing.

#### Scenario: Coalesced duplicates do not reorder the queue
- **WHEN** `(genex/pub task/a)`, `(genex/pub task/b)`, and `(genex/pub task/a)` are called before the scheduler drains queued pub/sub events
- **THEN** the retained delivery order SHALL be `task/a` followed by `task/b`
- **AND** `task/a` SHALL be delivered only once in that drain cycle
