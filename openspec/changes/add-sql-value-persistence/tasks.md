## 1. Schema & Codec Foundation

- [ ] 1.1 Define `DialectDescriptor` in `src/genex/db.nim` (placeholder style, blob type name, upsert clause, returning-id strategy) and implement for SQLite, MySQL, Postgres.
- [ ] 1.2 Implement `src/genex/db_store/codec.nim`: encode a `Value` to a `(payload: seq[byte], inline_format: uint8, byte_size: int, sha256: array[32, byte])` tuple using the existing text serdes (`src/gene/serdes.nim`).
- [ ] 1.3 Define the non-persistable kind list (`VkFunction`, `VkScope`, `VkFrame`, `VkThread`, `VkFuture`, `VkNativeFn`, `VkNativeMethod`, `VkCompiledUnit`, `VkInstruction`, `VkActor`, `VkActorContext`, `VkGenerator`); raise a typed error when encountered (test-covered).
- [ ] 1.4 Implement decode path (`payload + inline_format -> Value`) and assert round-trip equivalence at unit-test level for every persistable `Vk*` kind.

## 2. Per-Backend DDL

- [ ] 2.1 Author SQLite DDL templates for `gene_values`, `gene_blobs`, `gene_store_meta` in `src/genex/db_store/schema.nim`.
- [ ] 2.2 Author Postgres DDL with `BYTEA`, `TIMESTAMPTZ`, `ON CONFLICT` upsert, `gen_random_uuid()` available when ids omitted.
- [ ] 2.3 Author MySQL DDL with `LONGBLOB`, `DATETIME(6)`, `ON DUPLICATE KEY UPDATE`, `utf8mb4` charset.
- [ ] 2.4 Implement schema version table and an idempotent `ensure_schema(conn, dialect)` migration runner that detects current version and applies forward-only DDL.

## 3. Gene API Surface

- [ ] 3.1 Implement `src/genex/db_store.nim` exposing `open`, `put`, `get`, `has?`, `delete`, `scan`, `close`, plus the namespace export wired through `gene_init`. Orphan blob cleanup is internal to `delete`/`put`; there is no user-callable `gc_blobs` in v1.
- [ ] 3.2 `open` accepts an existing `SQLiteConnection|PostgresConnection|MySQLConnection` *or* a `(^backend "sqlite" ^dsn ...)` shorthand that opens the connection internally.
- [ ] 3.3 `put` enforces threshold rules: payloads ≤ `inline_threshold` go in `gene_values.inline_payload`; payloads ≤ `blob_threshold` are written to `gene_blobs` by sha256; payloads > `blob_threshold` raise unless caller passes `^external_uri` with a pre-uploaded blob.
- [ ] 3.4 `scan` returns an eagerly-materialized sequence (Gene-level) of `(id, value)` pairs keyed by id prefix, ordered by id. Detached values returned by `scan` are `VkLazyDbValue` wrappers (see Section 5), so the eager pass touches only `gene_values`.
- [ ] 3.5 Implement automatic orphan blob cleanup inside `delete` and `put`: capture the previously-referenced `blob_sha256` (via `DELETE ... RETURNING` / `UPDATE ... RETURNING` on SQLite 3.35+ and Postgres; via an explicit `SELECT blob_sha256 FROM gene_values WHERE id = ?` on MySQL 8.0), then conditionally `DELETE FROM gene_blobs WHERE sha256 = ? AND NOT EXISTS (SELECT 1 FROM gene_values WHERE blob_sha256 = ?)` in the same transaction. The orphan-check MUST be skipped when the operation does not change `blob_sha256` (inline → inline or same-hash detached → detached).

## 4. Fast-Update Path

