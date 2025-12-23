## ADDED Requirements

### Requirement: REPL Session Persistence
The REPL SHALL evaluate successive inputs in a persistent session scope so variables and definitions remain available across inputs.

#### Scenario: Variable defined then reused
- **WHEN** a user starts `gene repl` and enters `(var x 1)` followed by `x`
- **THEN** the second input evaluates to `1`

### Requirement: On-Demand REPL Scope
Calling `($repl)` within running Gene code SHALL start an interactive REPL in a new child scope whose parent is the caller scope, allowing reads and updates of parent variables.

#### Scenario: Parent variable read and updated
- **WHEN** a program defines `(var x 1)` and enters `($repl)` and the user executes `(x = 2)` and then `x`
- **THEN** the REPL returns `2` and after exiting, `x` in the caller scope is `2`

### Requirement: REPL Return Value
The `($repl)` call SHALL return the last evaluated REPL expression, or `NIL` when no expression was evaluated.

#### Scenario: Return last expression
- **WHEN** the user enters `(+ 1 2)` and then exits the REPL
- **THEN** `($repl)` returns `3`

### Requirement: REPL on Error (CLI)
When `gene run` or `gene eval` is invoked with `--repl-on-error`, the runtime SHALL open an interactive REPL at the throw site before exception handling continues, with `$ex` set to the thrown exception.

#### Scenario: Break on throw and continue
- **WHEN** a program run with `gene run --repl-on-error` throws a Gene exception
- **THEN** an interactive REPL starts at the throw site with `$ex` available, and exiting the REPL resumes execution without automatically rethrowing

#### Scenario: Throw from REPL
- **WHEN** the user enters a top-level `(throw ...)` inside the repl-on-error session
- **THEN** the new exception is raised and handled by the VM as usual

#### Scenario: Resume value from REPL
- **WHEN** the repl-on-error session exits without rethrowing
- **THEN** the last evaluated REPL expression is used as the value of the original `throw` expression
