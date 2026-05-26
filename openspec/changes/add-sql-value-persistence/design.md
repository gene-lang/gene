## Context

Gene's `Value` is an 8-byte NaN-boxed `uint64` with ~90 `Vk*` kinds (`src/gene/types/type_defs.nim:14-298`). Heap-allocated kinds (`VkString`, `VkArray`, `VkMap`, `VkGene`, `VkInstance`, …) carry arbitrarily nested payloads. Today the existing SQL extensions only bind scalars and stringify the rest, which is lossy. The existing text serdes (`src/gene/serdes.nim:850+`) already round-trips the persistable kind set; what's missing is a SQL-backed *storage* layer that uses serdes as a payload format and a portable schema across SQLite/MySQL/Postgres.

Prior persistence work in this repo:
- `add-geneclaw-data-storage-tiers` — chose **filesystem text `.gene`** for app-level tiering (config, hot state, keyed records, …). Binary format and SQL were explicitly deferred. This proposal does **not** replace that work; it adds a parallel SQL-backed tier for callers who want transactional, indexable, server-managed storage.
- `replace-tree-serdes-with-file-refs` — unified filesystem serdes around `gene/serdes/read|write` and external-file refs. The same wire format is reused here.
- `add-tagged-gene-json` — JSON-with-type-tags transport. Orthogonal; not the on-disk format for this capability.

## Goals / Non-Goals

**Goals**
- One logical schema usable across SQLite, MySQL, PostgreSQL.
- Store multiple unrelated Gene values in a single database, each indexed by a unique string ID.
- Round-trip every persistable `Vk*` kind without loss.
- **Performance-critical: `put` of an inline payload (≤ `inline_threshold`) is a single prepared UPSERT round-trip. Detached-blob writes are at most three statements inside one transaction (idempotent blob upsert + value upsert + conditional orphan-cleanup of the previously-referenced blob). With `N` developer-declared `^externalize` selectors the cost is bounded by `1 + 2·N + K` statements (root upsert + per-child blob/mapping upserts + at most `K ≤ N+1` orphan-cleanup deletes for blobs whose last reference was just removed).** No application-side existence checks, no triggers, no per-update ref-count writes on the schema.
- Small payloads inline (one row, one round trip); large payloads detached and content-addressed for free deduplication.
- Seamless blob lifecycle: orphaned `gene_blobs` rows are reclaimed automatically inside `delete` and `put` (same transaction). No user-callable GC operation in v1.
- Lazy materialization on read: `get` of a detached value (or of a developer-externalized field) returns an internal lazy wrapper; the blob is fetched and decoded only on first content access. Inline values are returned fully materialized.
- Developer-declared field-level externalization: callers MAY pass `^externalize [/path …]` at `put` time to force selected sub-trees into their own `gene_blobs` rows regardless of size, mirroring the filesystem `^externalize` mechanism in `src/gene/serdes.nim`.
- Portable but honest: dialect-specific DDL templates rather than a lowest-common-denominator schema.
- A deterministic, typed error for non-persistable kinds (`VkFunction`, `VkThread`, …) — never silent loss.

**Non-Goals**
- Secondary indexes on Gene properties (`^name`, `^kind`) — separate "queryable persistence" change.
- Multi-row transaction API across `put` calls — callers needing this drop down to the underlying connection's transaction surface.
- Distributed/sharded deployments, replication, or read replicas.
- A new compact binary wire format — `inline_format` byte is reserved for it; v1 ships text only.
- Migration from filesystem-tier stores into SQL stores.
- Optimistic concurrency control on the fast path — callers needing CAS-style updates use a separate `put_if_version` call (out of scope for v1).
- User-callable `gc_blobs` API — orphan cleanup is internal to `delete`/`put`; no Gene-level GC operation in v1.

## Decisions

### Decision: Single-blob row + content-addressed sidecar table
**What:** Two tables — `gene_values` (one row per logical id, with an `inline_payload` column) and `gene_blobs` (content-addressed by `sha256` for detached payloads). A third table `gene_store_meta` carries schema version + creation metadata.

