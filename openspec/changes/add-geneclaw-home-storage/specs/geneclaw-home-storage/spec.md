## ADDED Requirements

### Requirement: GeneClaw SHALL load non-sensitive runtime config from `GENECLAW_HOME`

GeneClaw SHALL treat `GENECLAW_HOME` as the bootstrap root for serialized
non-sensitive runtime config and durable workspace state.

#### Scenario: Built-in GeneClaw instance uses its repository home

- **WHEN** the built-in GeneClaw instance in this repository starts with
  `GENECLAW_HOME` configured
- **THEN** it SHALL load home state from that configured path
- **AND** the repository-provided instance SHALL use
  `/Users/gcao/gene-workspace/gene-old/example-projects/geneclaw/home` as its
  configured home location

#### Scenario: Non-sensitive config is loaded from serialized home storage

- **WHEN** GeneClaw initializes runtime config
- **THEN** it SHALL deserialize `GENECLAW_HOME/config` as Gene data
- **AND** it SHALL use that data as the canonical source for non-sensitive
  runtime settings

### Requirement: GeneClaw SHALL not preserve legacy config or memory fallback paths

This change SHALL be implemented as a breaking replacement of the old GeneClaw
config and workspace persistence model.

#### Scenario: Legacy workspace and session-memory sources are not required

- **WHEN** GeneClaw starts with valid `GENECLAW_HOME` config and workspace
  storage
- **THEN** it SHALL not require legacy `GENECLAW_WORKSPACE`-style layout or
  SQLite-backed conversation memory to restore runtime state
- **AND** obsolete fallback code paths MAY be removed

### Requirement: Sensitive configuration SHALL remain environment-sourced

GeneClaw SHALL not require secrets to be stored in serialized home config.

#### Scenario: API credentials are not read from home config

- **WHEN** GeneClaw loads its effective runtime configuration
- **THEN** provider API keys, Slack secrets or tokens, and other sensitive
  credentials SHALL be sourced from environment variables
- **AND** home config SHALL only provide non-sensitive settings or placeholder
  strings that resolve from environment values at load time

### Requirement: GeneClaw SHALL persist prompt and session state in serialized workspace storage

GeneClaw SHALL store restartable workspace state under
`GENECLAW_HOME/workspace` using Gene tree serialization.

#### Scenario: System prompt is loaded from workspace storage

- **WHEN** GeneClaw starts and loads workspace state
- **THEN** it SHALL deserialize the system prompt from
  `GENECLAW_HOME/workspace`

#### Scenario: Session memory survives restart

- **WHEN** a session has persisted conversational memory in
  `GENECLAW_HOME/workspace`
- **AND** GeneClaw restarts
- **THEN** the session memory SHALL be loaded from workspace storage
- **AND** subsequent agent runs for that session SHALL use the restored memory

### Requirement: Workspace persistence SHALL support partial subtree save and load

GeneClaw SHALL persist large config and workspace trees using separated
subtrees so unrelated state does not need to be rewritten for each update.

#### Scenario: Config stores top-level descendants separately

- **WHEN** GeneClaw writes serialized home config
- **THEN** the config tree SHALL be stored in a separated layout that keeps
  top-level config descendants individually addressable

#### Scenario: Session memory entries are persisted independently

- **WHEN** GeneClaw writes workspace state for a session with many memory
  entries
- **THEN** it SHALL use separated storage so session descendants and memory
  entries can be saved and loaded without rewriting unrelated sessions

### Requirement: Loaded strings SHALL support env placeholder interpolation

GeneClaw SHALL expand environment placeholders inside any loaded string from
serialized config or workspace values.

#### Scenario: Placeholder uses environment value when present

- **WHEN** a loaded string contains `{ENV:OPENAI_MODEL:gpt-5-mini}`
- **AND** `OPENAI_MODEL` is set in the process environment
- **THEN** the placeholder SHALL be replaced with the environment value

#### Scenario: Placeholder uses default when environment value is absent

- **WHEN** a loaded string contains `{ENV:OPENAI_MODEL:gpt-5-mini}`
- **AND** `OPENAI_MODEL` is not set in the process environment
- **THEN** the placeholder SHALL be replaced with `gpt-5-mini`

#### Scenario: Multiple placeholders appear in one string

- **WHEN** a loaded string contains multiple `{ENV:...:...}` placeholders
- **THEN** GeneClaw SHALL replace every placeholder occurrence in that string
