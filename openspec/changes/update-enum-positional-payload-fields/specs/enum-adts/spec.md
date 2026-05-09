## ADDED Requirements

### Requirement: Positional and Named Enum Payload Shapes
Enum declarations SHALL allow both positional tuple-like payload variants and named record-like payload variants within the same enum, while requiring each individual variant to use exactly one payload shape.

#### Scenario: Enum mixes positional and named variants
- **WHEN** source declares `(enum E (X Int Int) (Y r: Int))`
- **THEN** `E/X` is registered as a positional payload variant with two ordered payload slots typed as `Int`
- **AND** `E/Y` is registered as a named payload variant with declared field `r` typed as `Int`
- **AND** both variants retain the nominal identity of enum `E`

#### Scenario: Variant cannot mix positional and named fields
- **WHEN** source declares a variant such as `(Bad Int r: Int)` inside an enum declaration
- **THEN** declaration checking fails with a diagnostic that names the qualified variant
- **AND** the diagnostic explains that a variant payload must be all positional or all named

#### Scenario: Positional variant construction and ordinal access
- **WHEN** source evaluates `(var x (E/X 1 2))`
- **THEN** `x/0` returns `1`
- **AND** `x/1` returns `2`
- **AND** keyword construction of `E/X` is rejected because positional slots have no declared field names

#### Scenario: Named variant construction and field access
- **WHEN** source evaluates `(var y (E/Y ^r 3))`
- **THEN** `y/r` returns `3`
- **AND** constructor validation continues to reject mixed positional and keyword calls for the named variant

### Requirement: Enum Payload Shape Pattern Binding
Enum case patterns SHALL bind payloads according to the matched variant's declared payload shape.

#### Scenario: Positional enum pattern binds by ordinal
- **WHEN** source matches `(E/X 1 2)` with `when (E/X a b)`
- **THEN** `a` is bound to `1`
- **AND** `b` is bound to `2`

#### Scenario: Named enum pattern binds by field name shorthand
- **WHEN** source matches `(E/Y ^r 3)` with `when (E/Y r)`
- **THEN** local binding `r` receives the value of field `r`

#### Scenario: Named enum pattern aliases a field binding
- **WHEN** source matches `(E/Y ^r 3)` with `when (E/Y r:rx)`
- **THEN** local binding `rx` receives the value of field `r`

#### Scenario: Pattern shape mismatch is rejected
- **WHEN** a positional variant pattern uses named field alias syntax or a named variant pattern references an unknown field
- **THEN** checking fails with a targeted enum pattern diagnostic
