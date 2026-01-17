## ADDED Requirements

### Requirement: Bracketed argument lists for function definitions
The language SHALL require bracketed argument lists for function definitions. The only supported forms are `(fn [args] ...)` and `(fn name [args] ...)`.

#### Scenario: Anonymous function uses bracketed args
- **WHEN** a program defines `(fn [x] (x + 1))`
- **THEN** the function SHALL parse and run with `x` as its argument.

#### Scenario: Named function uses bracketed args
- **WHEN** a program defines `(fn add [a b] (a + b))`
- **THEN** the function name and argument list SHALL be recognized.

### Requirement: Legacy function forms are rejected
The language SHALL reject legacy function-definition forms, including `fnx`, `fnx!`, `fnxx`, and `fn` definitions without bracketed argument lists.

#### Scenario: `fnx` is rejected
- **WHEN** a program defines `(fnx [x] x)` or `(fnx x x)`
- **THEN** the compiler SHALL report an error indicating `fnx` is not a valid function form.

#### Scenario: Unbracketed args are rejected
- **WHEN** a program defines `(fn add x (x + 1))`
- **THEN** the compiler SHALL report an error indicating the argument list must be an array.
