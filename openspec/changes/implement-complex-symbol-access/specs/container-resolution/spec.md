# Container Resolution

## ADDED Requirements

### Requirement: Container Type Support
The system SHALL support multiple container types for complex symbol resolution with appropriate member setting semantics.

#### Scenario: Namespace container for class definition
**WHEN** a class definition uses a complex symbol within a namespace context
**THEN** the container expression SHALL resolve to the appropriate namespace object
**AND** the class SHALL be stored in that namespace using the namespace's class storage mechanism
**AND** the class SHALL be accessible via the complex symbol path.

```gene
(ns geometry)
(class shapes/Circle
  (method area _ (* /radius /radius 3.14))
)
; Container geometry.shapes resolves to namespace object
```

#### Scenario: Instance container for variable assignment
**WHEN** a class defines variables with leading slash notation like `/status`
**THEN** the container expression `self` SHALL resolve to the current instance
**AND** the property SHALL be set using the instance's member assignment mechanism
**AND** the property SHALL be accessible via standard instance access.

```gene
(class Container
  (ctor _)
  (var /status "created")
)
; Container self resolves to current instance
```

### Requirement: Stack-Based Container Compilation
Container expressions SHALL be compiled using stack-based approach for symbol definitions.

#### Scenario: Dynamic container resolution
**WHEN** a container expression references a variable like `current`
**THEN** the expression SHALL be compiled and pushed to stack
**AND** the symbol SHALL be compiled as member of stack top
**AND** the compilation SHALL use proper stack management.

```gene
(var containers {:primary {} :secondary {}})
(var current "primary")
(current/setting = "value")
; Compiles: current → push to stack → set member "setting" on stack top
```

### Requirement: Container Validation
The system SHALL validate container types and provide appropriate error handling for invalid container usage.

#### Scenario: Invalid container type
**WHEN** a complex symbol assignment targets an invalid container type
**THEN** the system SHALL detect the invalid type at runtime
**AND** raise a clear error message explaining the limitation
**AND** provide guidance on valid container types.

```gene
(var number 42)
(number/property = "value")
; Runtime error - number doesn't support member assignment
```

## MODIFIED Requirements

### Requirement: Property Access Enhancement
Property access using `/` notation SHALL integrate with complex symbol resolution for consistent behavior.

#### Scenario: Property access on complex containers
**WHEN** existing property access patterns are used
**THEN** they SHALL continue working exactly as before
**AND** the complex symbol system SHALL not interfere with existing property access
**AND** mixed patterns SHALL work correctly.

```gene
(var container {:inner {:value 42}})
(container/inner/value = "updated")
; Nested property access continues working
```

## REMOVED Requirements

No existing requirements are removed by this implementation. All current variable and property access patterns remain supported with enhanced capabilities.