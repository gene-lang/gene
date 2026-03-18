## ADDED Requirements

### Requirement: GeneClaw SHALL persist long-term memory as agent-owned markdown

GeneClaw SHALL store durable long-term memory in
`GENECLAW_HOME/memory/MEMORY.md`, and that markdown file SHALL be treated as
the canonical source of truth for long-term memory content.

#### Scenario: memory_write creates durable long-term memory

- **WHEN** the agent calls `memory_write` for a section that does not yet exist
- **THEN** GeneClaw SHALL create or update `MEMORY.md`
- **AND** the persisted markdown SHALL remain readable as plain text
- **AND** the system SHALL treat the markdown file as agent-owned durable state

### Requirement: GeneClaw SHALL maintain a rebuildable derived embedding index

GeneClaw SHALL maintain a derived embedding index for `MEMORY.md` under
`GENECLAW_HOME/memory/.index.gene`, and that index SHALL be rebuildable from
the markdown source.

#### Scenario: memory_search detects stale index state

- **WHEN** `memory_search` runs and the stored `file_hash` does not match the
  current `MEMORY.md`
- **THEN** GeneClaw SHALL rebuild the derived index before scoring results
- **AND** the rebuilt index SHALL correspond to the current markdown content

### Requirement: GeneClaw SHALL expose long-term memory tools

GeneClaw SHALL expose `memory_read`, `memory_write`, and `memory_search` as
agent tools for interacting with long-term memory.

#### Scenario: memory_read returns section markdown

- **WHEN** the agent calls `memory_read` with a section name
- **THEN** GeneClaw SHALL return the matching `##` section from `MEMORY.md`
- **AND** it SHALL not require `.index.gene` to satisfy that read

#### Scenario: memory_search is unavailable without embedding credentials

- **WHEN** the agent calls `memory_search` without usable OpenAI embedding
  credentials
- **THEN** GeneClaw SHALL return an explicit unavailable error
- **AND** `memory_read` and `memory_write` SHALL remain usable on markdown

#### Scenario: memory_search uses embedding API key, not OpenAI OAuth token

- **WHEN** the runtime has an OpenAI OAuth token for chat requests but no
  `OPENAI_EMBEDDING_API_KEY` or `OPENAI_API_KEY`
- **THEN** `memory_search` SHALL remain unavailable for embeddings
- **AND** it SHALL not attempt to treat the OAuth token as an embedding API key
