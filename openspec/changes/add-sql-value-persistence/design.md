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
- **Performance-critical: `put` without `^externalize` is a single prepared UPSERT against `gene_values` — one round-trip, no read-before-write, no touch of `gene_blobs` or `gene_value_blobs`, no hash. `put` with `N` `^externalize` selectors is bounded by `1 + 2·N + K` round-trips in one transaction (root value upsert + per-child blob and mapping upserts + at most `K ≤ N+1` orphan-cleanup deletes for blobs whose last reference was just removed; the prior-mapping read folds into the same CTE on SQLite/Postgres and is a separate `SELECT` on MySQL).** No application-side existence checks, no triggers, no per-update ref-count writes on the schema.
- Seamless blob lifecycle for externalized children: orphaned `gene_blobs` rows are reclaimed automatically inside `delete` and `put` (same transaction). No user-callable GC operation in v1.
- Lazy materialization on read for externalized children only: a `get` returns the root value fully materialized, with each externalized child path replaced by an internal lazy wrapper that fetches and decodes the corresponding blob on first content access.
- Developer-declared field-level externalization is the only externalization mechanism: callers MAY pass `^externalize [/path …]` at `put` time to force selected sub-trees into their own `gene_blobs` rows, mirroring the filesystem `^externalize` mechanism in `src/gene/serdes.nim`.
- Portable but honest: dialect-specific DDL templates rather than a lowest-common-denominator schema.
- A deterministic, typed error for non-persistable kinds (`VkFunction`, `VkThread`, …) — never silent loss.
- Forward-compatible schema: the v1 schema can be extended to support auto-detected leaf externalization (deferred to v2) by adding a `gene_values.blob_sha256` column behind the existing `schema_version` migration path — `gene_blobs`, `gene_value_blobs`, and `VkLazyDbValue` are reused unchanged.

**Non-Goals**
- Secondary indexes on Gene properties (`^name`, `^kind`) — separate "queryable persistence" change.
- Multi-row transaction API across `put` calls — callers needing this drop down to the underlying connection's transaction surface.
- Distributed/sharded deployments, replication, or read replicas.
- A new compact binary wire format — `inline_format` byte is reserved for it; v1 ships text only.
- Migration from filesystem-tier stores into SQL stores.
- Optimistic concurrency control on the fast path — callers needing CAS-style updates use a separate `put_if_match` call (out of scope for v1).
- User-callable `gc_blobs` API — orphan cleanup is internal to `delete`/`put`; no Gene-level GC operation in v1.
- **Size-based auto-detach of root values into a content-addressed sidecar** — v1 ships no `inline_threshold`, no root-level `blob_sha256` column, no auto-routing. Callers who know a sub-field is large declare it explicitly via `^externalize`. A future v2 may layer auto-detach for leaf `VkString`/`VkBytes`/`VkBin` over the same `gene_blobs`+`gene_value_blobs`+`VkLazyDbValue` machinery without disturbing v1 semantics.
- **`^external_uri` (pre-uploaded blob) tier** — also deferred. `gene_blobs.external_uri` is omitted from the v1 schema; the column can be added in a forward-only migration when a real pre-uploaded-blob workload appears.

## Decisions

### Decision: Always-inline root + content-addressed sidecar for externalized children only
**What:** v1 ships three tables:
- `gene_values` — one row per logical id. Holds `inline_payload` (the encoded value, always populated), `kind`, `inline_format`, `byte_size`, `updated_at`. v1 has **no** `blob_sha256` column on `gene_values`.
- `gene_blobs` — content-addressed by `sha256`. Populated **only** by `^externalize` children. v1 has **no** `external_uri` column.
- `gene_value_blobs` — `(value_id, child_path, blob_sha256)` mapping from each externalized child path back to its blob.

A fourth table `gene_store_meta` carries schema version + creation metadata so v2 can layer auto-leaf-detach by adding `gene_values.blob_sha256` (and re-adding `gene_blobs.external_uri` if needed) via the existing forward-only migration path.

