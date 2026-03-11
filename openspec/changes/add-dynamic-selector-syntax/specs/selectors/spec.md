## ADDED Requirements

### Requirement: Dynamic Selector Path Segments
The language SHALL support `<>` inside slash-delimited path forms to mark a selector segment whose value is resolved dynamically from a slash-path fragment.

#### Scenario: Resolve a dynamic map key from a variable
- **GIVEN** a map `{^name "Ada"}` bound to `data`
- **AND** a variable `key` bound to `"name"`
- **WHEN** code evaluates `data/<key>`
- **THEN** the result SHALL be the same as `(data ./ key)`
- **AND** the result SHALL be `"Ada"`

#### Scenario: Resolve a dynamic segment from another path
- **GIVEN** a map `{^selected "name"}` bound to `state`
- **AND** a map `{^user {^name "Ada"}}` bound to `data`
- **WHEN** code evaluates `data/user/<state/selected>`
- **THEN** the inner path `state/selected` SHALL be resolved first
- **AND** the lookup SHALL return `"Ada"`

#### Scenario: Mix static and dynamic path segments
- **GIVEN** a map `{^users [{^name "Ada"} {^name "Bob"}]}` bound to `data`
- **AND** a variable `idx` bound to `1`
- **WHEN** code evaluates `data/users/<idx>/name`
- **THEN** the dynamic segment SHALL select the second array element
- **AND** the final result SHALL be `"Bob"`

### Requirement: Dynamic Selector Segment Grammar
Angle-bracket selector sugar SHALL only accept slash-path fragments inside `<>`. Arbitrary expressions SHALL continue to use the explicit dynamic lookup form.

#### Scenario: Use operator form for an arbitrary expression
- **GIVEN** an expression `(pick key)` that computes a selector at runtime
- **WHEN** user code needs to look up `data` with that expression
- **THEN** the supported form SHALL be `(data ./ (pick key))`
- **AND** `data/<(pick key)>` SHALL NOT be required to parse or compile as sugar

### Requirement: Dynamic Selector Value Validation
The runtime SHALL accept only string, symbol, or int values as resolved dynamic selector segments.

#### Scenario: Reject nil as a resolved selector segment
- **GIVEN** a variable `key` bound to `nil`
- **WHEN** code evaluates `data/<key>`
- **THEN** execution SHALL fail with an error indicating that `nil` is not a valid selector segment

#### Scenario: Reject unsupported selector result kinds
- **GIVEN** a variable `key` bound to a map value
- **WHEN** code evaluates `data/<key>`
- **THEN** execution SHALL fail with an error indicating that the resolved segment type is unsupported

### Requirement: Dynamic Method Selector Segments
The language SHALL support `a/.<path>` as sugar for zero-argument dynamic method dispatch, and argumentful dynamic method calls SHALL continue to use the explicit `(obj . expr args...)` form.

#### Scenario: Invoke a zero-argument method name from a variable
- **GIVEN** a string `"hello"` bound to `s`
- **AND** a variable `method_name` bound to `"size"`
- **WHEN** code evaluates `s/.<method_name>`
- **THEN** the method name SHALL be resolved at runtime
- **AND** the result SHALL equal the result of the corresponding static call `s/.size`

#### Scenario: Use explicit dynamic call syntax for methods with arguments
- **GIVEN** an object `obj`
- **AND** an expression `method_expr` that resolves to a method name
- **WHEN** the call needs explicit arguments
- **THEN** the supported form SHALL be `(obj . method_expr arg1 arg2)`
- **AND** the `<>` sugar SHALL remain limited to zero-argument method shorthand

### Requirement: Dynamic Method Dispatch Parity
Dynamic method calls SHALL support the same receiver kinds and dispatch behavior as static method calls.

#### Scenario: Dynamic dispatch on a value type
- **GIVEN** an array `[1 2 3]` bound to `xs`
- **AND** a variable `method_name` bound to `"size"`
- **WHEN** code evaluates `xs/.<method_name>`
- **THEN** the call SHALL succeed
- **AND** the result SHALL equal the result of the static call `xs/.size`

#### Scenario: Missing dynamic method matches static failure behavior
- **GIVEN** an object `obj`
- **AND** a variable `method_name` bound to `"does_not_exist"`
- **WHEN** code evaluates `obj/.<method_name>`
- **THEN** the runtime SHALL fail with the same missing-method behavior used by static method calls on that receiver kind
