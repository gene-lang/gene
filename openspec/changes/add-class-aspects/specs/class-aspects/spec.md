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

### Requirement: Execute around advice
The system SHALL allow a single `around` advice per placeholder, receiving implicit `self`, method arguments, and a wrapped callable that can be invoked via `(call_aop wrapped ...)`.

#### Scenario: Around wraps a method
- **WHEN** an `around` advice calls `(call_aop wrapped ...)`
- **THEN** the original method runs and its return value is propagated back to the caller.
