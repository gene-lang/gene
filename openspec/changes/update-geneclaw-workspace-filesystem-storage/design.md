## Context

GeneClaw home storage already uses serialized Gene trees for config, the system
prompt, and per-session memory, but `db.gene` still owns several durable record
types in SQLite:

- agent runs
- tool audit events
- scheduled jobs
- document metadata and per-session document associations

That split introduces two durability models and two startup paths. It also
means restart behavior depends on which subsystem wrote the state.

## Goals / Non-Goals

- Goals:
  - Make filesystem-backed serialized storage the only durable GeneClaw home
    storage model.
  - Load the workspace tree once at initialization and lazily materialize
    high-cardinality session data.
  - Persist changed subtrees when a logical change completes so durability
    semantics are explicit without flushing on every internal mutation.
  - Keep partial rewrite behavior so a single session or record can be updated
    without rewriting the whole workspace tree.
  - Preserve restart restoration for sessions, schedules, documents, and other
    runtime records that must survive process exit.
- Non-Goals:
  - Preserve backward-compatible runtime reads from `geneclaw.sqlite`.
  - Design a generic database abstraction for GeneClaw.
  - Require automatic migration from existing SQLite files in this change.

## Decisions

- Decision: `GENECLAW_HOME/workspace` becomes the authoritative root for
  durable runtime state.
  - Rationale: the data is hierarchical, human-inspectable, and already partly
    modeled as serialized Gene trees.

- Decision: GeneClaw loads the workspace tree once at startup and uses lazy
  loading for `sessions`.
  - Startup contract:
    - eager read for config and small workspace roots
    - one `read_tree` call for workspace with lazy session descendants
      equivalent to `read_tree ^lazy [/sessions]`
    - first access to a session materializes that session subtree into memory
  - Rationale: this keeps the runtime model simple while avoiding eager parsing
    of every session at startup.

- Decision: high-churn entities are stored as independently addressable records.
  - Proposed layout:
    - `workspace/system_prompt`
    - `workspace/sessions/<session-key>`
    - `workspace/runs/<run-id>`
    - `workspace/audit/<yyyy-mm-dd>/<event-id>`
    - `workspace/scheduler/jobs/<job-id>`
    - `workspace/documents/<document-id>`
  - Rationale: a single mutation should rewrite only the affected record.
  - Notes:
    - session paths should use a filesystem-safe encoded session key
    - audit uses date partitioning because it is append-heavy and unbounded

- Decision: v1 uses explicit dirty-subtree tracking.
  - Examples:
    - `sessions/<session-key>`
    - `runs/<run-id>`
    - `scheduler/jobs/<job-id>`
    - `documents/<document-id>`
    - `audit/<yyyy-mm-dd>`
  - Rationale: the call sites are known and this avoids introducing proxy-based
    mutation tracking before the lazy tree machinery settles.

- Decision: mutating APIs write back when a logical change completes, not on
  every low-level mutation.
  - Applies to:
    - session memory after a chat turn completes
    - config edits after the edit is committed
    - scheduled jobs after create/update/remove/execute
    - tool audit after each tool execution
    - document metadata after upload/delete
    - run tracking after run completion or terminal state transition
  - Rationale: this makes durability semantics explicit and easy to reason
    about during restart or crash analysis without over-specifying internal
    mutation ordering.

- Decision: the initialized in-memory workspace tree is the live runtime model,
  while filesystem state remains the durable source for restart restoration.
  - Rationale: load-once plus explicit save points matches the desired
    operational model better than repeated read-through from disk.

- Decision: expanded placeholder values are never written back to the authored
  config or prompt files in v1.
  - Guardrails:
    - runtime writes target operational subtrees such as sessions, runs,
      scheduler, audit, and documents
    - config and system prompt write paths must preserve authored placeholder
      strings or avoid writing expanded values entirely
  - Rationale: this prevents secret leakage from `{ENV:...}` interpolation.

- Decision: manifest writes must be crash-safe.
  - Minimum requirement:
    - manifest-style files are written via temp file plus atomic rename
  - Rationale: a crash during write-back should not corrupt the workspace tree.

## Alternatives Considered

- Keep SQLite for non-session records only:
  - Rejected because it keeps two persistence contracts and does not actually
    retire SQLite.

- Use a single append-only event log:
  - Rejected for now because GeneClaw already has tree serialization helpers
  and the current access patterns are mostly key-based record reads/updates.

- Use proxy-based mutation tracking:
  - Rejected for v1 because explicit dirty tracking is simpler and the write
    sites are already concentrated.

## Risks / Trade-offs

- More small filesystem writes:
  - Mitigation: keep records narrow and independently addressable.

- Partial write failure could leave one record stale:
  - Mitigation: writes happen before success is reported, manifest files use
    atomic replacement, and tests should cover read-after-write and restart
    restoration.

- Append-heavy arrays may still rewrite manifests:
  - Mitigation: write only the affected subtree, rely on `^separate` layout for
    per-entry files, and validate whether array manifest rewrites are
    acceptable for expected session sizes.

- Loss of ad hoc SQL querying for debugging:
  - Mitigation: keep record formats human-readable and easy to inspect with
    filesystem tools.

## Migration Plan

1. Introduce filesystem-backed helpers for each durable record type.
2. Introduce startup workspace loading with lazy session descendants and
   explicit dirty-subtree tracking.
3. Switch callers from `db.gene` SQLite operations to filesystem-backed
   read/write helpers.
4. Remove SQLite bootstrap from startup and config/public config surfaces.
5. Update repository fixtures and tests to assert filesystem state instead of
   database paths or SQLite restoration.
6. Leave old `geneclaw.sqlite` files unsupported and ignorable.

## Open Questions

- Whether document lookup should keep a per-session index file or derive the
  association by scanning document records.
  A: session should store the file location and loaded only when accessed
- Whether very large session counts need a second-level partitioning strategy
  under `workspace/sessions`.
  A: not for v1
