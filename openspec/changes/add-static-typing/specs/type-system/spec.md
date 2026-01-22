## ADDED Requirements

### Requirement: Type Expression Syntax
The language SHALL accept type expressions as standard Gene forms, including primitives, generic constructors, unions, and function types.

#### Scenario: Generic, union, and function types parse
- **WHEN** a function is annotated with `(Result (Array User) ApiError)`, `(A | B | C)`, or `(Fn [^a A ^b B C] R)`
- **THEN** the compiler records the corresponding type expression in the AST

### Requirement: Type Annotations
The language SHALL allow type annotations on variables, function parameters, return types, and class members.

#### Scenario: Annotated function signature
- **WHEN** a function declares `[x: Int y: Int] -> Int`
- **THEN** the compiler associates `Int` types with the parameters and return

### Requirement: Keyword Parameter Types
The language SHALL allow labeled parameter types in function type signatures, and the compiler SHALL validate keyword arguments against these labels.

#### Scenario: Keyword argument type validation
- **WHEN** a function type uses `(Fn [^limit Int ^offset Int String] R)` and a call supplies keyword arguments `{^limit 10 ^offset 0}`
- **THEN** the keyword argument map is accepted and its entries are type-checked against the labeled parameter types

#### Scenario: Unknown arguments rejected
- **WHEN** a call provides a positional or keyword argument that is not declared in the function type parameter list
- **THEN** the compiler reports an argument error and rejects the call in type-check mode

### Requirement: Type Checking
The compiler SHALL type-check expressions and report a compile-time error for type mismatches or unknown types.

#### Scenario: Type mismatch
- **WHEN** an expression applies `+` to `Int` and `String`
- **THEN** the compiler reports a type error and refuses to compile in type-check mode

### Requirement: Nominal Class Types
A class name SHALL define a nominal instance type, and member access SHALL be validated against declared class members.

#### Scenario: Invalid field access
- **WHEN** a class declares fields `{^x Int}` and code accesses `obj/.y`
- **THEN** the compiler reports an unknown-field type error
