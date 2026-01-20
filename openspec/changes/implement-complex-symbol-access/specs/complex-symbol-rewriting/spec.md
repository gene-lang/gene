# Complex Symbol Rewriting

## ADDED Requirements

### Requirement: Complex Symbol Parsing and Segmentation
The compiler SHALL parse complex symbols with slash delimiters and split them into logical segments for rewriting.

#### Scenario: Basic two-segment class definition
**WHEN** a class definition uses a complex symbol like `geometry/Circle`
**THEN** the compiler SHALL split the symbol into segments `["geometry", "Circle"]`
**AND** rewrite the definition to use `Circle` as the identifier with `^container geometry`
**AND** the class SHALL be created in the geometry namespace.

```gene
(class geometry/Circle
  (method area _ (* /radius /radius 3.14))
)
; Compiles using stack-based approach:
; 1. Compile geometry → push to stack
; 2. Compile Circle as member of stack top (IkClassAsMember)
```

#### Scenario: Multi-segment namespace definition
**WHEN** a class definition uses a deep complex symbol like `app/models/User`
**THEN** the compiler SHALL split into segments `["app", "models", "User"]`
**AND** rewrite to use `User` as identifier with `^container app/models`
**AND** the class SHALL be created in the nested namespace structure.

```gene
(class app/models/User
  (ctor [name email]
    (/name = name)
    (/email = email)
  )
)
; Compiles using stack-based approach:
; 1. Compile app → push to stack
; 2. Compile models as member of app → push result to stack
; 3. Compile User as member of stack top (which is models)
```

#### Scenario: Variable definition with self container
**WHEN** a variable definition uses a leading slash like `/status`
**THEN** the compiler SHALL treat the leading slash as `self` container
**AND** rewrite to use `status` as identifier with `^container self`
**AND** the variable SHALL be assigned to the current instance.

```gene
(var /status "active")
; Compiles using stack-based approach:
; 1. Compile self → push to stack
; 2. Compile status as member of stack top (IkVarAsMember)
```

### Requirement: Stack-Based Container Compilation
The system SHALL compile container expressions using stack-based approach for symbol definitions.

#### Scenario: Namespace container for class
**WHEN** a complex symbol class definition like `shapes/Circle` is used within a namespace
**THEN** the container expression `shapes` SHALL be compiled and pushed to stack
**AND** the Circle class SHALL be compiled as member of stack top using IkClassAsMember
**AND** the Circle class SHALL be stored in that namespace.

```gene
(ns geometry)
(class shapes/Circle
  (method area _ (* /radius /radius 3.14))
)
; Compiles: shapes → push to stack → Circle as member of stack top
```

#### Scenario: Instance container for property
**WHEN** a class uses a leading slash in variable definition like `/value`
**THEN** the container expression `self` SHALL be compiled and pushed to stack
**AND** the value property SHALL be compiled as member of stack top
**AND** the property SHALL be accessible via instance access patterns.

```gene
(class Container
  (var /value 42)
)
; Compiles: self → push to stack → value as member of stack top
```

#### Scenario: Map container for assignment
**WHEN** a complex symbol assignment uses a map as container like `config/setting`
**THEN** the container expression `config` SHALL be compiled and pushed to stack
**AND** the setting property SHALL be set on stack top using IkSetMember
**AND** the assignment SHALL use the map's member setting mechanism.

```gene
(var config {})
(config/setting = "value")
; Compiles: config → push to stack → set member "setting" on stack top
```

### Requirement: Numeric Segment Child Access
The system SHALL detect numeric trailing segments and use child access instead of member access.

#### Scenario: Array element assignment
**WHEN** an assignment uses a numeric trailing segment like `arr/0`
**THEN** the system SHALL detect the numeric segment
**AND** use IkSetChild instead of IkSetMember for the assignment
**AND** modify the array element at the specified index.

```gene
(var arr [1 2 3])
(arr/0 = 10)
; Compiles: arr → push to stack → IkSetChild with index 0
```

#### Scenario: Gene element assignment
**WHEN** a Gene object is assigned with numeric access like `g/1`
**THEN** the system SHALL use child access for Gene elements
**AND** preserve the Gene structure while modifying the specified element.

```gene
(var g (gene (a b c)))
(g/1 = "modified")
; Compiles: g → push to stack → IkSetChild with index 1
```

### Requirement: Backward Compatibility
The complex symbol system SHALL maintain full compatibility with existing symbol access patterns.

#### Scenario: Simple symbols unchanged
**WHEN** existing code uses simple symbols without slashes
**THEN** the rewriter SHALL not modify these symbols
**AND** all existing patterns SHALL continue working exactly as before.

```gene
(class SimpleClass ...)
(var simpleVar 42)
; No rewriting applied
```

## MODIFIED Requirements

### Requirement: Variable Assignment Enhancement
Variable assignment SHALL support container-based target resolution for complex symbols.

#### Scenario: Container-based variable assignment
**WHEN** a variable assignment uses a complex symbol target
**THEN** the system SHALL evaluate the container expression
**AND** set the variable on the resulting container object
**AND** maintain proper type safety and validation.

```gene
(var container {})
(var container/value 42)
; Enhanced container expression evaluation
```

## REMOVED Requirements

No existing requirements are removed by this implementation. All current symbol access patterns remain supported with enhanced capabilities.