**Why:** Shredding nested Gene values into an EAV-style relational layout is conceptually appealing but loses child ordering, balloons row count for deep nesting, and forces every `get` into a recursive join. A single-blob row with the existing text serdes as payload is dramatically simpler and reuses already-tested code. Hash-addressed sidecar gives free dedup and isolates large rows from the hot row-cache.

**Alternatives considered:**
- *EAV shredding* — rejected: ordering loss, join cost, code complexity.
- *Per-kind tables* (`gene_strings`, `gene_arrays`, …) — rejected: explodes schema; doesn't help queryability without secondary indexes (out of scope).
- *Always-external blob store* (S3, filesystem) — rejected: forces an extra dependency; not portable across deployments. Kept as an *optional* mode via `gene_blobs.external_uri`.

### Decision: SHA-256 content addressing for detached blobs
**What:** `gene_blobs.sha256` is the primary key. Inserts use the dialect's upsert idiom (`INSERT OR IGNORE`, `ON CONFLICT DO NOTHING`, `INSERT IGNORE`); duplicate writes are cheap no-ops.

**Why:** Free deduplication for repeated large payloads (common in append-only history or snapshot workloads). Also produces a stable cross-database identifier for replication tooling.

**Alternatives considered:** Synthetic blob ids — rejected: no dedup, harder to verify integrity across backups.

### Decision: Configurable thresholds with sensible defaults
**What:** `inline_threshold` (default 8 KiB), `blob_threshold` (default 1 MiB), set at `open` time, overridable per `put`. Routing rule:
- `byte_size ≤ inline_threshold` → store payload inline in `gene_values.inline_payload`; `blob_sha256` is NULL.
- `inline_threshold < byte_size ≤ blob_threshold` → store payload in `gene_blobs.inline_data`; `gene_values.blob_sha256` set; `gene_values.inline_payload` is NULL.
- `byte_size > blob_threshold` → require caller to pass `^external_uri` referencing a pre-uploaded blob; `gene_blobs.inline_data` NULL, `gene_blobs.external_uri` set; otherwise raise.

**Why:** A single hard-coded threshold can't serve a 50 KiB user-config store and a 100 GiB event archive equally. Defaults are tuned for SQLite page-size (≤ 8 KiB rows stay in the row btree on default page configs) and MySQL `LONGBLOB` cost amortization.

**Alternatives considered:** Always-inline (rejected: row-cache thrash on large blobs), always-detached (rejected: extra join for tiny rows).

### Decision: Reuse `src/gene/serdes.nim` text format as v1 payload
**What:** Payload bytes are the UTF-8 text produced by `serialize(value)`. `inline_format = 0` means gene-text.

**Why:** Already exists, already tested, already supports hooks for `VkCustom`/`VkInstance`. Debuggable from a SQL prompt with `cast(inline_payload as text)`. Reserved `inline_format = 1` for a future binary format keeps the schema forward-compatible.

**Alternatives considered:** Force binary v1 — rejected: doubles the scope of this proposal, and the text format isn't the bottleneck for the workloads in scope.

### Decision: Schema is owned by `db_store`, not by user app code
**What:** `ensure_schema(conn)` is idempotent and runs forward-only DDL keyed by `gene_store_meta.schema_version`. Apps must call it (or pass `^auto_migrate true` to `open`).

**Why:** Stable contract; avoids ops surprises. Forward-only because rollback semantics for blob data are ill-defined.

### Decision: Single-statement UPSERT fast path for inline values
**What:** `put` compiles into one prepared statement per dialect that performs an idempotent upsert keyed on `id`. SQLite uses `INSERT INTO gene_values(...) VALUES(...) ON CONFLICT(id) DO UPDATE SET ...`; Postgres uses the same `ON CONFLICT (id) DO UPDATE`; MySQL uses `INSERT ... ON DUPLICATE KEY UPDATE`. The statement is prepared once at `open` and re-bound per call. For inline payloads (the common case) `put` is **one round-trip, zero reads**. For detached blobs `put` is **two to three statements** in one transaction (idempotent blob upsert + value upsert + the orphan-cleanup of the previously-referenced blob when the payload changed; see next decision).