**Why:** Shredding nested Gene values into an EAV-style relational layout loses child ordering, balloons row count for deep nesting, and forces every `get` into a recursive join. A single-blob row with the existing text serdes as payload is dramatically simpler and reuses already-tested code. Restricting `gene_blobs` to developer-declared externalized children removes the hidden complexity of size-driven auto-routing (threshold tuning, hash-on-every-write, prior-hash capture, two-table orphan check spanning root and child references) while preserving free dedup and lazy load for the workloads that actually need it.

**Alternatives considered:**
- *EAV shredding* — rejected: ordering loss, join cost, code complexity.
- *Per-kind tables* (`gene_strings`, `gene_arrays`, …) — rejected: explodes schema; doesn't help queryability without secondary indexes (out of scope).
- *Size-based auto-detach of root values* (the prior design) — deferred to v2. The hidden routing logic, threshold tuning, prior-hash capture, and two-table orphan check that auto-detach required carried most of v1's implementation complexity for a workload v1 has no named caller for; v2 can revisit when one appears.
- *`^external_uri` (pre-uploaded blob) escape hatch* — deferred. The column can be added in a forward-only migration when a real pre-uploaded-blob workload appears.

### Decision: SHA-256 content addressing for externalized child blobs
**What:** `gene_blobs.sha256` is the primary key. Inserts use the dialect's upsert idiom (`INSERT OR IGNORE`, `ON CONFLICT DO NOTHING`, `INSERT IGNORE`); duplicate writes are cheap no-ops. Only `^externalize` children populate `gene_blobs` in v1.

**Why:** Free deduplication for repeated child payloads (avatar shared across many user rows, repeated audit-event templates, identical embedding vectors). Also produces a stable cross-database identifier for replication tooling.

**Alternatives considered:** Synthetic blob ids — rejected: no dedup, harder to verify integrity across backups.

### Decision: Reuse `src/gene/serdes.nim` text format as v1 payload
**What:** Payload bytes are the UTF-8 text produced by `serialize(value)`. `inline_format = 0` means gene-text.

**Why:** Already exists, already tested, already supports hooks for `VkCustom`/`VkInstance`. Debuggable from a SQL prompt with `cast(inline_payload as text)`. Reserved `inline_format = 1` for a future binary format keeps the schema forward-compatible.

**Alternatives considered:** Force binary v1 — rejected: doubles the scope of this proposal, and the text format isn't the bottleneck for the workloads in scope.

### Decision: Schema is owned by `db_store`, not by user app code
**What:** `ensure_schema(conn)` is idempotent and runs forward-only DDL keyed by `gene_store_meta.schema_version`. Apps must call it (or pass `^auto_migrate true` to `open`).

**Why:** Stable contract; avoids ops surprises. Forward-only because rollback semantics for blob data are ill-defined.

### Decision: Single-statement UPSERT fast path for `put` without `^externalize`
**What:** `put` without `^externalize` compiles into one prepared statement per dialect that performs an idempotent upsert keyed on `id`. SQLite uses `INSERT INTO gene_values(...) VALUES(...) ON CONFLICT(id) DO UPDATE SET ...`; Postgres uses the same `ON CONFLICT (id) DO UPDATE`; MySQL uses `INSERT ... ON DUPLICATE KEY UPDATE`. The statement is prepared once at `open` and re-bound per call. The bound is exactly **one round-trip, zero reads** against any table — there is no prior-hash capture and no `gene_blobs`/`gene_value_blobs` touch.

**Why:** Read-before-write doubles round-trip count and contends on the row latch. UPSERT lets the engine collapse "exists? update : insert" into a single B-tree traversal. Prepared statements amortize parse/plan cost, which is the dominant cost on SQLite and a measurable cost on Postgres/MySQL for sub-millisecond workloads. Stripping the root-value `blob_sha256` column from v1 removes the need for a prior-hash CTE in the common case, keeping the fast path genuinely one statement on all three dialects.

