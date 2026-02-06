## ADDED Requirements

### Requirement: Runtime Type Enforcement for Bindings
When type checking is enabled, the runtime SHALL validate values assigned to bindings against the inferred or annotated type.

#### Scenario: Inferred var type enforced
- **WHEN** a variable is initialized with an Int and later assigned a String
- **THEN** execution raises a type error indicating the expected Int type

#### Scenario: Annotated var type enforced
- **WHEN** a variable annotated as String receives a non-String value
- **THEN** execution raises a type error indicating the expected String type

### Requirement: Runtime Union Compatibility
The runtime SHALL accept a value for a union type if it matches any member type.

#### Scenario: Union accepts any member
- **WHEN** a binding has type `(Int | String)`
- **THEN** assigning an Int or String succeeds and other types fail

### Requirement: Runtime Function Type Compatibility
The runtime SHALL treat function values as compatible with function type expressions when their arity and annotated parameter/return types are compatible, treating missing annotations as `Any`.

#### Scenario: Function signature compatibility
- **WHEN** a function value with parameter annotations `[Int Bool]` and return `String` is checked against `(Fn [Int Bool] String)`
- **THEN** it is accepted, and mismatched arity or incompatible annotations are rejected
