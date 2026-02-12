## ADDED Requirements

### Requirement: Structured Tooling Metadata Export
The CLI SHALL expose a machine-readable metadata format suitable for AI/tooling ingestion.

#### Scenario: Compile emits metadata JSON
- **WHEN** users run `gene compile -f ai-metadata` on a module
- **THEN** output includes structured module/type/function metadata without requiring textual listing parsing

### Requirement: Descriptor-Aware Metadata
Metadata export SHALL include descriptor-driven type identity for typed callables.

#### Scenario: Typed callable metadata payload
- **WHEN** a module contains typed functions
- **THEN** metadata includes callable parameter and return `TypeId` references
