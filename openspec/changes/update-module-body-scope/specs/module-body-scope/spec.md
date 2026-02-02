## ADDED Requirements
### Requirement: Module Body Lexical Scope
Module bodies SHALL execute in a lexical scope distinct from the module namespace.

#### Scenario: Local var does not export
- **WHEN** a module body evaluates `(var a 1)`
- **THEN** `a` is available within the module body but is not a module namespace member after initialization

#### Scenario: Local function does not export
- **WHEN** a module body evaluates `(fn f [] 1)`
- **THEN** `f` is local to the module body and is not a module namespace member unless explicitly assigned to `/f`

### Requirement: Explicit Module Namespace Writes
Module bodies SHALL allow explicit writes to the module namespace via `/`-prefixed symbols.

#### Scenario: Module member with slash-prefixed symbol
- **WHEN** a module body evaluates `(var /a 2)`
- **THEN** the module namespace exposes `a` with value `2`

### Requirement: Module Self Binding
Module initialization SHALL bind `self` to the module namespace object, regardless of whether `__init__` declares it explicitly.

#### Scenario: Explicit self parameter
- **WHEN** `__init__` is declared with `[self]` and assigns `(var /x 1)`
- **THEN** `self` refers to the module namespace and `/x` becomes a module member
