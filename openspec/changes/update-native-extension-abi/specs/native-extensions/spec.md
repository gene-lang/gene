## ADDED Requirements

### Requirement: Versioned Native Extension Host ABI
The runtime SHALL define a stable, versioned native extension host ABI with a C-callable extension entrypoint.

#### Scenario: Load extension through canonical entrypoint
- **GIVEN** a shared library extension exporting `gene_init`
- **AND** the extension ABI version matches the host ABI version
- **WHEN** the runtime loads the extension
- **THEN** the extension SHALL initialize successfully through the host ABI contract
- **AND** return/publish a namespace that can be imported and called from Gene code

### Requirement: ABI Version Negotiation and Rejection
The runtime SHALL reject extensions whose declared ABI version is incompatible with the host ABI version.

#### Scenario: Reject incompatible extension ABI
- **GIVEN** a shared library extension exporting `gene_init`
- **AND** the extension ABI version does not match the host ABI version
- **WHEN** the runtime loads the extension
- **THEN** loading SHALL fail deterministically with `GENE.EXT.ABI_MISMATCH`
- **AND** the error SHALL identify the extension path or module name

### Requirement: Legacy Extension Compatibility Path
The runtime SHALL preserve functionality for legacy extensions during migration by supporting legacy loader symbols when canonical ABI symbols are absent.

#### Scenario: Load legacy extension without `gene_init`
- **GIVEN** a shared library extension that exports legacy `set_globals` and `init` symbols
- **AND** does not export `gene_init`
- **WHEN** the runtime loads the extension
- **THEN** the loader SHALL use the legacy path
- **AND** the extension namespace SHALL remain usable without behavior loss relative to pre-change runtime behavior

### Requirement: Extension Load Syntax Stability
This change SHALL NOT alter user-facing syntax for loading native extensions.

#### Scenario: Native import syntax remains valid
- **WHEN** code imports a native extension using `import ... from "<path>" ^^native`
- **THEN** the import form SHALL behave the same as before the ABI migration

#### Scenario: Genex namespace access remains valid
- **WHEN** code accesses extension members via `genex/<module>/...`
- **THEN** the access path and call syntax SHALL remain unchanged

### Requirement: No Functional Regression During Static-Import Removal
Removing VM static extension imports SHALL NOT reduce available extension functionality for previously supported modules.

#### Scenario: Previously available extension API remains callable
- **GIVEN** an extension API that was available before static-import removal (for example `genex/sqlite/open`)
- **WHEN** running the same Gene program after migration
- **THEN** the API SHALL still resolve and execute successfully under dynamic loading

### Requirement: Deterministic Extension Load Diagnostics
Extension load failures SHALL produce deterministic, code-based diagnostics instead of silent fallthrough.

#### Scenario: Missing library path
- **WHEN** code requests loading an extension whose shared library file does not exist
- **THEN** the runtime SHALL fail with `GENE.EXT.LOAD_FAILED`
- **AND** include attempted lookup path details

#### Scenario: Missing required entrypoint symbol
- **WHEN** a shared library is found but required init symbols are missing
- **THEN** the runtime SHALL fail with `GENE.EXT.SYMBOL_MISSING`
- **AND** report which symbol was required

#### Scenario: Extension initialization failure
- **WHEN** extension initialization raises or returns failure
- **THEN** the runtime SHALL fail with `GENE.EXT.INIT_FAILED`
- **AND** surface extension/module context in the error

### Requirement: Shared-Library Build Contract for Core Extensions
Project extension build tooling SHALL produce predictable shared-library artifacts consumable by the runtime loader.

#### Scenario: Core extension artifacts are buildable and loadable
- **WHEN** extension build tasks are run for supported modules
- **THEN** expected library artifacts (`build/lib<name>.<ext>`) SHALL be produced
- **AND** those artifacts SHALL load through the same runtime extension loader used by imports
