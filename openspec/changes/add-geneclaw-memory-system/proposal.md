## Why

GeneClaw currently has per-session working memory, but it does not have a
durable long-term memory store for facts, decisions, and preferences that
should survive beyond one conversation. The reviewed design in
`example-projects/geneclaw/docs/memory_system.md` defines that missing layer.

This change implements long-term memory as an agent-owned markdown file plus a
derived embedding index under `GENECLAW_HOME/memory/`, exposed through
tool-callable read/write/search primitives.

## What Changes

- Add a GeneClaw long-term memory module backed by
  `GENECLAW_HOME/memory/MEMORY.md`.
- Add rebuildable derived index storage at `GENECLAW_HOME/memory/.index.gene`
  using OpenAI embeddings.
- Add `memory_read`, `memory_write`, and `memory_search` tools.
- Ensure `memory_search` validates the markdown hash and rebuilds the derived
  index when it is missing or stale.
- Keep long-term memory global per GeneClaw instance; one instance remains one
  workspace and one agent.
- Keep `MEMORY.md` agent-owned: users request changes through the agent rather
  than editing the file directly.

## Impact

- Affected specs:
  - `geneclaw-memory-system`
- Affected code:
  - `example-projects/geneclaw/src/home_store.gene`
  - `example-projects/geneclaw/src/config.gene`
  - `example-projects/geneclaw/src/memory.gene`
  - `example-projects/geneclaw/src/tools/memory.gene`
  - `example-projects/geneclaw/src/tools.gene`
  - `example-projects/geneclaw/tests/*`