**Alternatives considered:**
- *Application-side `SELECT` then `UPDATE`/`INSERT`* — rejected: two round-trips, race window, no benefit.
- *Per-call ad-hoc SQL string formatting* — rejected: parse cost dominates for small payloads, also a SQL-injection surface.
- *Keep the root-level `blob_sha256` column "for future use"* — rejected: forces every detached-path UPSERT through a prior-hash CTE today even though v1 has no caller for root detachment. The forward-only migration path can add the column on day one of v2 if/when leaf auto-detach lands.

### Decision: Automatic Blob Cleanup via Orphan-Check (Externalized Children Only)
**What:** `gene_blobs` has no `ref_count` column. Cleanup is driven by an orphan-check against the single referrer table that exists in v1, `gene_value_blobs`. When `delete` or `put` evicts a `(value_id, child_path)` mapping whose `blob_sha256` is no longer referenced by any remaining `gene_value_blobs` row, the same transaction issues:

```
DELETE FROM gene_blobs
WHERE sha256 = ?
  AND NOT EXISTS (SELECT 1 FROM gene_value_blobs WHERE blob_sha256 = ?)
```

The check is single-table because v1 has no `gene_values.blob_sha256` — root payloads are always inline and never reach `gene_blobs`. If v2 adds root-level detachment, the orphan-check grows a second `NOT EXISTS` clause; the v1 schema migration is purely additive (`gene_value_blobs` rows already present remain valid).

Capturing the previously-mapped child hashes on the `put` side:
- **SQLite 3.35+ / Postgres**: a single CTE in one prepared statement reads the prior `(child_path, blob_sha256)` rows for `value_id`, performs the new mapping upserts, and returns the prior set to the client in the same round-trip.
- **MySQL 8.0** (no `RETURNING` on DML, no CTE inside DML): one `SELECT child_path, blob_sha256 FROM gene_value_blobs WHERE value_id = ? FOR UPDATE` inside the same transaction, then the mapping upserts, then the conditional cleanup.

`delete` flows use `DELETE ... RETURNING blob_sha256` on SQLite 3.35+/Postgres and an explicit `SELECT ... FOR UPDATE` followed by the `DELETE` on MySQL.

**Why:** The user-visible contract is "delete a value, its externalized children go too — no second step." Ref-count maintenance would force read-before-write on every `^externalize` `put` (to decide how to adjust the counter) and is fragile under concurrent writers and retries. The orphan-check is correct under last-writer-wins, runs inside the same transaction as the triggering mutation, and only costs extra work when `^externalize` is in play. `put` without `^externalize` never touches `gene_blobs` or `gene_value_blobs`.

**Cost model (round-trips per call):**
- `put` without `^externalize`: 1 statement (UPSERT). No cleanup. No prior-hash capture.
- `delete` of an id with no externalized children: 1 statement (DELETE from `gene_values`). No cleanup, no `gene_value_blobs` touch.
- `put` with `^externalize` (`N` selectors, `K ≤ N+1` orphaned blobs after the operation): see "Field-Level Externalization" below.
- `delete` of an id with externalized children: 1 DELETE from `gene_values` + 1 DELETE from `gene_value_blobs` capturing the freed hashes (via `RETURNING` on SQLite/PG; via prior `SELECT` on MySQL) + `K` orphan-cleanup deletes against `gene_blobs`.

**Alternatives considered:**
- *Ref-count column with delta UPDATEs* — rejected: forces read-before-write on every `^externalize` `put`, fragile under retries/concurrency.
- *Trigger-maintained ref-count* — rejected: not portably writable across all three dialects; hides write cost.
- *Offline-only GC (`gc_blobs` callable from Gene)* — rejected per user requirement: leaves the user managing GC, breaks the "seamless" contract.

### Decision: Lazy Materialization via `VkLazyDbValue` (Externalized Children Only)
**What:** `get` returns the root value fully materialized from `gene_values.inline_payload`. Each externalized child path inside the returned value is a runtime-only `VkLazyDbValue` wrapper that resolves itself on first content access (iteration, indexing, property read, equality against a non-lazy peer, kind queries that need decoded structure). The wrapper carries `(store_handle, value_id, child_path, blob_sha256, inline_format, original_kind, byte_size)`. Root values are never wrapped — v1 has no root-level detachment, so the row read already brings the full root payload into the client.