**Why:** Read-before-write doubles round-trip count and contends on the row latch. UPSERT lets the engine collapse "exists? update : insert" into a single B-tree traversal. Prepared statements amortize parse/plan cost, which is the dominant cost on SQLite and a measurable cost on Postgres/MySQL for sub-millisecond workloads.

**Alternatives considered:**
- *Application-side `SELECT` then `UPDATE`/`INSERT`* — rejected: two round-trips, race window, no benefit.
- *Per-call ad-hoc SQL string formatting* — rejected: parse cost dominates for small payloads, also a SQL-injection surface.

### Decision: Automatic Blob Cleanup via Orphan-Check
**What:** `gene_blobs` has no `ref_count` column. Cleanup is driven by an orphan-check, not by counting. When `delete` or `put` causes a value row to stop referencing a `blob_sha256`, the same transaction issues `DELETE FROM gene_blobs WHERE sha256 = ? AND NOT EXISTS (SELECT 1 FROM gene_values WHERE blob_sha256 = ?)`. Capturing the previously-referenced hash uses `DELETE ... RETURNING blob_sha256` (SQLite 3.35+, Postgres) or `UPDATE ... RETURNING` for the put-side; MySQL 8.0 lacks `RETURNING` on DML and falls back to one extra `SELECT blob_sha256 FROM gene_values WHERE id = ?` inside the transaction.

**Why:** The user-visible contract is "delete a value, its blob goes too — no second step." Ref-count maintenance would force read-before-write on every detached `put` (to decide how to adjust the counter) and is fragile under concurrent writers and retries. The orphan-check is correct under last-writer-wins, runs inside the same transaction as the triggering mutation, and only costs extra work on the detached path. The inline fast path is unaffected — it never touches `gene_blobs` for reads or writes.

**Cost model:**
- Inline `put`: 1 statement (unchanged).
- Inline `delete`: 1 statement (unchanged).
- Detached `put`, blob unchanged: 2 statements (blob upsert + value upsert; orphan-check skipped).
- Detached `put`, blob changed (or inline ↔ detached transition): 3 statements (blob upsert + value upsert with RETURNING old hash + conditional blob delete).
- Detached `delete`: 2 statements on SQLite/Postgres (`DELETE ... RETURNING` + conditional blob delete); 3 on MySQL (`SELECT` + `DELETE` + conditional blob delete).

**Alternatives considered:**
- *Ref-count column with delta UPDATEs* — rejected: forces read-before-write on detached `put`, fragile under retries/concurrency.
- *Trigger-maintained ref-count* — rejected: not portably writable across all three dialects; hides write cost.
- *Offline-only GC (`gc_blobs` callable from Gene)* — rejected per user requirement: leaves the user managing GC, breaks the "seamless" contract.

### Decision: Lazy Materialization via `VkLazyDbValue`
**What:** `get` of a detached value (one whose payload lives in `gene_blobs`) returns a runtime-only `VkLazyDbValue` instead of a fully materialized value. The wrapper carries `(store_handle, id, blob_sha256, inline_format, original_kind, byte_size)` and resolves itself on first content access (iteration, indexing, property read, equality against a non-lazy peer, kind queries that need decoded structure). Inline values are returned fully materialized — laziness is unnecessary when the row read already brought the bytes into the client. The wrapper MUST be invisible at the user-visible Gene type system level: `(gene/kind v)` reports the cached `original_kind` (`VkMap`, `VkGene`, …), never the lazy marker.

**Why:** Detached values are large by definition. Callers often `scan`/`get` then filter on id, kind, or size without ever touching bodies. Eagerly fetching and decoding every blob in a result set wastes round-trips and CPU. Deferring that work to first contact is a straight win when the caller doesn't read the body, and zero-cost when they do (one blob fetch either way).

