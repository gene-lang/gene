## ADDED Requirements
### Requirement: Argument Matching Baseline
Argument pattern binding SHALL reuse the current scope, allow shadowing of existing bindings, and SHALL NOT construct an aggregate object of all arguments (bindings use direct stack/child access).

#### Scenario: Bind two args without aggregate or new scope
- **GIVEN** a function `(fn f [a b] ...)` defined in a scope where `a` is already bound
- **WHEN** `f` is invoked with two positional arguments
- **THEN** `a` and `b` are bound in the current scope (existing `a` is shadowed)
- **AND** no aggregate argument object is constructed during binding

### Requirement: Match Expression Baseline
The `(match [pattern] value)` expression SHALL destructure the single `value` operand using compile-time child access into the current scope, allowing shadowing of existing bindings, and SHALL evaluate to `nil`.

#### Scenario: Destructure array into current scope
- **GIVEN** a scope with `a` already bound to `0`
- **WHEN** `(match [a b] [1 2])` executes
- **THEN** `a` is rebound to `1` and `b` is bound to `2` in the same scope (shadowing allowed)
- **AND** the expression evaluates to `nil`
- **AND** destructuring uses child-index access to the array (no matcher object or aggregate is created)