Gene-level kind introspection (`(gene/kind v)`) reports the cached `original_kind` (`VkMap`, `VkGene`, …) so the wrapper is type-transparent to callers that only check the kind, and structural access transparently triggers materialization. The wrapper lives behind `REF_TAG` (the NaN-box tag for ref-cell values, `src/gene/types/core/value_ops.nim:637-638`); transparency is achieved by an explicit branch in `kind()` rather than by sharing a NaN-box tag with `VkMap` / `VkArray` / `VkGene` / `VkInstance`. The next bullet lists the exact callsites this touches.

**Why:** Externalized children are large by declaration. Callers often `scan`/`get` then filter on id, kind, or root-payload properties without ever touching the big sub-trees. Eagerly fetching and decoding every externalized blob in a result set wastes round-trips and CPU. Deferring that work to first contact is a straight win when the caller doesn't read the body, and zero-cost when they do (one blob fetch either way).

**Implementation sketch:**
- New `VkLazyDbValue` enum entry **appended at the end of `ValueKind`** in `src/gene/types/type_defs.nim` (after `VkTupleValue`), so existing ordinals — including the `gene_values.kind` integer this store will itself persist — remain stable across future appends. Reference-cell holds the descriptor above.
- `materialize_lazy_db(v)` in `src/genex/db_store.nim` performs `SELECT inline_data FROM gene_blobs WHERE sha256 = ?`, decodes via the codec, and atomically replaces the wrapper's reference-cell contents with the resolved value so subsequent accesses are O(1). (v1 omits `external_uri`; v2 may add it to the SELECT once the column is reintroduced.)
- `kind()` in `src/gene/types/core/value_ops.nim` is extended with a single branch: when a `REF_TAG` value has `v.ref.kind == VkLazyDbValue`, return the cached `original_kind` instead. This is the only edit to the introspection hot path; all other `case v.kind` callers see the original kind.
- Structural accessors `array_data` / `map_data` / `gene_*` field reads, which today dispatch on the NaN-box tag (`value_ops.nim:95-160`), are upgraded so that a `VkLazyDbValue` argument calls `materialize_lazy_db` first and then re-binds through the materialized value. The hot non-lazy path remains a single tag check; the additional branch predicts trivially.
- Equality (mirroring `materialize_custom_value` at `value_ops.nim:431-436`) short-circuits to `true` between two `VkLazyDbValue`s with the same `(store_handle, blob_sha256)` without materializing either side, and materializes both sides for any other comparison.
- Serializing a `VkLazyDbValue` (e.g., it lands in another `put`) materializes first; on-disk payloads never contain lazy markers.
- `(genex/db_store/materialize v)` is exposed as an explicit escape hatch for callers who need eager error surfacing or who want to release the store handle without retaining live wrappers.

**Alternatives considered:**
- *Eager materialize inside `get`* — rejected per user requirement (L3): wastes work for filter-then-discard patterns.
- *`VkCustom`-class proxy* — rejected: exposes an implementation detail as a user-visible class; conflicts with the type-transparency requirement.
- *Lazy only at `scan` boundary, eager at `get`* — rejected: forces the caller to choose between APIs based on knowledge of payload size, which they may not have.
- *Full NaN-box-tag transparency (a lazy wrapper that masquerades as ARRAY_TAG / MAP_TAG / GENE_TAG)* — rejected: would require reserving distinct lazy NaN-box tags per shape, doubling the tag space and forcing every fast-path tag check in `kind()` and friends to also test a "lazy variant" bit. The REF_TAG + `kind()` branch above achieves the same user-visible transparency at a fraction of the implementation cost.

