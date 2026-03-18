## Context

GeneClaw already persists session memory per conversation under
`GENECLAW_HOME/sessions/`, but it lacks a durable cross-session memory layer.
The detailed runtime design lives in
`example-projects/geneclaw/docs/memory_system.md`.

This OpenSpec change adopts that design with two implementation constraints:

- The long-term store is global per GeneClaw instance, not multi-tenant.
- The markdown file is agent-owned; external/manual mutation is unsupported in
  normal operation.

## Goals / Non-Goals

- Goals:
  - Add a durable long-term memory markdown store.
  - Add tool-level read/write/search access.
  - Keep embeddings as derived state that can be rebuilt from markdown.
  - Self-heal stale indexes on search.
- Non-Goals:
  - Multi-process ownership or cross-process locking.
  - Automatic promotion from session memory into long-term memory.
  - Manual user editing workflows for `MEMORY.md`.

## Decisions

- Decision: `MEMORY.md` is the source of truth and `.index.gene` is derived.
  - Rationale: keeps durable memory human-readable and rebuildable.

- Decision: long-term memory is global per GeneClaw instance.
  - Rationale: this app currently assumes one instance serves one workspace and
    one agent.

- Decision: writes and rebuilds are serialized within the process.
  - Rationale: it is enough for v1 and matches the reviewed design without
    introducing heavier cross-process coordination.

- Decision: `memory_search` validates `file_hash` before trusting the index.
  - Rationale: derived state should recover automatically after crashes or
    stale index removal.
