## Context

GeneClaw currently bootstraps most runtime settings from environment variables
in `example-projects/geneclaw/src/config.gene`. Durable state is split across:

- process memory for hot-swap pause flags and counters
- SQLite for session memory, run tracking, scheduling, document metadata, and
  tool audit
- filesystem roots for workspace/document/artifact files

That split makes restart behavior uneven. The user-facing parts of the agent
that should survive restart, especially non-sensitive config, the system prompt,
and session memory, do not have a single canonical persisted layout.

The repository already has tree serialization support in core Gene, including
selective subtree separation via `^separate`. This change should use that
serialization model instead of inventing a second persistence format.

## Goals

- Make `GENECLAW_HOME` the canonical root for persistent GeneClaw state.
- Store non-sensitive runtime config under `GENECLAW_HOME/config` using Gene
  tree serialization.
- Store workspace state under `GENECLAW_HOME/workspace`, including the system
  prompt, sessions, and per-session memory.
- Support `{ENV:NAME:default value}` interpolation in any loaded string, with
  multiple placeholders in the same string.
- Keep secrets sourced from environment variables rather than plaintext home
  files.
- Support partial save/load so large workspaces do not require rewriting the
  full state tree.

## Non-Goals

- Replacing every existing SQLite table in v1.
- Designing a generic secret-management system beyond env placeholders.
- Adding end-user editing APIs for config or workspace in this change.
- Migrating document blobs or audit history out of SQLite in this change.
- Preserving compatibility with the old env-first config model, legacy
  `GENECLAW_WORKSPACE` layout, or SQLite-backed session memory.

## Decisions

### 1. `GENECLAW_HOME` Is the Bootstrap Root

GeneClaw should discover durable state from a single bootstrap environment
variable:

- `GENECLAW_HOME/config` contains serialized non-sensitive config
- `GENECLAW_HOME/workspace` contains serialized workspace state

For the built-in repository instance, the configured home path is:

`/Users/gcao/gene-workspace/gene-old/example-projects/geneclaw/home`

This path is a repository-local deployment choice, not a new language-level
default.

### 2. Non-Sensitive Config Moves to Serialized Home Config

`config.gene` should stop treating environment variables as the primary source
for non-sensitive runtime settings such as:

- provider choice
- model names
- reasoning or thinking level
- context-size-related limits
- request timeouts
- step/tool budgets
- document/image limits
- scheduler and pause timing knobs

Sensitive values remain environment-only:

- OpenAI keys
- Anthropic credentials
- Slack tokens/secrets
- Brave API key

Bootstrap or deployment-specific values may also remain environment-driven when
they are required before loading home config, such as `GENECLAW_HOME` itself
and process-level listen settings like `PORT`.

The old env-first config path does not need to be preserved. Obsolete settings
such as legacy workspace-root overrides can be removed instead of supported in
parallel.

### 3. Workspace Stores Prompt, Sessions, and Memory

`GENECLAW_HOME/workspace` is the durable source for agent state that should
survive restart:

- system prompt
- session catalog and metadata
- per-session conversational memory

The runtime shape should stay in Gene values. A representative logical shape is:

```gene
{
  ^system_prompt "..."
  ^sessions {
    ^default:general {
      ^workspace_id "default"
      ^channel_id "general"
      ^thread_id ""
      ^updated_at_ms 1741480000000
      ^memory [
        {^role "user" ^content "hello"}
        {^role "assistant" ^content "hi"}
      ]
    }
  }
}
```

Session memory becomes file-backed canonical state. SQLite remains in scope for
audit-oriented and operational tables in v1, such as:

- tool audit
- run tracking
- scheduled jobs
- document metadata/chunks

The old SQLite conversation-memory path does not need a compatibility bridge.
Reads and writes can move directly to workspace storage, and the legacy memory
code can be deleted.

### 4. Serialization Uses Selective Separation

The new tree serializer should be the persistence mechanism for both `config`
and `workspace`.

Expected write patterns:

- `config` is small and human-editable, so top-level values should be separated
  with a layout equivalent to `^separate [/*]`
- `workspace` should separate the root, top-level workspace sections, each
  session, and each memory entry with a layout equivalent to
  `^separate [/* /sessions/* /sessions/*/memory/*]`

This keeps unrelated sessions from being rewritten when one conversation grows.

### 5. Env Placeholder Expansion Happens After Deserialization

After loading a config or workspace tree, GeneClaw should walk the resulting
Gene value recursively and expand every string placeholder that matches:

`{ENV:NAME:default value}`

Rules:

- `NAME` is the environment variable name to read
- if the variable exists in the process environment, its value is used
- otherwise the default text after the second `:` is used
- multiple placeholders may appear in a single string
- expansion is non-recursive in v1; replacement text is not re-scanned for
  nested placeholders

This interpolation applies to loaded strings in both config and workspace so
prompts and other text can reference environment values without storing them in
cleartext home files.

### 6. Persisted Source Remains Placeholder-Friendly

The on-disk source of truth remains the serialized Gene tree, not a pre-expanded
copy. This change is intended to load placeholder-bearing files and produce an
effective runtime view without requiring secrets to be written into the home
tree.

In practice, most runtime-written workspace state will be memory/session data
that does not contain placeholders. Human-authored config and prompt content are
the main consumers of interpolation.

### 7. This Change Is a Clean Break

This change should prefer deletion over fallback:

- no dual-read logic for old and new config sources
- no compatibility mode for the old workspace-root model
- no mirroring session memory to both SQLite and workspace files

That keeps the implementation smaller and avoids a long tail of ambiguous
bootstrap behavior.

## Risks / Trade-offs

- Moving canonical session memory from SQLite to the home tree simplifies
  restart semantics but creates migration and consistency work for existing
  memory code paths.
- Env interpolation is convenient, but careless write-back of expanded values
  could leak secrets if later features edit placeholder-bearing nodes in place.
- Partial tree persistence adds loader/saver complexity, but it is necessary to
  avoid large-workspace rewrite costs.

## Migration Plan

1. Introduce home config/workspace loaders based on tree serialization.
2. Refactor `config.gene` to compute effective runtime config from serialized
   config plus env-only secrets.
3. Add workspace persistence helpers and migrate system prompt, session
   metadata, and memory reads/writes to them.
4. Delete the old env-first config path, legacy workspace-root assumptions, and
   SQLite-backed conversation-memory code.
5. Leave audit/document/scheduler SQLite tables intact in v1.
6. Update docs and tests for the built-in home layout and restart semantics.
