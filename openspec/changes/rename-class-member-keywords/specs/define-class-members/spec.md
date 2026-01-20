# Define Class Members

## ADDED Requirements

### Requirement: Constructors use ctor / ctor!
The language SHALL declare constructors inside `class` bodies using `ctor` and `ctor!` forms.

#### Scenario: Regular constructor uses ctor
- **WHEN** a program defines a class with `(ctor [x y] ...)`
- **THEN** the constructor SHALL parse and be invoked by `new`.

```gene
(class Point
  (ctor [x y]
    (/x = x)
    (/y = y)
  )
)

(var p (new Point 1 2))
```

#### Scenario: Macro constructor uses ctor!
- **WHEN** a program defines a class with `(ctor! [expr] ...)`
- **THEN** the constructor SHALL parse and be invoked by `new!` with unevaluated arguments.

```gene
(class LazyPoint
  (ctor! [x y]
    (/x = x)
    (/y = y)
  )
)

(var p (new! LazyPoint x y))
```

### Requirement: Methods use method
The language SHALL declare instance methods inside `class` bodies using `method` forms.

#### Scenario: Regular method uses method
- **WHEN** a program defines `(method get_x _ /x)`
- **THEN** the method SHALL be available on instances.

```gene
(class Point
  (ctor [x] (/x = x))
  (method get_x _ /x)
)

(var p (new Point 10))
(p .get_x)
```

#### Scenario: Macro-like method
- **WHEN** a program defines `(method debug! [expr] ...)`
- **THEN** the method SHALL receive unevaluated arguments.

```gene
(class Debugger
  (method debug! [expr]
    (println expr)
    ($caller_eval expr)
  )
)
```

### Requirement: Super constructor calls use .ctor / .ctor!
The `super` form SHALL use `ctor` or `ctor!` to target parent constructors.

#### Scenario: Regular super constructor call uses .ctor
- **WHEN** a child class calls `(super .ctor x)`
- **THEN** the parent constructor SHALL be invoked with evaluated arguments.

```gene
(class Base
  (ctor [x] (/x = x))
)

(class Child < Base
  (ctor [x y]
    (super .ctor x)
    (/y = y)
  )
)
```

#### Scenario: Macro super constructor call uses .ctor!
- **WHEN** a child class calls `(super .ctor! expr)`
- **THEN** the parent macro constructor SHALL be invoked with unevaluated arguments.

```gene
(class Base
  (ctor! [expr] (/expr = expr))
)

(class Child < Base
  (ctor! [expr]
    (super .ctor! expr)
  )
)
```

#### Scenario: Bare ctor in super call is rejected
- **WHEN** a program calls `(super ctor x)` or `(super ctor! x)`
- **THEN** the compiler SHALL report an error indicating `.ctor` or `.ctor!` must be used.

### Requirement: Legacy dotted forms are rejected
The language SHALL reject legacy dotted class member forms `.ctor`, `.ctor!`, `.fn`, `.fn!`.

#### Scenario: Dotted constructor form is rejected
- **WHEN** a program defines `(.ctor [x] ...)` or `(.ctor! [x] ...)`
- **THEN** the compiler SHALL report an error indicating `ctor` or `ctor!` must be used.

#### Scenario: Dotted method form is rejected
- **WHEN** a program defines `(.fn name [args] ...)` or `(.fn! name [args] ...)`
- **THEN** the compiler SHALL report an error indicating `method` must be used.
