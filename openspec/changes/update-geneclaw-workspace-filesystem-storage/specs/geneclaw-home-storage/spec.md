## MODIFIED Requirements

### Requirement: GeneClaw SHALL not preserve legacy config or memory fallback paths

This change SHALL be implemented as a breaking replacement of SQLite-backed
GeneClaw workspace persistence.

#### Scenario: SQLite workspace storage is not required

- **WHEN** GeneClaw starts with valid `GENECLAW_HOME` config and workspace
  storage
- **THEN** it SHALL not require, create, or open `GENECLAW_HOME/geneclaw.sqlite`
- **AND** obsolete SQLite-backed workspace persistence code MAY be removed

### Requirement: GeneClaw SHALL persist prompt and session state in serialized workspace storage

GeneClaw SHALL store restartable workspace state exclusively under
`GENECLAW_HOME/workspace` using Gene tree serialization, including the system
prompt, session records, and session memory.

#### Scenario: System prompt is loaded from workspace storage

- **WHEN** GeneClaw starts and loads workspace state
- **THEN** it SHALL deserialize the system prompt from
  `GENECLAW_HOME/workspace`

#### Scenario: Workspace loads once with lazy sessions

- **WHEN** GeneClaw initializes workspace state
- **THEN** it SHALL load the workspace tree once at startup
- **AND** session descendants SHALL be materialized lazily on first access

#### Scenario: Session memory survives restart

- **WHEN** a session has persisted conversational memory in
  `GENECLAW_HOME/workspace`
- **AND** GeneClaw restarts
- **THEN** the session memory SHALL be loaded from workspace storage
- **AND** subsequent agent runs for that session SHALL use the restored memory

#### Scenario: New session is persisted on first logical change

- **WHEN** GeneClaw completes the first logical change for a previously unseen
  session
- **THEN** it SHALL materialize a session record under
  `GENECLAW_HOME/workspace/sessions`
- **AND** that record SHALL be durable before the operation reports success

#### Scenario: Session updates are persisted when the turn completes

- **WHEN** conversational memory or other persisted session fields change as
  part of a completed chat turn
- **THEN** GeneClaw SHALL write the updated session record to filesystem
  storage before that turn reports success
- **AND** it SHALL not defer the write to shutdown time or periodic flushing

### Requirement: Workspace persistence SHALL support partial subtree save and load

GeneClaw SHALL persist workspace records in a layout that allows unrelated
records to remain untouched when a single session or other runtime record is
updated.

#### Scenario: Session memory entries are persisted independently

- **WHEN** GeneClaw writes workspace state for a session with many memory
  entries
- **THEN** it SHALL use separated storage so session descendants and memory
  entries can be saved and loaded without rewriting unrelated sessions

#### Scenario: Non-session runtime records are independently addressable

- **WHEN** GeneClaw updates a run record, scheduled job, audit event, or
  document record
- **THEN** it SHALL persist only the affected filesystem-backed record set
- **AND** it SHALL not require a full workspace rewrite

#### Scenario: Dirty tracking identifies changed workspace subtrees

- **WHEN** GeneClaw completes a logical change that affects persisted runtime
  state
- **THEN** it SHALL identify the changed subtree explicitly before write-back
- **AND** it SHALL flush only those dirty subtrees

## ADDED Requirements

### Requirement: GeneClaw SHALL persist durable runtime records as filesystem-backed workspace data

GeneClaw SHALL store durable runtime records that were previously maintained in
SQLite as serialized filesystem-backed workspace records under
`GENECLAW_HOME/workspace`.

#### Scenario: Scheduled jobs survive restart without SQLite

- **WHEN** GeneClaw persists one or more scheduled jobs and then restarts
- **THEN** it SHALL restore those jobs from filesystem-backed workspace storage
- **AND** no SQLite database SHALL be required for that restoration

#### Scenario: Document records survive restart without SQLite

- **WHEN** GeneClaw persists document metadata or session-document associations
- **AND** the process restarts
- **THEN** GeneClaw SHALL restore that durable document state from
  filesystem-backed workspace storage

#### Scenario: Run and audit records are written as filesystem data

- **WHEN** GeneClaw creates or updates a run record or tool audit record
- **THEN** it SHALL persist that record under `GENECLAW_HOME/workspace`
- **AND** restart behavior for those records SHALL not depend on SQLite

### Requirement: GeneClaw SHALL protect placeholder-backed config and prompt values during write-back

GeneClaw SHALL not persist environment-expanded secret values back into the
authored config or system prompt files.

#### Scenario: Expanded placeholders are not written back

- **WHEN** GeneClaw loads config or prompt values that contain `{ENV:...}`
  placeholders
- **AND** runtime persistence later writes operational workspace state
- **THEN** the write-back path SHALL not replace the authored placeholder form
  with the expanded secret value on disk

### Requirement: Workspace manifest writes SHALL be crash-safe

GeneClaw SHALL write manifest-style workspace files in a way that avoids
corrupting durable state on process crash.

#### Scenario: Crash during manifest update does not corrupt prior state

- **WHEN** GeneClaw updates a manifest-style workspace file such as a separated
  array manifest
- **AND** the process crashes during that write
- **THEN** the previously committed manifest SHALL remain readable on disk
