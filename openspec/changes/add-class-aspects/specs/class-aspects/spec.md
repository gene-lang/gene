## ADDED Requirements

### Requirement: Define a class aspect
The system SHALL allow defining a class aspect with `(aspect <Name> [<placeholder>...])` and one or more advice blocks (`before`, `after`, `before_filter`, `around`).

#### Scenario: Define a class aspect with before/after
- **WHEN** a user evaluates `(aspect A [m] (before m [x] (println x)) (after m [x] (println x)))`
- **THEN** `A` is bound to an Aspect value in the current namespace.

### Requirement: Apply a class aspect in place
The system SHALL apply a class aspect in place via `(A .apply <Class> <method-name>...)`, mapping placeholders to concrete method names.

#### Scenario: Apply to two methods
- **WHEN** `(A .apply C "m1" "m2")` is evaluated
- **THEN** method calls to `C.m1` and `C.m2` are intercepted by aspect `A`.

### Requirement: Execute before/before_filter/after advices
The system SHALL execute `before_filter`, `before`, and `after` advices in FIFO order around the original method, with implicit `self` as the first argument. After advices SHALL receive the method result as the final argument and MAY override the return value when declared with `^^replace_result`.

#### Scenario: Before filter aborts
- **WHEN** a `before_filter` advice returns `false`
- **THEN** the original method and `before`/`after` advices are not executed and the call returns `NIL`.

#### Scenario: After advice overrides result
- **WHEN** an `after` advice is declared as `(after ^^replace_result m [x result] (result + 1))`
- **THEN** the caller receives the overridden value.

### Requirement: Execute invariant advices
The system SHALL execute `invariant` advices in FIFO order immediately before the around/original call and in FIFO order immediately after it, with implicit `self` as the first argument and only the method arguments (no result argument).

#### Scenario: Invariant ordering
- **WHEN** two invariants are defined for a method and an around advice is present
- **THEN** they run in FIFO order before the around/original call and in FIFO order immediately after it, before any `after` advices.

#### Scenario: Invariants skipped on before_filter
- **WHEN** a `before_filter` advice returns `false`
- **THEN** invariant advices are not executed and the call returns `NIL`.

#### Scenario: Invariants not executed after exceptions
- **WHEN** the around/original call raises an exception
- **THEN** the post-invariant advices are not executed.

### Requirement: Reference advice callables
The system SHALL allow advice definitions to reference existing Gene or native functions using `(before <placeholder> <callable>)`, `(after <placeholder> <callable>)`, `(before_filter <placeholder> <callable>)`, `(around <placeholder> <callable>)`, or `(invariant <placeholder> <callable>)`, where the callable is resolved at aspect definition time.

#### Scenario: Callable-based before advice
- **WHEN** an aspect defines `(before m log_fn)` and `log_fn` is a function in the current namespace
- **THEN** calls to the intercepted method invoke `log_fn` with implicit `self` and the method arguments.

### Requirement: Execute around advice
The system SHALL allow a single `around` advice per placeholder, receiving implicit `self`, method arguments, and a wrapped bound method that can be invoked via `(wrapped ...)`.

#### Scenario: Around wraps a method
- **WHEN** an `around` advice calls `(wrapped ...)`
- **THEN** the original method runs and its return value is propagated back to the caller.
