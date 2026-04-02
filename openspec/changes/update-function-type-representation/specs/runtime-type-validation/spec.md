## MODIFIED Requirements

### Requirement: Runtime Function Type Compatibility
The runtime SHALL treat function values as compatible with function type expressions when their canonical callable signatures are compatible, including fixed positional parameters, positional variadic placement, fixed keyword labels, keyword-rest value types, and explicit return types. Missing annotations SHALL continue to behave as `Any`.

#### Scenario: Mixed keyword and positional variadic signature is compatible
- **WHEN** a function value exposes the signature `(Fn [^a Int ^... String Int ... String] -> String)`
- **AND** it is checked against `(Fn [^a Int ^... String Int ... String] -> String)`
- **THEN** it is accepted

#### Scenario: Extra keywords require keyword-rest support
- **WHEN** a function value exposes the signature `(Fn [^a Int] -> String)`
- **AND** it is checked against `(Fn [^a Int ^... String] -> String)`
- **THEN** it is rejected because the function value does not accept additional keyword arguments

#### Scenario: Positional variadic placement participates in compatibility
- **WHEN** a function value exposes the signature `(Fn [Int ... String])`
- **AND** it is checked against `(Fn [Int String ...])`
- **THEN** it is rejected because the variadic segment appears in a different position

#### Scenario: Explicit `Void` return is stricter than `Any`
- **WHEN** a function value exposes the signature `(Fn -> Any)`
- **AND** it is checked against `(Fn -> Void)`
- **THEN** it is rejected because `Void` requires an explicit void-return contract