**Implementation sketch:**
- New `VkLazyDbValue` enum entry next to `VkInstance` in `src/gene/types/type_defs.nim`; reference-cell holds the descriptor above.
- `materialize_lazy_db(v)` in `src/genex/db_store.nim` performs `SELECT inline_data, external_uri FROM gene_blobs WHERE sha256 = ?`, decodes via the codec, and stores the resolved value back into the reference cell so subsequent accesses are O(1).
- VM accessor sites (`array_data`, `map_data`, `gene_*` field reads, equality, kind dispatch beyond the cached kind) call `materialize_lazy_db` before proceeding.
- Equality short-circuits to `true` between two `VkLazyDbValue`s with the same `(store_handle, blob_sha256)` without materializing.
- Serializing a `VkLazyDbValue` (e.g., it lands in another `put`) materializes first; on-disk payloads never contain lazy markers.

**Alternatives considered:**
- *Eager materialize inside `get`* — rejected per user requirement (L3): wastes work for filter-then-discard patterns.
- *`VkCustom`-class proxy* — rejected: exposes an implementation detail as a user-visible class; conflicts with the type-transparency requirement.
- *Lazy only at `scan` boundary, eager at `get`* — rejected: forces the caller to choose between APIs based on knowledge of payload size, which they may not have.

### Decision: No optimistic-concurrency token on the fast path
**What:** `gene_values` does not carry a `version` column. Callers who need CAS-style updates use a separate, opt-in `put_if_match` (not in v1 scope). `updated_at` is set client-side at write time as a bound parameter; no server-side trigger maintains it.

**Why:** A `version` column adds either a read-before-write (defeating the UPSERT goal) or an `UPDATE ... WHERE version = ?` plus retry loop on the caller. Most persistence callers in Gene programs are single-writer per key; the cost is not justified for v1.

### Decision: Field-Level Externalization via `^externalize` Selectors
**What:** `put` accepts an optional `^externalize` property whose value is an array of absolute child selectors (e.g., `[/avatar /history/items]`). The selector syntax, validation rules, and parser are the same ones already used by filesystem serdes in `src/gene/serdes.nim:1125-1217`:

- Selectors are absolute (the first segment is empty, i.e., they begin with `/`).
- Selectors MUST target a child — the root selector `/` is rejected.
- Empty path segments are rejected.
- Wildcard / legacy forms (`*`, `**`, `@`, `@@`, `!`) are rejected.
- Duplicate selectors are rejected.
- Selectors that strictly contain or are contained by another selector (ancestor/descendant overlap) are rejected.
- A selector that does not match any value at write time raises (matching `serdes.nim`'s "missing selector target" behavior).

For each accepted selector the codec encodes the sub-tree separately, the parent payload at that path is replaced by a stable placeholder marker (analogous to the filesystem `(read_file_ref ...)` ref), and the store writes:

1. one `gene_blobs(sha256, byte_size, inline_data)` row per externalized child (idempotent, content-addressed; identical sub-trees across different ids dedupe automatically), and
2. one `gene_value_blobs(value_id, child_path, blob_sha256)` row per externalized child, recording the mapping from this value's child path to its blob.

The parent itself is routed through the normal tier rules — it MAY remain inline in `gene_values.inline_payload` if the residual is small, or be detached into its own `gene_blobs` row if the parent residual is still large.

**Why:** Developers commonly know up front which fields are large (avatars, document bodies, embedding vectors, history lists). The threshold-only model forces them to choose between fetching the whole value or not fetching at all. Field-level externalization gives the same ergonomics the filesystem layer already gives (`(serdes/write path v ^externalize [/avatar])`) — selective laziness, free per-field dedup via content addressing, and orphan-cleanup that releases each evicted child blob independently. Reusing the `serdes.nim` selector grammar avoids inventing a second syntax for the same concept.

**Cost model with `N` selectors and `K ≤ N+1` orphaned blobs after the operation:**
- `put`: 1 statement for the root upsert + `2·N` statements for child blob and mapping upserts + `K` orphan-cleanup deletes, all in one transaction. For typical updates where the externalized children's content is unchanged, the blob upserts are no-op idempotent inserts and the mapping upserts are no-op updates; `K` is 0.
- `get`: 1 `SELECT` against `gene_values` + (if any externalized fields exist for this id) 1 batched `SELECT child_path, blob_sha256 FROM gene_value_blobs WHERE value_id = ?`. Each externalized field becomes a `VkLazyDbValue` and triggers at most one further `gene_blobs` `SELECT` on first content access.
- `delete`: 1 statement to remove the value row + 1 statement to remove all `gene_value_blobs` rows for this id + `K` orphan-cleanup deletes against `gene_blobs`.

**Alternatives considered:**
- *Auto-detection only (size thresholds, no developer hint)* — rejected: thresholds cannot distinguish "this field is large because it always is" from "this field happened to be large this time." Developers lose the ability to opt fields into lazy loading.
- *Per-store schema-level externalization rules* — rejected: forces a global decision; cannot express "the avatar field of `users` is large but the avatar field of `audit_events` is not"; harder to evolve.
- *Reusing `^external_uri` for field-level externalization* — rejected: `^external_uri` is a per-blob escape hatch for payloads above `blob_threshold`; conflating it with field-level routing would overload one mechanism with two unrelated jobs.
- *Storing externalized children as nested rows in `gene_values` keyed by `(parent_id, child_path)`* — rejected: loses content-addressed dedup, doubles the index work, and breaks the "one logical value per `gene_values` row" contract.

## Logical Schema

```
gene_store_meta
  key             TEXT/VARCHAR(64) PRIMARY KEY
  value           TEXT
  -- holds schema_version, created_at, store_uuid

gene_values
  id              TEXT/VARCHAR(255) PRIMARY KEY     -- caller-supplied or store-generated ULID
  kind            INTEGER                            -- VkKind ordinal; informational, not authoritative
  inline_format   INTEGER                            -- 0=gene-text, 1=reserved-binary
  inline_payload  BLOB/BYTEA/LONGBLOB  NULL          -- present iff blob_sha256 IS NULL
  blob_sha256     CHAR(64)             NULL          -- present iff inline_payload IS NULL
  byte_size       BIGINT                             -- payload size (post-encode), used for thresholds + stats
  updated_at      TIMESTAMP/TIMESTAMPTZ/DATETIME(6)  -- client-set at write time; no trigger

gene_blobs
  sha256          CHAR(64) PRIMARY KEY
  byte_size       BIGINT
  inline_data     BLOB/BYTEA/LONGBLOB  NULL          -- present iff external_uri IS NULL
  external_uri    TEXT                 NULL          -- e.g. file://..., s3://..., when payload is externalized

gene_value_blobs                                     -- per-field externalization mapping
  value_id        TEXT/VARCHAR(255)                  -- references gene_values.id (application-side, no FK)
  child_path      TEXT/VARCHAR(512)                  -- absolute selector, e.g. "/avatar" or "/history/items"
  blob_sha256     CHAR(64)                           -- references gene_blobs.sha256 (application-side, no FK)
  PRIMARY KEY     (value_id, child_path)
  INDEX           (blob_sha256)                      -- supports orphan-check on update/delete
```

Notes:
- `gene_values.id` is the natural primary key — clustered on SQLite/MySQL (InnoDB), btree on Postgres — so id-keyed `get`/`put` is O(log n) with no secondary lookup.
- No foreign key from `gene_values.blob_sha256` to `gene_blobs.sha256` is declared. FK checks add a per-write probe and complicate the "blob upsert + value upsert" two-statement transaction without correctness benefit (content addressing makes dangling refs harmless until GC).
- `gene_value_blobs` is empty for values written without `^externalize`. The fast inline path never touches it, and the detached-only path never touches it either; it is touched only when the caller opts in to field-level externalization. The orphan-cleanup `NOT EXISTS` predicate, however, checks both `gene_values` AND `gene_value_blobs` so a blob shared between a root payload and a different value's externalized field is correctly retained.
- No `created_at`, no `version`, no `ref_count` — every column removed from the v1 schema is one less byte to write and one less index to update on the hot path.

## Risks / Trade-offs

- **Risk:** Text serdes is larger than a packed binary format → larger rows, larger blobs.
  - *Mitigation:* `inline_format` byte reserved; binary upgrade is a non-breaking follow-up.
- **Risk:** Three dialect-specific DDLs increase maintenance burden if a fourth backend (DuckDB, etc.) lands.
  - *Mitigation:* DDLs live in one file, generated from a single Nim-side description; adding a new dialect is template work.
- **Risk:** Concurrent deletes/updates against the same id can race on the orphan-check, leaving a transiently orphaned `gene_blobs` row.
  - *Mitigation:* The orphan-check runs inside the same transaction as the value-row mutation; the race window collapses to the conventional isolation level of the underlying connection. Worst-case residue is a single orphaned row that a subsequent `put` of the same content silently re-uses (via idempotent insert) or that a future opt-in vacuum sweeps.
- **Risk:** `VkLazyDbValue` resolution errors (closed store, missing blob, network failure) surface at first access rather than at `get` time, which can confuse callers who treat `get` as the failure boundary.
  - *Mitigation:* Documented behavior; resolution errors raise the same typed errors as a direct `get` would, with the originating `id` and `sha256` in the message. Callers who need eager validation can call an explicit `materialize` on the value at the `get` site (v2; out of scope here).
- **Risk:** No optimistic-concurrency token means concurrent writers can clobber each other under last-writer-wins semantics.
  - *Mitigation:* Documented limitation. v2 may add an opt-in `put_if_match(id, expected_sha256, value)` that compiles to `UPDATE ... WHERE blob_sha256 = ?` — still one round-trip, but only for callers who need it.
- **Risk:** Prepared-statement reuse across reconnects requires re-preparation; transient connection loss hides behind it.
  - *Mitigation:* The store layer owns its own prepared-statement cache keyed by connection handle; reconnection invalidates and rebuilds the cache lazily on next `put`.
- **Risk:** MySQL build wiring may surface platform-specific link issues (libmysqlclient is OS-managed).
  - *Mitigation:* Gate the build target on a `--mysql` flag; default off until CI confirms green across Linux + macOS.
- **Risk:** Non-persistable kinds list drifts as new `Vk*` kinds land.
  - *Mitigation:* Codec computes persistability from a single allow-list table near the `Vk*` enum, with a compile-time check that every kind is either allow- or deny-listed.

## Migration Plan

This is additive; no existing data is touched. Steps:

1. Land schema + codec + SQLite driver behind `(import genex/db_store)`. No build-system changes.
2. Land Postgres driver; CI service in `docker-compose.yml` already exists for `add-postgres-client`.
3. Land MySQL driver and `buildext` wiring; gate on `--mysql` flag until CI green.
4. Document the persistable-kind matrix and threshold tuning in `docs/sql-value-persistence.md`.
5. Future change: introduce `inline_format = 1` binary payload; `gene_store_meta.schema_version` bumps and a forward-only migration runs the new codec on read (lazy upgrade — no rewrite required).

Rollback: drop the three tables; the change is self-contained.

## Open Questions

- Should `put` auto-generate ids by **ULID** (sortable, no extra index needed) or **UUIDv7**? ULID has fewer dependencies in Nim; UUIDv7 is more standard. Proposal leans ULID; flag for review.
A: ULID
- Should `scan` return Gene values eagerly or lazily? Lazy iterator matches existing Gene generator surface (`add-iteration-protocol`) but requires holding a cursor; complicates connection-pool semantics. Proposal leans lazy with explicit `close`; flag for review.
A: eagerly in v1
- Should `gc_blobs` ship in v1 (callable from Gene) or be deferred to a separate change? Proposal leans v1 so the offline-GC story is complete; flag for review.
A: Neither — orphan cleanup is automatic and runs inside `delete`/`put` (see "Automatic Blob Cleanup via Orphan-Check"). No user-callable `gc_blobs` in v1; no external DB job required.
- Should there be a published p99 latency budget for `put` on inline payloads (e.g., "≤ 100µs against in-memory SQLite, ≤ 1ms against local Postgres")? Helpful for regression detection but requires CI bench infra; flag for review.
A: deferred