### Decision: No optimistic-concurrency token on the fast path
**What:** `gene_values` does not carry a `version` column. Callers who need CAS-style updates use a separate, opt-in `put_if_match(id, expected_blob_sha256, value)` call (not in v1 scope; the name matches the deferred risk-mitigation note below and replaces the earlier working name `put_if_version`). `updated_at` is set client-side at write time as a bound parameter; no server-side trigger maintains it.

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

The parent (root with placeholders substituted) is always stored inline in `gene_values.inline_payload`. v1 has no root-level detachment, so a parent whose residual size still exceeds the backend's row-size limit MUST be split further by the caller via additional `^externalize` selectors — there is no implicit fallback to a blob.

**Why:** Developers commonly know up front which fields are large (avatars, document bodies, embedding vectors, history lists). The threshold-only model forces them to choose between fetching the whole value or not fetching at all. Field-level externalization gives the same ergonomics the filesystem layer already gives (`(serdes/write path v ^externalize [/avatar])`) — selective laziness, free per-field dedup via content addressing, and orphan-cleanup that releases each evicted child blob independently. Reusing the `serdes.nim` selector grammar avoids inventing a second syntax for the same concept.

**Cost model with `N` selectors and `K ≤ N+1` orphaned blobs after the operation (round-trips, all in one transaction):**
- `put`: 1 prior-mapping `SELECT` to capture the per-child blob hashes that may become orphans + 1 root value upsert + `2·N` child blob and `gene_value_blobs` mapping upserts + `K` orphan-cleanup `DELETE`s that test `NOT EXISTS` against `gene_value_blobs.blob_sha256`. On SQLite/Postgres the prior-mapping read folds into a CTE with the root upsert and does not add a round-trip; on MySQL it is a separate statement. For typical updates where the externalized children's content is unchanged, every blob and mapping upsert collapses to a no-op via the dialect's idempotent insert idiom and `K` is 0.
- `get`: 1 `SELECT` against `gene_values` + (if any externalized fields exist for this id) 1 batched `SELECT child_path, blob_sha256 FROM gene_value_blobs WHERE value_id = ?`. Each externalized field becomes a `VkLazyDbValue` and triggers at most one further `gene_blobs` `SELECT` on first content access.
- `delete`: 1 root value `DELETE` + 1 `DELETE` of all `gene_value_blobs` rows for this id (capturing per-child blob hashes via `RETURNING` on SQLite/Postgres; via a prior `SELECT` on MySQL) + `K` orphan-cleanup deletes against `gene_blobs`, each checking `gene_value_blobs.blob_sha256`.

**Alternatives considered:**
- *Auto-detection only (size thresholds, no developer hint)* — deferred to v2 as a leaf-only extension; for v1 the developer hint is the only mechanism. Thresholds cannot distinguish "this field is large because it always is" from "this field happened to be large this time."
- *Per-store schema-level externalization rules* — rejected: forces a global decision; cannot express "the avatar field of `users` is large but the avatar field of `audit_events` is not"; harder to evolve.
- *`^external_uri` (pre-uploaded blob) tier* — deferred. The column can be added in a forward-only migration when a real pre-uploaded-blob workload appears; v1 ships neither the column nor the keyword.
- *Storing externalized children as nested rows in `gene_values` keyed by `(parent_id, child_path)`* — rejected: loses content-addressed dedup, doubles the index work, and breaks the "one logical value per `gene_values` row" contract.

## Logical Schema

