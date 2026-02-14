## ADDED Requirements

### Requirement: Standard Library Module Boundaries
The standard library implementation SHALL be split into dedicated source modules under `src/gene/stdlib/` for core builtins, classes, strings, regex, JSON, collections, dates, selectors, gene meta helpers, and aspects.

#### Scenario: Module files exist
- **WHEN** source files are inspected
- **THEN** the following modules exist:
  - `src/gene/stdlib/core.nim`
  - `src/gene/stdlib/classes.nim`
  - `src/gene/stdlib/strings.nim`
  - `src/gene/stdlib/regex.nim`
  - `src/gene/stdlib/json.nim`
  - `src/gene/stdlib/collections.nim`
  - `src/gene/stdlib/dates.nim`
  - `src/gene/stdlib/selectors.nim`
  - `src/gene/stdlib/gene_meta.nim`
  - `src/gene/stdlib/aspects.nim`

### Requirement: Thin Stdlib Orchestrator
`src/gene/stdlib.nim` SHALL act as an orchestrator that imports stdlib modules and coordinates initialization order.

#### Scenario: Init path orchestrated through modules
- **WHEN** `init_stdlib` is invoked
- **THEN** stdlib initialization is performed by calling module initialization procedures
- **AND** orchestration order remains compatible with existing runtime behavior

### Requirement: Behavior Preservation During Reorganization
The reorganization SHALL preserve existing stdlib functionality.

#### Scenario: Build and tests remain green
- **WHEN** the refactor is complete
- **THEN** `nimble build` succeeds
- **AND** `./testsuite/run_tests.sh` passes without regressions

### Requirement: Incremental Extraction Safety
Each module extraction SHALL be validated before continuing.

#### Scenario: Step-wise validation
- **WHEN** a module extraction step is completed
- **THEN** `nimble build` is executed
- **AND** `./testsuite/run_tests.sh` is executed
- **AND** changes are committed before starting the next extraction step
