## ADDED Requirements

### Requirement: Native Methods Expose Type Metadata
The runtime method model SHALL support optional native parameter and return type metadata for native methods.

#### Scenario: Native method registration stores metadata
- **WHEN** a class registers a native method with parameter and return type names
- **THEN** the created `Method` stores parameter name/type pairs and return type name
- **AND** registrations without explicit metadata continue to work with default metadata.

### Requirement: Type Checker Uses Native Method Metadata
The type checker SHALL consult native method metadata for known class method calls when metadata is present.

#### Scenario: Validate argument types from native metadata
- **WHEN** a method call targets a known class and the method has native parameter metadata
- **THEN** the type checker validates provided argument types against that metadata.

#### Scenario: Native method return type participates in inference
- **WHEN** a native method has return type metadata
- **THEN** the type checker uses that return type for expression typing and variable inference.
