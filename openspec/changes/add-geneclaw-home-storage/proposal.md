## Why

GeneClaw currently treats most runtime configuration as environment-only state
and mixes tool workspace paths, document storage, and agent state across
process memory and SQLite. That makes restart behavior hard to reason about and
prevents a single durable home layout for the built-in instance.

GeneClaw needs a canonical home root that persists:

- non-sensitive configuration in files
- agent workspace state such as system prompt, memory, and sessions
- secret values via environment substitution rather than on-disk plaintext

## What Changes

- Add a GeneClaw home model rooted at `GENECLAW_HOME`.
- Define `GENECLAW_HOME/config` as serialized non-sensitive configuration.
- Define `GENECLAW_HOME/workspace` as serialized agent workspace state,
  including the system prompt, memory, and sessions.
- Define environment placeholder interpolation for any loaded string using
  `{ENV:NAME:default value}` with multiple placeholders allowed per string.
- Make the built-in GeneClaw instance use
  `/Users/gcao/gene-workspace/gene-old/example-projects/geneclaw/home` as its
  configured `GENECLAW_HOME`.
- Make this a breaking replacement of the old GeneClaw config and workspace
  model, with no backward-compatibility requirement for legacy env-first config,
  legacy workspace roots, or SQLite-backed session memory.
- Make file-backed home state the canonical source for restartable GeneClaw
  config/workspace data.

## Impact

- Affected specs:
  - `geneclaw-home-storage` (new)
- Affected code:
  - `example-projects/geneclaw/src/config.gene`
  - `example-projects/geneclaw/src/agent.gene`
  - `example-projects/geneclaw/src/tools.gene`
  - `example-projects/geneclaw/src/hotswap_state.gene`
  - `example-projects/geneclaw/src/main.gene`
  - GeneClaw docs and tests
- Risk: medium
- Key risks:
  - shifting config authority from environment defaults to persisted files
  - removing legacy code paths cleanly without leaving stale assumptions in
    docs or runtime modules
  - keeping interpolation secure while avoiding accidental persistence of
    secrets
