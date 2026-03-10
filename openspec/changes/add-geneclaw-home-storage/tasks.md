## 1. Implementation

- [x] 1.1 Add GeneClaw home bootstrap helpers that resolve `GENECLAW_HOME`,
      `GENECLAW_HOME/config`, and `GENECLAW_HOME/workspace`.
- [x] 1.2 Refactor `example-projects/geneclaw/src/config.gene` to load
      serialized non-sensitive config from home storage and merge in env-only
      secrets/bootstrap settings.
- [x] 1.3 Implement deep string interpolation for loaded Gene values using the
      `{ENV:NAME:default value}` placeholder syntax.
- [x] 1.4 Add workspace persistence helpers using tree serialization with
      selective separation for prompt, sessions, and per-session memory.
- [x] 1.5 Migrate GeneClaw session-memory reads and writes from SQLite-backed
      conversation storage to workspace-backed serialized state.
- [x] 1.6 Remove obsolete env-first config paths, legacy workspace-root
      assumptions, and SQLite-backed session-memory code that are superseded by
      home storage.
- [x] 1.7 Update the built-in GeneClaw example, docs, and config inspection
      paths to use the repository home at
      `/Users/gcao/gene-workspace/gene-old/example-projects/geneclaw/home`.
- [x] 1.8 Add focused Nim and GeneClaw tests for config loading, env
      interpolation, restart restoration, and selective workspace persistence.

## 2. Validation

- [x] 2.1 Run GeneClaw-focused tests that cover config and workspace restart
      behavior.
- [x] 2.2 Run any targeted Nim tests added for interpolation or serialization
      helpers.
- [x] 2.3 Validate the OpenSpec change with
      `openspec validate add-geneclaw-home-storage --strict`.
