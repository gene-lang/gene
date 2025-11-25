## ADDED Requirements

### Requirement: Package Root Detection
The loader SHALL treat the nearest ancestor directory containing `package.gene` as the package root for any file under that tree; package imports MUST fail when no such root exists.

#### Scenario: Root found in ancestor
- **WHEN** a file `pkg/src/foo.gene` is loaded and `pkg/package.gene` exists
- **THEN** the package root is `pkg`, and subsequent module resolution uses that root

#### Scenario: Missing package.gene
- **WHEN** an import targets a package but no `package.gene` is found in the current or ancestor directories
- **THEN** the loader fails with a package resolution error before executing the import

### Requirement: Package Entrypoint Resolution
From a resolved package root, the loader SHALL select the entrypoint in the following order: `index.gene`, then `lib/index.gene`, then a prebuilt `build/index.gir` relative to the package root.

#### Scenario: Source entrypoint preferred
- **WHEN** both `index.gene` and `build/index.gir` exist under a package root
- **THEN** `index.gene` is used as the entrypoint

#### Scenario: Prebuilt GIR fallback
- **WHEN** no source entrypoint exists but `build/index.gir` is present and readable
- **THEN** the loader executes the GIR as the package entrypoint

### Requirement: Intra-Package Module Resolution
Within a package, imports without an explicit package qualifier (e.g., `(import y from "mod-y")`) SHALL resolve modules relative to the same package root using the module resolution rules of the current module system change.

#### Scenario: Same-package import
- **WHEN** `pkg/src/foo.gene` imports `(import bar from "mod-bar")` and `pkg/src/mod-bar.gene` exists
- **THEN** the resolver loads `pkg/src/mod-bar.gene` under the `pkg` package context

### Requirement: Package Import Syntax
Imports of another package’s entrypoint via `(import sym from "index" of "<package-name>")` SHALL resolve that package by name, apply entrypoint selection, and bind requested symbols into the importer.

#### Scenario: Entry point import
- **WHEN** `(import x from "index" of "org/pkg")` is evaluated and `org/pkg` resolves to a package root with an `index.gene`
- **THEN** the entrypoint executes and `x` is bound in the importer’s scope according to the export surface

### Requirement: Package Naming Rules
Package names SHALL match the regex `[a-z][a-z0-9\\-\\_\\+\\&]*[a-z0-9](/[a-z][a-z0-9\\-\\_\\+\\&]*[a-z0-9])+`, use at least two segments, and MUST NOT use reserved top-level namespaces `gene`, `genex`, or any `gene*` prefix. Top-level names `x`, `y`, and `z` remain open for general use.

#### Scenario: Valid multi-segment name
- **WHEN** a package is declared as `org/pkg-a`
- **THEN** the name is accepted as valid

#### Scenario: Reserved prefix rejected
- **WHEN** a package is declared as `gene/pkg`
- **THEN** the loader rejects it with a reserved-namespace error

## Non-MVP (Deferred)
- Package-of-packages composition and version selection (e.g., `C = A v1 + B v2`).
- Namespace registration governance and revocation messaging.
- Repository overrides/sync and dependency substitution/alias mapping mechanisms.
