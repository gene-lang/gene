## ADDED Requirements
### Requirement: GIR file visualization
The CLI MUST provide a `gene gir show <path>` command (alias `gene gir visualize <path>`) that renders the contents of an existing `.gir` file in a human-readable form, including header metadata and each instruction with its operands.

#### Scenario: Render GIR listing
- **GIVEN** a previously compiled Gene source that produced `build/examples/hello_world.gir`
- **WHEN** the user runs `gene gir show build/examples/hello_world.gir`
- **THEN** the command prints a header block with compiler version and VM ABI details
- **AND** prints a table or list of instructions that matches the sequence returned by `load_gir`

### Requirement: GIR visualization error handling
The CLI MUST fail with a clear error message and non-zero exit code when the requested `.gir` file is missing or invalid.

#### Scenario: Missing GIR file
- **WHEN** the user runs `gene gir show build/missing.gir`
- **THEN** the command exits with failure
- **AND** prints an error message stating that the GIR file could not be found or loaded
