## ADDED Requirements

### Requirement: CLI Package Context Selection
The CLI SHALL allow package-oriented execution commands to select an explicit package context via `--pkg`, where the value is either a package name resolved by package lookup rules or a filesystem path within a package tree.

#### Scenario: Package selected by name
- **WHEN** a user runs `gene run --pkg "x/geneclaw" src/main.gene`
- **THEN** the CLI resolves `x/geneclaw` to a package root before loading `src/main.gene`

#### Scenario: Package selected by root path
- **WHEN** a user runs `gene eval --pkg ../geneclaw ...`
- **THEN** the CLI resolves the nearest ancestor containing `package.gene` from that path and uses it as the package root

### Requirement: CLI Package Context Auto-Discovery
When `--pkg` is omitted, package-oriented execution commands SHALL auto-discover package context from the current working directory or the referenced package-owned source/script file.

#### Scenario: Eval auto-discovers package from cwd
- **GIVEN** the process cwd is inside `/work/geneclaw/tools`
- **WHEN** a user runs `gene eval '(import start from "index") (start)'`
- **THEN** the eval session resolves package-local imports against `/work/geneclaw`
- **AND** `$pkg` identifies the `geneclaw` package

#### Scenario: Pipe script auto-discovers package from script path
- **GIVEN** `/work/geneclaw/tools/filter.gene` belongs to package `x/geneclaw`
- **WHEN** a user runs `gene pipe /work/geneclaw/tools/filter.gene`
- **THEN** the pipe session uses the `x/geneclaw` package context without rebasing the process cwd

### Requirement: CLI Relative Path Resolution Uses Selected Package Root
When `--pkg` is provided, relative file/script paths consumed by supported execution commands SHALL resolve from the selected package root instead of the process cwd.

#### Scenario: Run main file from another directory
- **GIVEN** the process cwd is outside the selected package
- **WHEN** a user runs `gene run --pkg "/work/geneclaw" src/main.gene`
- **THEN** `src/main.gene` resolves to `/work/geneclaw/src/main.gene`

#### Scenario: Pipe script resolved from package root
- **GIVEN** the process cwd is outside the selected package
- **WHEN** a user runs `gene pipe --pkg "/work/geneclaw" tools/filter.gene`
- **THEN** `tools/filter.gene` resolves from `/work/geneclaw`

### Requirement: Inline CLI Sessions Use Selected Package Context
When `--pkg` is provided to inline execution commands, the session SHALL behave as if its module context belongs to the selected package root so `$pkg` and package-local imports resolve from that package.

#### Scenario: Eval imports package-local module
- **WHEN** a user runs `gene eval --pkg "/work/geneclaw" '(import start from "index") (start)'`
- **THEN** the import resolves relative to the selected package root and `$pkg` identifies that package

#### Scenario: Repl starts in package context
- **WHEN** a user runs `gene repl --pkg "x/geneclaw"`
- **THEN** expressions entered in the REPL can import package-local modules without changing the process cwd

### Requirement: CLI Main Thread Exposes Application Context
Package-oriented CLI execution commands SHALL create a main-thread application object that is accessible as `$app`, and `$app.pkg` SHALL reflect the selected or discovered package context.

#### Scenario: Run exposes application package
- **WHEN** a user runs `gene run --pkg "x/geneclaw" src/main.gene`
- **THEN** `$app` is defined in the main module
- **AND** `$app.pkg.name` is `x/geneclaw`

#### Scenario: Eval auto-discovery updates application package
- **GIVEN** the process cwd is inside package `x/geneclaw`
- **WHEN** a user runs `gene eval '$app/.pkg/.name'`
- **THEN** the result is `x/geneclaw`

### Requirement: CLI Package Context Does Not Change Process Cwd
Selecting a package with `--pkg` SHALL affect package/module resolution only and SHALL NOT change the process cwd used by runtime filesystem operations.

#### Scenario: Runtime cwd remains launch directory
- **GIVEN** a user launches a package command from `/tmp/session`
- **WHEN** the command runs with `--pkg "/work/geneclaw"`
- **THEN** runtime `cwd` still reports `/tmp/session`