- [ ] 4.1 Build a per-connection prepared-statement cache keyed by `(dialect, stmt_kind)`; prepare UPSERT, GET, DELETE, HAS, SCAN once at first use and re-bind thereafter.
- [ ] 4.2 Implement single-statement UPSERT for SQLite (`INSERT INTO gene_values(...) VALUES(?, ...) ON CONFLICT(id) DO UPDATE SET inline_payload=excluded.inline_payload, blob_sha256=excluded.blob_sha256, ...`), Postgres (`ON CONFLICT (id) DO UPDATE`), and MySQL (`ON DUPLICATE KEY UPDATE`).
- [ ] 4.3 Implement idempotent blob upsert: `INSERT OR IGNORE INTO gene_blobs ...` (SQLite), `ON CONFLICT (sha256) DO NOTHING` (Postgres), `INSERT IGNORE` (MySQL) — no `SELECT` first.
- [ ] 4.4 Batch the detached-blob path as one transaction containing blob upsert, value upsert, and (when the operation changes `blob_sha256`) the orphan-cleanup `DELETE` against `gene_blobs`; commit at the end of `put`.
- [ ] 4.5 Skip SHA-256 hashing entirely when `byte_size ≤ inline_threshold`; the codec returns an empty digest in that case.
- [ ] 4.6 Add a perf test under `tests/perf/test_db_store_perf.nim` asserting that an inline `put` against an in-memory SQLite store issues exactly one prepared statement (verified via a query counter), that an inline `delete` issues exactly one, and that the prepared statements are re-used across iterations.

## 5. Lazy Materialization

- [ ] 5.1 Add a new `VkLazyDbValue` entry to the `Vk*` enum in `src/gene/types/type_defs.nim` (near `VkInstance`); reserve a reference-cell payload carrying `store_handle`, `id`, `blob_sha256`, `inline_format`, `original_kind`, and `byte_size`.
- [ ] 5.2 Implement `materialize_lazy_db(value)` in `src/genex/db_store.nim`: issue `SELECT inline_data, external_uri FROM gene_blobs WHERE sha256 = ?`, decode via the codec, atomically replace the wrapper's reference cell with the resolved value; idempotent on repeated calls.
- [ ] 5.3 Wire VM accessor sites (`array_data`, `map_data`, `gene_*` field reads, equality, kind dispatch when the cached `original_kind` is insufficient) to call `materialize_lazy_db` before proceeding.
- [ ] 5.4 Short-circuit equality between two `VkLazyDbValue`s with the same `(store_handle, blob_sha256)` to `true` without materializing either side.
- [ ] 5.5 Ensure serialization of a `VkLazyDbValue` (e.g., it is the input to another `put`) materializes first so on-disk payloads never contain lazy markers.
- [ ] 5.6 Make `get` of an inline value return a fully materialized value (no wrapper); only detached `get`s return a wrapper.
- [ ] 5.7 Make Gene-level kind introspection (e.g., `(gene/kind v)`) report the cached `original_kind`, not `VkLazyDbValue`.
- [ ] 5.8 Add `tests/test_db_store_lazy.nim` covering: (a) detached `get` issues zero blob queries until content is accessed, (b) first content access issues exactly one query and the wrapper is replaced, (c) repeated access after the first issues zero further queries, (d) inline `get` returns a fully materialized value with no wrapper, (e) Gene-level `kind` introspection reports the original kind.

## 6. MySQL Build Wiring

- [ ] 6.1 Add `build/libmysql.dylib` (and `.so` / `.dll`) target to the `buildext` task in `gene.nimble:36-47`.
- [ ] 6.2 Add a CI smoke test that exercises the MySQL driver against the docker-compose service.

## 7. Tests

- [ ] 7.1 Write `tests/test_db_store_codec.nim` — pure codec round-trip for every persistable `Vk*` kind including deeply nested `VkGene`, `VkMap`, `VkArray`, `VkInstance` (named class only), `VkEnumValue`, `VkTupleValue`.
- [ ] 7.2 Write `tests/test_db_store_sqlite.nim` — end-to-end put/get/has?/delete/scan against an in-memory SQLite database, plus the "multiple unrelated ids in one store" case.
- [ ] 7.3 Write `tests/test_db_store_postgres.nim` and `tests/test_db_store_mysql.nim` gated on env (run in CI against docker-compose services).
- [ ] 7.4 Add a Gene-level integration test under `testsuite/15-serialization/` mirroring the user-visible API and asserting the threshold-routing behavior at the byte-count boundary.
- [ ] 7.5 Add an auto-cleanup test that exercises: (a) deleting the only reference to a blob removes the blob row, (b) deleting one of two references retains the blob row, (c) `put`ing an existing id with a different payload reclaims the old blob row, (d) inline `delete` and inline `put` issue zero statements against `gene_blobs`.

## 8. Field-Level Externalization

