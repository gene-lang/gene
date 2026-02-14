## ADDED Requirements

### Requirement: Golden Style Alignment
The formatter SHALL produce output aligned with the style demonstrated in `examples/full.gene`.

#### Scenario: Canonical sample remains canonical
- **WHEN** `gene fmt --check examples/full.gene` is executed
- **THEN** the command exits successfully without rewriting the file

#### Scenario: Two-space nested indentation
- **WHEN** formatting nested forms (function/class/if/do bodies)
- **THEN** each nesting level uses exactly 2 spaces of indentation

#### Scenario: Short form retention
- **WHEN** a form is short and readable (e.g. `(var x 10)`, `(x + y)`, `(println "hello")`)
- **THEN** it remains on one line

#### Scenario: Multiline block layout
- **WHEN** a form is not suitable for one-line layout
- **THEN** output uses opening form on first line, indented body lines, and deterministic closing placement matching project style

### Requirement: Structural Text Preservation
The formatter SHALL preserve human-authored non-semantic structure.

#### Scenario: Shebang preservation
- **WHEN** input starts with a shebang line
- **THEN** shebang is preserved exactly as the first output line

#### Scenario: Comment preservation
- **WHEN** input contains comments
- **THEN** comments are preserved exactly in relative position and remain on comment lines

#### Scenario: Top-level spacing preservation
- **WHEN** input contains blank lines between top-level sections
- **THEN** blank-line section separation is preserved

### Requirement: Formatter Command Behavior
The CLI SHALL expose in-place and check-only formatting workflows.

#### Scenario: In-place formatting
- **WHEN** running `gene fmt file.gene`
- **THEN** file content is rewritten to canonical style
- **AND** exit code is `0`

#### Scenario: Check mode mismatch
- **WHEN** running `gene fmt --check file.gene` on non-canonical source
- **THEN** no file content is modified
- **AND** command exits with non-zero status

#### Scenario: Check mode canonical
- **WHEN** running `gene fmt --check file.gene` on canonical source
- **THEN** no file content is modified
- **AND** command exits with status `0`

### Requirement: Output Hygiene
Formatter output SHALL avoid trailing whitespace and be deterministic.

#### Scenario: Trailing whitespace elimination
- **WHEN** formatting any source file
- **THEN** output lines do not end with trailing spaces or tabs

#### Scenario: Deterministic output
- **WHEN** formatting the same input multiple times
- **THEN** output bytes are identical across runs
