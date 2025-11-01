## ADDED Requirements

### Requirement: Module Resolution
The system SHALL resolve modules using a deterministic search order:
1) Relative path from the importing file
2) Workspace `src/` roots (configurable)
3) Precompiled GIR cache in `build/`

#### Scenario: Relative import success
- **WHEN** a module is imported via a relative path
- **THEN** the resolver loads the nearest matching file under the same directory tree

#### Scenario: GIR cache hit
- **WHEN** a compiled GIR exists and is up-to-date
- **THEN** the loader MUST reuse the GIR without recompilation

### Requirement: Import Syntax and Semantics
The language SHALL support explicit symbol imports with aliasing.

#### Scenario: Named import
- **WHEN** `(import :math [add sub])` is compiled
- **THEN** only `add` and `sub` are introduced into the local scope

#### Scenario: Aliased import
- **WHEN** `(import :math :as m)` is compiled
- **THEN** symbols are accessible via the alias `m/*`

### Requirement: Export Semantics
Modules MUST explicitly export public symbols.

#### Scenario: Selective export
- **WHEN** `(export [add sub])` is present
- **THEN** only the listed symbols are visible to importers

### Requirement: Cyclic Import Detection
The loader MUST detect cycles and produce a deterministic error.

#### Scenario: Simple cycle
- **WHEN** A imports B and B imports A
- **THEN** the loader fails with a cycle error and no partial initialization leaks into runtime

### Requirement: Module Initialization Order
The system MUST initialize modules topologically respecting dependencies.

#### Scenario: Dependency-first init
- **WHEN** module A depends on B
- **THEN** B initializes before A

