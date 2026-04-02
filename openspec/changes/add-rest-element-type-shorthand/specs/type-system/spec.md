## ADDED Requirements

### Requirement: Positional Rest Element-Type Shorthand
The type system SHALL use a positional rest parameter annotation of the form `rest...: T` to mean that the bound rest value has internal type `(Array T)`.

#### Scenario: Shorthand typed rest is accepted
- **GIVEN** a function with parameters `[head: String items...: Int]`
- **WHEN** the function is type-checked
- **THEN** the rest parameter is treated as having type `(Array Int)`

#### Scenario: Shorthand typed rest validates collected elements
- **GIVEN** a function with parameters `[head: String items...: Int tail: Bool]`
- **WHEN** the function is called with `"x" 1 2 true`
- **THEN** type checking succeeds because the collected rest payload elements are all `Int`

#### Scenario: Shorthand typed rest rejects a mismatched collected element
- **GIVEN** a function with parameters `[head: String items...: Int tail: Bool]`
- **WHEN** the function is called with `"x" 1 "bad" true`
- **THEN** type checking fails because the collected rest payload contains a non-`Int` value

### Requirement: Rest Element-Type Normalization Applies To Any Type Expression
The element-type rule SHALL apply uniformly to positional rest annotations, including composite type expressions.

#### Scenario: Explicit array element type yields nested rest arrays
- **GIVEN** a function with parameters `[items...: (Array Int)]`
- **WHEN** the function is type-checked
- **THEN** the bound rest value is treated as having internal type `(Array (Array Int))`

### Requirement: Non-Rest Annotations Keep Their Existing Meaning
The shorthand rule SHALL apply only to positional rest parameters.

#### Scenario: Fixed parameters are not rewritten as arrays
- **GIVEN** a function with parameters `[item: Int rest...: Int]`
- **WHEN** the function is type-checked
- **THEN** `item` is treated as `Int`
- **AND** `rest` is treated as `(Array Int)`