```
gene_store_meta
  key             TEXT/VARCHAR(64) PRIMARY KEY
  value           TEXT
  -- holds schema_version, created_at, store_uuid

gene_values
  id              TEXT/VARCHAR(255) PRIMARY KEY      -- caller-supplied or store-generated ULID
  kind            INTEGER                            -- VkKind ordinal; informational, not authoritative
  inline_format   INTEGER                            -- 0=gene-text, 1=reserved-binary
  inline_payload  BLOB/BYTEA/LONGBLOB  NOT NULL      -- always populated in v1
  byte_size       BIGINT                             -- payload size (post-encode), used for stats
  updated_at      TIMESTAMP/TIMESTAMPTZ/DATETIME(6)  -- client-set at write time; no trigger

gene_blobs                                           -- externalized-child sidecar (v1: ^externalize only)
  sha256          CHAR(64) PRIMARY KEY
  byte_size       BIGINT
  inline_data     BLOB/BYTEA/LONGBLOB  NOT NULL      -- present in v1 (no external_uri tier)

gene_value_blobs                                     -- per-field externalization mapping
  value_id        TEXT/VARCHAR(255)                  -- references gene_values.id (application-side, no FK)
  child_path      TEXT/VARCHAR(512)                  -- absolute selector, e.g. "/avatar" or "/history/items"
  blob_sha256     CHAR(64)                           -- references gene_blobs.sha256 (application-side, no FK)
  PRIMARY KEY     (value_id, child_path)
  INDEX           (blob_sha256)                      -- supports orphan-check on update/delete
```

Notes:
- `gene_values.id` is the natural primary key — clustered on SQLite/MySQL (InnoDB), btree on Postgres — so id-keyed `get`/`put` is O(log n) with no secondary lookup.
- `gene_values.inline_payload` is `NOT NULL` in v1 because root values are always inline. v2 may relax this to `NULL` and add `gene_values.blob_sha256` for size-driven leaf auto-detach via a forward-only migration; existing v1 rows remain valid (their `blob_sha256` defaults to NULL and `inline_payload` stays populated).
- No foreign key from `gene_value_blobs.blob_sha256` to `gene_blobs.sha256` is declared. FK checks add a per-write probe and complicate the multi-statement transaction without correctness benefit (content addressing makes transiently dangling refs harmless until cleanup).
- `gene_blobs` and `gene_value_blobs` are empty for stores that never use `^externalize`. The fast `put`/`get`/`delete` paths never touch them; they exist only for opt-in field-level externalization. The orphan-cleanup `NOT EXISTS` predicate checks only `gene_value_blobs.blob_sha256`, since v1 has no root-level referrer.
- No `created_at`, no `version`, no `ref_count`, no root `blob_sha256`, no `external_uri` — every column removed from the v1 schema is one less byte to write and one less index to update on the hot path. Each can be reintroduced in a forward-only migration if a future workload needs it.

## Risks / Trade-offs

- **Risk:** Text serdes is larger than a packed binary format → larger rows, larger blobs.
  - *Mitigation:* `inline_format` byte reserved; binary upgrade is a non-breaking follow-up.
- **Risk:** Three dialect-specific DDLs increase maintenance burden if a fourth backend (DuckDB, etc.) lands.
  - *Mitigation:* DDLs live in one file, generated from a single Nim-side description; adding a new dialect is template work.
- **Risk:** Concurrent `^externalize` updates against the same id can leave orphaned `gene_blobs` rows. Under `N` concurrent writers on a single id with overlapping child paths the residue is bounded by `O(N-1)` orphaned blobs per evicted child, not the single-row case the simple two-writer analysis suggests: each writer's orphan-check sees only the prior hashes it captured, not the hashes the other in-flight writers are about to evict.
  - *Mitigation:* Each writer's orphan-check runs inside the same transaction as its own mapping-row mutation, so the orphan count is provably bounded by the number of in-flight writers at any instant — there is no unbounded leak. A subsequent `^externalize` `put` whose child content matches an orphan re-attaches it via the idempotent blob insert. v1 does not ship a sweeper or a `gc_blobs` API; callers running highly-concurrent updates on the same externalized fields should either serialize through their own queue or wait for the opt-in vacuum follow-up (v2). `put` without `^externalize` is single-statement and cannot create orphans.
- **Risk:** A caller stores a multi-MB root value (e.g., a giant `VkString`) and hits the backend's per-row size limit (~1 GB on Postgres TOAST, configurable on SQLite, `max_allowed_packet` on MySQL) with no implicit fallback to a blob.
  - *Mitigation:* Documented v1 limitation. Callers who anticipate large sub-fields declare them with `^externalize` at the field they know to be large. A root that is itself one big leaf string is unsupported in v1 (`^externalize [/]` is rejected by the selector grammar); v2's leaf auto-detach will close this gap by treating a root-leaf string above threshold as if `^externalize` had been declared.
