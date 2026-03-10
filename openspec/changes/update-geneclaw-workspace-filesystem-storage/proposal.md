## Why

GeneClaw already serializes part of its home state to the filesystem, but
durable runtime state is still split between serialized workspace trees and
`geneclaw.sqlite`. That split makes restart behavior harder to reason about,
keeps SQLite in the runtime dependency path, and leaves persistence semantics
implicit instead of defined around state mutations.

GeneClaw should use a single filesystem-backed workspace store, load that tree
once during initialization, and persist changed subtrees when a logical change
completes. SQLite can be retired for this workflow.

## What Changes

- Make `GENECLAW_HOME/workspace` the canonical durable store for GeneClaw
  workspace state.
- Load the workspace tree once at startup and lazily materialize session
  records from `GENECLAW_HOME/workspace/sessions`.
- Persist changed subtrees when a logical change completes, including new
  session creation, completed chat turns, schedule updates, document metadata
  changes, tool audit appends, and run completion.
- Move all remaining durable GeneClaw runtime records that are still stored in
  `geneclaw.sqlite` into filesystem-backed serialized records under the home
  workspace.
- Remove the SQLite requirement for GeneClaw home/workspace persistence and
  stop exposing `geneclaw.sqlite` as part of the expected runtime layout.
- Update GeneClaw docs, fixtures, and tests to reflect the filesystem-only
  storage model.

## Impact

- Affected specs:
  - `geneclaw-home-storage`
- Affected code:
  - `example-projects/geneclaw/src/home_store.gene`
  - `example-projects/geneclaw/src/workspace_state.gene`
  - `example-projects/geneclaw/src/db.gene`
  - `example-projects/geneclaw/src/config.gene`
  - `example-projects/geneclaw/src/documents.gene`
  - `example-projects/geneclaw/src/tools/schedule.gene`
  - `example-projects/geneclaw/src/main.gene`
  - GeneClaw docs and tests
- Breaking behavior:
  - `GENECLAW_HOME/geneclaw.sqlite` is no longer part of the supported GeneClaw
    storage contract.
  - GeneClaw no longer needs SQLite to restore workspace state after restart.