- [ ] 8.1 Add a `gene_value_blobs(value_id, child_path, blob_sha256)` mapping table to the DDL templates in `src/genex/db_store/schema.nim` for all three dialects: primary key `(value_id, child_path)`, secondary index on `blob_sha256` to support orphan-check, and an `ON DELETE CASCADE`-equivalent cleanup driven by the store (no FK to `gene_values` so the dialects stay consistent; cleanup is application-side inside the same transaction as `delete`/`put`).
- [ ] 8.2 Port the `^externalize` selector parser and validator from `src/gene/serdes.nim:1125-1217` into a shared helper reachable from both serdes and `db_store`: enforce absolute selectors (`/path`), reject root selectors, reject empty segments, reject wildcards (`*`, `**`, `@`, `@@`, `!`), reject duplicates, and reject ancestor/descendant overlap.
- [ ] 8.3 Extend `src/genex/db_store/codec.nim` with a `encode_with_externalize(value, selectors)` entry point that returns `(parent_payload, child_payloads: seq[(child_path, payload, sha256, byte_size)])`; the parent payload places a stable placeholder marker at each externalized path so the decoder can re-install a `VkLazyDbValue` there.
- [ ] 8.4 In `src/genex/db_store.nim::put`, when `^externalize` is set: encode parent + children, upsert each `gene_blobs` row by sha256 (idempotent), upsert each `gene_value_blobs(value_id, child_path, blob_sha256)` row, upsert the root `gene_values` row, then run a single orphan-cleanup pass that deletes from `gene_blobs` any sha256 that the operation evicted (root or child) and which no `gene_values` or `gene_value_blobs` row still references — all inside one transaction.
- [ ] 8.5 In `delete`, also remove every `gene_value_blobs` row for the target `value_id` and orphan-check each evicted blob sha256 against both `gene_values.blob_sha256` and `gene_value_blobs.blob_sha256`.
- [ ] 8.6 Extend `VkLazyDbValue` (Section 5) to carry `(store_handle, value_id, child_path, blob_sha256, inline_format, original_kind, byte_size)`; `materialize_lazy_db` resolves via `SELECT inline_data, external_uri FROM gene_blobs WHERE sha256 = ?` (sha256 is captured at `get` time so the materialization does not re-hit `gene_value_blobs`).
- [ ] 8.7 In `get`, after decoding the parent payload, walk the decoded value and replace each placeholder marker with a `VkLazyDbValue` populated from the corresponding `gene_value_blobs` row (one batched `SELECT child_path, blob_sha256 ... WHERE value_id = ?` per `get` of a value that has externalized fields; zero queries when none).
- [ ] 8.8 Add `tests/test_db_store_externalize.nim` covering: (a) selector validation matches `serdes.nim` (absolute, no root, no wildcards, no duplicates, no overlap), (b) a `put` with `^externalize [/avatar]` writes exactly one `gene_value_blobs` row and one `gene_blobs` row for the avatar regardless of avatar size, (c) the root parent payload itself is inline when the residual is small, (d) `get` returns a `VkLazyDbValue` at the externalized path and does not fetch the blob until first access, (e) replacing the value with one whose `/avatar` payload differs reclaims the old blob via orphan-check, (f) `delete` cascades to `gene_value_blobs` and orphan-cleans every previously-referenced blob, (g) two distinct ids with `^externalize` selectors hitting byte-identical sub-tree content share a single `gene_blobs` row.

## 9. Documentation

- [ ] 9.1 Add `docs/sql-value-persistence.md` describing the schema, thresholds, dialect quirks, the persistable-kind matrix, the fast-update path, the automatic-cleanup model, the lazy-materialization behavior of `VkLazyDbValue`, and a "Field-Level Externalization" section showing `(genex/db_store/put s id v ^externalize [/avatar /history])` with the resulting row layout across `gene_values`, `gene_value_blobs`, and `gene_blobs`.
- [ ] 9.2 Update `examples/sqlite.gene` (or add `examples/db_store.gene`) showing the put/get round-trip pattern over multiple unrelated ids, including a detached-value example that demonstrates transparent lazy materialization and a field-level `^externalize` example.

## 10. Validation Gate

- [ ] 9.1 `openspec validate add-sql-value-persistence --strict` passes.
- [ ] 9.2 Proposal reviewed and approved before any task above starts (per `openspec/AGENTS.md` Stage 1).