- **Risk:** `VkLazyDbValue` resolution errors (closed store, missing blob, network failure) surface at first access rather than at `get` time, which can confuse callers who treat `get` as the failure boundary.
  - *Mitigation:* Documented behavior; resolution errors raise the same typed errors as a direct `get` would, with the originating `id` and `sha256` in the message. Callers who need eager validation can call an explicit `materialize` on the value at the `get` site (v2; out of scope here).
- **Risk:** No optimistic-concurrency token means concurrent writers can clobber each other under last-writer-wins semantics.
  - *Mitigation:* Documented limitation. v2 may add an opt-in `put_if_match(id, expected_sha256, value)` that compiles to `UPDATE ... WHERE blob_sha256 = ?` — still one round-trip, but only for callers who need it.
- **Risk:** Prepared-statement reuse across reconnects requires re-preparation; transient connection loss hides behind it.
  - *Mitigation:* The store layer owns its own prepared-statement cache keyed by connection handle; reconnection invalidates and rebuilds the cache lazily on next `put`.
- **Risk:** MySQL build wiring already landed (`gene.nimble:44`, commit `8d499f5e`) but no CI smoke tests its behavior end-to-end; platform-specific link issues against libmysqlclient may regress silently.
  - *Mitigation:* This proposal adds a CI smoke job that exercises the MySQL driver against the docker-compose service. The `buildext` target itself stays as-is.
- **Risk:** Non-persistable kinds list drifts as new `Vk*` kinds land.
  - *Mitigation:* Codec computes persistability from a single allow-list table near the `Vk*` enum, with a compile-time check that every kind is either allow- or deny-listed.

## Migration Plan

This is additive; no existing data is touched. Steps:

1. Land schema (`gene_values`, `gene_blobs`, `gene_value_blobs`, `gene_store_meta`) + codec + SQLite driver behind `(import genex/db_store)`. No build-system changes; MySQL `buildext` already present.
2. Land Postgres driver; CI service in `docker-compose.yml` already exists for `add-postgres-client`.
3. Add MySQL CI smoke job against the docker-compose service (driver and build already in place).
4. Document the persistable-kind matrix, the `^externalize` workflow, and the v1→v2 schema-evolution path in `docs/sql-value-persistence.md`.
5. Future change (v2): introduce `inline_format = 1` binary payload, or add `gene_values.blob_sha256` (+ `gene_blobs.external_uri` if needed) for leaf auto-detach; `gene_store_meta.schema_version` bumps and a forward-only migration adds the columns (default NULL on existing rows). Existing v1 rows remain valid without rewrite.

Rollback: drop the four tables; the change is self-contained.

## Open Questions

- Should `put` auto-generate ids by **ULID** (sortable, no extra index needed) or **UUIDv7**? ULID has fewer dependencies in Nim; UUIDv7 is more standard. Proposal leans ULID; flag for review.
A: ULID
- Should `scan` return Gene values eagerly or lazily? Lazy iterator matches existing Gene generator surface (`add-iteration-protocol`) but requires holding a cursor; complicates connection-pool semantics. Proposal leans lazy with explicit `close`; flag for review.
A: eagerly in v1
- Should `gc_blobs` ship in v1 (callable from Gene) or be deferred to a separate change? Proposal leans v1 so the offline-GC story is complete; flag for review.
A: Neither — orphan cleanup is automatic and runs inside `delete`/`put` (see "Automatic Blob Cleanup via Orphan-Check"). No user-callable `gc_blobs` in v1; no external DB job required.
- Should there be a published p99 latency budget for `put` on inline payloads (e.g., "≤ 100µs against in-memory SQLite, ≤ 1ms against local Postgres")? Helpful for regression detection but requires CI bench infra; flag for review.
A: deferred
