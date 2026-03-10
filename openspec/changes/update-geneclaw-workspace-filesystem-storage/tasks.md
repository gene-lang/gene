## 1. Implementation

- [x] 1.1 Define the filesystem layout for durable GeneClaw workspace records
      under `GENECLAW_HOME/workspace`, including sessions and the remaining
      runtime record types that still live in SQLite.
- [x] 1.2 Load workspace state once at startup using lazy session materialization
      for `workspace/sessions`, keeping the in-memory tree authoritative for the
      lifetime of the process.
- [x] 1.3 Refactor session persistence so a new session is materialized on
      first logical write and the changed session subtree is written when the
      turn completes.
- [x] 1.4 Add explicit dirty-subtree tracking for v1 write-back so only changed
      records are flushed for sessions, runs, schedules, audit entries, and
      documents.
- [x] 1.5 Replace SQLite-backed run, tool-audit, schedule, and document record
      persistence with filesystem-backed serialized records.
- [x] 1.6 Remove SQLite bootstrap, config surface, and runtime assumptions from
      GeneClaw home storage and startup.
- [x] 1.7 Protect placeholder-bearing config and prompt paths from write-back of
      expanded secret values.
- [x] 1.8 Update GeneClaw docs, example home fixtures, and any config/reporting
      output that still references `geneclaw.sqlite`.
- [x] 1.9 Add focused tests for restart restoration, lazy session loading, and
      save-on-change behavior, including new-session creation and turn-complete
      session writes.

## 2. Validation

- [x] 2.1 Run GeneClaw-focused tests covering workspace storage reads/writes and
      restart behavior.
- [x] 2.2 Run targeted tests for schedules, document metadata, audit/run
      records, and placeholder-safe write-back behavior after the SQLite
      removal.
- [x] 2.3 Validate the OpenSpec change with
      `openspec validate update-geneclaw-workspace-filesystem-storage --strict`.
