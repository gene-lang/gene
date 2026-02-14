## ADDED Requirements

### Requirement: Var Initializer Type Inference
The type checker SHALL infer a variable binding type from a `var` initializer when no explicit type annotation is present.

#### Scenario: Infer primitive literal types
- **WHEN** source contains `(var x 1)`, `(var y 1.5)`, `(var s "hello")`, or `(var b true)`
- **THEN** inferred binding types are `Int`, `Float`, `String`, and `Bool` respectively

#### Scenario: Infer nil literal type
- **WHEN** source contains `(var x nil)`
- **THEN** inferred binding type is a consistent nil-compatible type (project choice: `Nil`)

#### Scenario: Infer array and map literal types
- **WHEN** source contains `(var xs [1 2 3])` and `(var m {^a 1})`
- **THEN** inferred binding types are `(Array Int)` and `(Map Symbol Int)`

#### Scenario: Infer from known call return type
- **WHEN** source contains `(var x (some-fn ...))` and the callee return type is known
- **THEN** `x` uses the callee return type
- **AND** if unknown, `x` falls back to `Any`

### Requirement: Explicit Annotation Precedence
Explicit variable annotations SHALL override initializer-based inference.

#### Scenario: Explicit Any opt-out
- **WHEN** source contains `(var x: Any 1)`
- **THEN** binding type is `Any`
- **AND** reassignment to different runtime value types is permitted by static checking

#### Scenario: Explicit concrete type
- **WHEN** source contains `(var x: Int 1)`
- **THEN** binding type is `Int`
- **AND** assignments incompatible with `Int` are reported as type errors

### Requirement: Assignment Compatibility Uses Inferred Var Type
Assignments SHALL be checked against each variable's inferred or annotated binding type.

#### Scenario: Reassignment mismatch
- **WHEN** source contains `(var a 1)` followed by `(a = "test")`
- **THEN** the type checker reports a type mismatch against `Int`

### Requirement: Function Parameter Default Typing Unchanged
Function parameters without explicit annotations SHALL continue to default to `Any`.

#### Scenario: Unannotated parameter remains Any
- **WHEN** source defines `(fn f [x] x)`
- **THEN** parameter `x` is treated as `Any` unless annotated
