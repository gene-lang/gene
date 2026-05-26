## ADDED Requirements

### Requirement: Generic Logical Schema

The system SHALL define a single logical schema — `gene_values`, `gene_blobs`, `gene_value_blobs`, `gene_store_meta` — that is materialized by per-backend DDL templates for SQLite, MySQL, and PostgreSQL. The same schema MUST be capable of storing multiple unrelated Gene values, each keyed by a caller- or store-supplied unique string id, without backend-specific surface changes. In v1 every root value's encoded payload SHALL live inline in `gene_values.inline_payload`; `gene_blobs` and `gene_value_blobs` SHALL be populated only by explicit `^externalize` selectors (see "Field-Level Externalization"). The v1 schema SHALL NOT include a `gene_values.blob_sha256` column or a `gene_blobs.external_uri` column; a future version MAY add these via a forward-only `schema_version` migration without invalidating v1 rows.

#### Scenario: Multiple unrelated values persist in one store
- **GIVEN** an open SQL-backed store
- **WHEN** a caller `put`s a `VkString` with id `"user_name"`, a `VkMap` with id `"config"`, and a `VkGene` with id `"current_state"`
- **THEN** all three values MUST be independently retrievable by their respective IDs and MUST remain unrelated in storage.

#### Scenario: Same Gene value round-trips across all three backends
- **WHEN** a caller `put`s the same complex Gene value (a nested `VkGene` with `VkMap` and `VkArray` children) into a SQLite store, a MySQL store, and a Postgres store
- **THEN** subsequent `get` calls against all three stores return values that are `==`-equal to the original under Gene's value-equality semantics.

#### Scenario: Schema is idempotent across opens
- **WHEN** `open` is called twice against the same backing database with the same schema version
- **THEN** the second call MUST NOT alter any existing rows or DDL and MUST succeed without error.

### Requirement: Always-Inline Root Payloads

Every `put` call SHALL store the encoded value bytes in `gene_values.inline_payload`. The system SHALL NOT auto-route root payloads to a content-addressed sidecar based on size; v1 ships no `inline_threshold` or `blob_threshold` configuration, no `gene_values.blob_sha256` column, and no `^external_uri` keyword. Callers who know a particular sub-field is large MUST declare it explicitly via `^externalize` (see "Field-Level Externalization"); auto-detection of large leaf fields is deferred to a future version that can layer onto the same schema without invalidating v1 rows.

#### Scenario: Root payload is always inline
- **WHEN** a caller `put`s any value (small, medium, or large)
- **THEN** `gene_values.inline_payload` MUST be non-NULL and MUST contain the encoded payload bytes.

#### Scenario: No row-level routing keywords in v1
- **WHEN** a caller passes `^inline_threshold`, `^blob_threshold`, or `^external_uri` to `put`
- **THEN** the call MUST raise a typed error naming the unsupported keyword, and MUST NOT write any row.

#### Scenario: Root that exceeds backend row-size limit is the caller's responsibility
- **GIVEN** a value whose encoded payload exceeds the underlying backend's per-row size limit (e.g., MySQL `max_allowed_packet`)
- **WHEN** the caller invokes `put` without `^externalize`
- **THEN** the store MAY surface the backend's native error and MUST NOT silently truncate or implicitly detach. Callers SHOULD use `^externalize` on the field(s) known to be large.

### Requirement: Content-Addressed Deduplication of Externalized Children

Externalized children written through `^externalize` SHALL be addressed by SHA-256 of their encoded sub-tree, and identical sub-trees MUST share a single `gene_blobs` row regardless of how many `gene_value_blobs` rows reference them. Blob inserts MUST be idempotent and MUST NOT require an application-side existence check.

#### Scenario: Two identical externalized children share one blob row
- **WHEN** two distinct `gene_values` ids `put` with `^externalize [/avatar]` whose `/avatar` sub-trees encode to byte-identical payloads
- **THEN** exactly one row MUST exist in `gene_blobs` and both `gene_value_blobs` rows MUST reference the same `blob_sha256`.

#### Scenario: Blob upsert is engine-idempotent
- **WHEN** an `^externalize` `put` produces a child whose `sha256` already exists in `gene_blobs`
- **THEN** the blob write MUST use the dialect's idempotent insert idiom (`INSERT OR IGNORE`, `ON CONFLICT (sha256) DO NOTHING`, or `INSERT IGNORE`) and MUST NOT issue a prior `SELECT` to check existence.

### Requirement: Single-Statement Fast Update Path

`put` without `^externalize` SHALL compile into exactly one prepared, idempotent UPSERT statement per dialect, keyed on `id`. The call MUST issue exactly one SQL statement, MUST NOT perform any read-before-write, and MUST NOT touch `gene_blobs` or `gene_value_blobs`. When the caller passes `^externalize` selectors (see "Field-Level Externalization") `put` MUST issue at most `1 + 2·N + K` round-trips in a single transaction, where `N` is the number of selectors and `K ≤ N+1` is the number of previously-referenced child blobs that became orphaned by the operation. Prepared statements MUST be reused across calls on the same connection.

#### Scenario: put without externalize issues a single statement
- **WHEN** a caller `put`s any value under any id without `^externalize`
- **THEN** exactly one SQL statement MUST be executed against the underlying connection, and that statement MUST be the dialect's idempotent UPSERT (`INSERT ... ON CONFLICT(id) DO UPDATE` for SQLite/Postgres, `INSERT ... ON DUPLICATE KEY UPDATE` for MySQL).

#### Scenario: Prepared statement is reused across puts
- **GIVEN** a store open against the same connection
- **WHEN** a caller invokes `put` 1000 times with different ids and payloads, none of them using `^externalize`
- **THEN** the underlying driver MUST prepare the UPSERT statement at most once and MUST re-bind parameters on each subsequent call.

#### Scenario: Updating a value performs no extra read
- **GIVEN** an id that already has a value stored
- **WHEN** a caller `put`s a new value under that id without `^externalize`
- **THEN** the store MUST NOT issue a prior `SELECT` or any other read against `gene_values`, `gene_blobs`, or `gene_value_blobs`, and exactly one UPSERT statement MUST be executed.

### Requirement: Automatic Blob Cleanup on Delete and Update

The system SHALL NOT maintain per-update reference counts on `gene_blobs`. Orphan cleanup applies only to externalized children. When `delete` removes a value that had externalized children, the store SHALL atomically delete each corresponding `gene_blobs` row if and only if no other `gene_value_blobs.blob_sha256` still references its `sha256`. When `put` with `^externalize` evicts a previously-mapped `(value_id, child_path)` whose `blob_sha256` is no longer referenced by any remaining `gene_value_blobs` row, the store SHALL apply the same orphan-check. Cleanup MUST run inside the same transaction as the triggering `delete`/`put` and MUST NOT require a separate user-callable GC operation. v1 has no `gene_values.blob_sha256` column, so the orphan-check is single-table (`gene_value_blobs` only); a future version that adds root-level detachment MUST extend the orphan-check predicate accordingly.

#### Scenario: Deleting a value with a unique externalized child removes the child blob
- **GIVEN** a `gene_value_blobs` row whose `blob_sha256` is the only reference to a `gene_blobs` row
- **WHEN** a caller invokes `delete` on that value's id
- **THEN** the `gene_values` row, the `gene_value_blobs` row, and the `gene_blobs` row MUST all be removed in the same transaction.

#### Scenario: Deleting one of two values sharing an externalized child retains the child blob
- **GIVEN** two `gene_value_blobs` rows (belonging to distinct value ids) referencing the same `gene_blobs.sha256`
- **WHEN** a caller invokes `delete` on one of them
- **THEN** only that value's `gene_values` and `gene_value_blobs` rows MUST be removed, and the `gene_blobs` row MUST remain because the other value's `gene_value_blobs` row still references it.

#### Scenario: Replacing an externalized child reclaims the old child blob if orphaned
- **GIVEN** a `gene_value_blobs` row that uniquely references a `gene_blobs` sha256
- **WHEN** `put` with the same `^externalize` selector replaces the child sub-tree with new content
- **THEN** the `gene_value_blobs` row MUST end up pointing at the new sha256, a `gene_blobs` row MUST exist for the new sha256, and the old `gene_blobs` row MUST have been deleted inside the same transaction.

#### Scenario: put/delete without externalized children issues no blob-cleanup statement
- **GIVEN** an id whose value was written without `^externalize` (no `gene_value_blobs` rows exist for it)
- **WHEN** a caller invokes `delete` or `put` (without `^externalize`) on that id
- **THEN** the store MUST NOT execute any `DELETE` or `SELECT` against `gene_blobs` or `gene_value_blobs`.

### Requirement: Persistable Kind Coverage

The system SHALL persist every `Vk*` kind that the existing text serdes (`src/gene/serdes.nim`) supports, including but not limited to `VkNil`, `VkBool`, `VkInt`, `VkFloat`, `VkChar`, `VkString`, `VkSymbol`, `VkArray`, `VkMap`, `VkGene`, `VkInstance` (named-class form), `VkEnum`, `VkEnumValue`, `VkTupleValue`, and `VkCustom` values that register class hooks.

#### Scenario: Round-trip preserves nested Gene structure
- **WHEN** a `VkGene` value with properties (`^a 1 ^b "x"`) and children (`[1 2 [3 4]]`) is `put` and then `get`
- **THEN** the returned value MUST have the same kind, the same property keys and values, and the same ordered children as the original.

#### Scenario: Named instance round-trips via class hook
- **WHEN** a `VkInstance` of a class registered with `custom_serdes_hooks` is `put` and then `get`
- **THEN** the returned value MUST be an instance of the same class with the same hook-produced payload.

#### Scenario: Named instance whose class is absent at decode raises
- **GIVEN** a `gene_values` row whose payload encodes a `VkInstance` of class `acme/Widget`
- **WHEN** `get` is invoked in a process whose runtime has not loaded the `acme/Widget` class
- **THEN** the call MUST raise a typed error naming the missing class and the offending value id, and MUST NOT return a degraded representation (e.g., a `VkMap` of the raw fields).

### Requirement: Field-Level Externalization

`put` SHALL accept an optional `^externalize` property whose value is an array of absolute child selectors using the same grammar enforced by the filesystem serdes layer (`src/gene/serdes.nim`). For each accepted selector the store SHALL encode the corresponding sub-tree of the value into its own `gene_blobs` row, replace the sub-tree in the parent payload with a stable placeholder marker, and record the mapping in a `gene_value_blobs(value_id, child_path, blob_sha256)` row. Externalized children MUST be routed to `gene_blobs` regardless of size — `^externalize` is the only externalization mechanism in v1, and there is no size-based fallback. Externalized blobs MUST participate in content-addressed deduplication and orphan-cleanup as specified in the requirements above. The parent payload (with placeholders substituted) MUST always be stored inline in `gene_values.inline_payload`; v1 has no root-level detachment.

Selector validation MUST reject:
- selectors that are not absolute (do not begin with `/`),
- the root selector `/` (selectors must target a child),
- selectors with empty path segments,
- wildcard or legacy forms (`*`, `**`, `@`, `@@`, `!`),
- duplicate selectors within a single `put` call,
- selectors that are strict ancestors or descendants of another selector in the same call.

A selector that matches no value at write time MUST raise a typed error and MUST NOT write any row.

#### Scenario: Externalized field is written to its own blob row
- **GIVEN** an open store and a value `v` with a 10 KiB `^avatar` field
- **WHEN** the caller invokes `put` with `^externalize [/avatar]`
- **THEN** exactly one row MUST exist in `gene_blobs` whose `sha256` matches the encoded avatar sub-tree, exactly one row MUST exist in `gene_value_blobs` with `(value_id = id, child_path = "/avatar", blob_sha256 = <that sha>)`, and the parent payload stored in `gene_values.inline_payload` MUST contain a placeholder at the `/avatar` path instead of the inline avatar bytes.

#### Scenario: Externalization applies regardless of child size
- **GIVEN** a value whose `^summary` field encodes to 64 bytes
- **WHEN** the caller invokes `put` with `^externalize [/summary]`
- **THEN** the `/summary` sub-tree MUST still be written to `gene_blobs` and recorded in `gene_value_blobs`, and the parent payload stored in `gene_values.inline_payload` MUST contain a placeholder at the `/summary` path. v1 has no size threshold to bypass; `^externalize` is unconditional.

#### Scenario: Externalized field is returned lazily
- **GIVEN** an id whose value was `put` with `^externalize [/avatar]`
- **WHEN** the caller invokes `get` on that id and does not access the `/avatar` field
- **THEN** the store MUST issue at most one `SELECT` against `gene_value_blobs` keyed by `value_id`, and MUST NOT issue any `SELECT` against `gene_blobs` for the avatar's sha256.

#### Scenario: First access to an externalized field materializes exactly once
- **GIVEN** an id whose value was `put` with `^externalize [/avatar]`
- **WHEN** the caller invokes `get` on that id and then accesses the `/avatar` field two or more times
- **THEN** the store MUST issue exactly one `SELECT` against `gene_blobs` for the avatar's sha256, decode the payload, replace the per-field `VkLazyDbValue` with the materialized value, and MUST NOT re-issue the fetch for subsequent accesses.

#### Scenario: Replacing an externalized field reclaims the old blob
- **GIVEN** an id whose value was `put` with `^externalize [/avatar]` and whose avatar sub-tree is the only reference to its `gene_blobs` sha256 across `gene_value_blobs.blob_sha256`
- **WHEN** the caller invokes `put` again under the same id with a new avatar sub-tree and the same `^externalize [/avatar]`
- **THEN** the `gene_value_blobs` row for `(id, "/avatar")` MUST point at the new sha256, a `gene_blobs` row MUST exist for the new sha256, and the old `gene_blobs` row MUST have been removed inside the same transaction.

#### Scenario: Deleting a value cascades to externalized fields
- **GIVEN** an id whose value was `put` with `^externalize [/avatar /history]` and whose two child blobs are each only referenced by this value
- **WHEN** the caller invokes `delete` on that id
- **THEN** the `gene_values` row, both `gene_value_blobs` rows for this id, and both `gene_blobs` rows MUST be removed in the same transaction.

#### Scenario: Externalized fields dedupe across unrelated ids
- **GIVEN** two distinct `gene_values` ids that are each `put` with `^externalize [/avatar]` and whose `/avatar` sub-trees encode to byte-identical payloads
- **THEN** exactly one row MUST exist in `gene_blobs` for that sha256, and both ids MUST have a `gene_value_blobs` row referencing it.

#### Scenario: Invalid selector forms are rejected
- **WHEN** a caller invokes `put` with any of `^externalize [/]`, `^externalize [avatar]`, `^externalize [/*]`, `^externalize [/avatar /avatar]`, or `^externalize [/profile /profile/avatar]`
- **THEN** the call MUST raise a typed error naming the offending selector and MUST NOT write any row.

#### Scenario: Selector that matches no value raises
- **GIVEN** a value `v` that has no `/missing` child
- **WHEN** the caller invokes `put` with `^externalize [/missing]`
- **THEN** the call MUST raise a typed error and MUST NOT write any row.

### Requirement: Lazy Materialization of Externalized Children

`get` SHALL return the root value fully materialized from `gene_values.inline_payload`. For each externalized child path inside the returned value, the store SHALL substitute a runtime-only lazy wrapper; the child's `gene_blobs` row MUST NOT be fetched, and the child payload MUST NOT be decoded, until the caller accesses that child's contents. Values written without `^externalize` MUST be returned fully materialized with no wrapper anywhere in the result. The lazy wrapper MUST be type-transparent at the user-visible Gene type system level: `(gene/kind v)` and equivalent introspection paths MUST report the cached original kind (`VkMap`, `VkGene`, …) rather than an internal wrapper kind. Structural access to the wrapped value's contents (iteration, indexing, property read, equality against a non-lazy peer, serialization) MUST implicitly materialize the wrapper before proceeding, and the materialized value MUST replace the wrapper in place so subsequent accesses are O(1). The system MAY expose an explicit `materialize` operation as an escape hatch for callers who need eager error surfacing or who want to drop the wrapper's reference to the store handle.

#### Scenario: get without externalized children materializes immediately
- **GIVEN** an id whose value was `put` without `^externalize`
- **WHEN** `get` is invoked on that id
- **THEN** the returned value MUST be fully decoded, MUST contain no `VkLazyDbValue` wrappers, and MUST NOT trigger any further query against `gene_blobs` or `gene_value_blobs`.

#### Scenario: get with externalized children defers child blob fetches
- **GIVEN** an id whose value was `put` with one or more `^externalize` selectors
- **WHEN** `get` is invoked on that id and the caller does not access any externalized child
- **THEN** the store MUST issue at most one `SELECT` against `gene_value_blobs` keyed by `value_id` to discover the child mappings, and MUST NOT issue any `SELECT` against `gene_blobs` for any child sha256.

#### Scenario: First content access materializes a child exactly once
- **GIVEN** an id whose value was `put` with `^externalize [/avatar]`
- **WHEN** `get` is invoked on that id and the caller then iterates, indexes, or otherwise accesses the `/avatar` field two or more times
- **THEN** the store MUST issue exactly one `SELECT` against `gene_blobs` keyed by the avatar's `sha256`, decode the payload, and replace the wrapper with the materialized value so that all subsequent accesses MUST NOT re-issue the fetch.

#### Scenario: Lazy wrapper is type-transparent
- **WHEN** a caller `get`s a value with an externalized `VkMap` child and queries that child's kind via Gene-level introspection (without accessing its contents)
- **THEN** the introspection MUST report the original kind (e.g., `VkMap`) and MUST NOT expose `VkLazyDbValue` or any equivalent internal marker.

### Requirement: Non-Persistable Kinds Raise Typed Errors

The system SHALL refuse to persist runtime-only kinds (`VkFunction`, `VkMethod`, `VkBoundMethod`, `VkNativeFn`, `VkNativeMethod`, `VkScope`, `VkFrame`, `VkNativeFrame`, `VkThread`, `VkActor`, `VkActorContext`, `VkThreadMessage`, `VkFuture`, `VkGenerator`, `VkCompiledUnit`, `VkInstruction`, `VkFunctionDef`, `VkScopeTracker`) and MUST raise a deterministic, typed error rather than silently writing a degraded representation.

#### Scenario: Putting a function raises
- **WHEN** a caller `put`s a `VkFunction` value
- **THEN** the call MUST raise an error whose message names the offending kind, and no row MUST be written.

### Requirement: Stable On-Disk Format Through `inline_format` Byte

The system SHALL record the encoding format of each payload in `gene_values.inline_format`. Value `0` denotes the existing gene-text serdes format; value `1` is reserved for a future compact binary format. Decoders MUST dispatch on this field and MUST reject unknown values.

#### Scenario: Reader rejects unknown inline_format
- **WHEN** a `gene_values` row contains `inline_format = 99`
- **THEN** `get` MUST raise an error indicating an unsupported format version and MUST NOT return a partially decoded value.

### Requirement: Idempotent Schema Migration

The system SHALL maintain a `schema_version` entry in `gene_store_meta` and SHALL apply forward-only DDL migrations during `open` when `^auto_migrate true` is set. Migrations MUST be re-runnable: invoking `ensure_schema` against an already-current store MUST be a no-op.

#### Scenario: Auto-migrate on open
- **WHEN** `open` is called with `^auto_migrate true` against a database whose `schema_version` is below the current version
- **THEN** the store MUST apply pending DDL and MUST update `schema_version` to the current value atomically.

#### Scenario: Open without auto-migrate against stale schema
- **WHEN** `open` is called with `^auto_migrate false` (the default) against a database whose `schema_version` is below the current version
- **THEN** the call MUST raise a schema-version-mismatch error naming the expected and actual versions.

### Requirement: Backend-Portable Gene API

The system SHALL expose `(import genex/db_store)` with the operations `open`, `put`, `get`, `has?`, `delete`, `scan`, and `close`, and the surface MUST be identical regardless of underlying backend.

#### Scenario: Same Gene code drives SQLite and Postgres
- **WHEN** the same Gene program calls `(var s (genex/db_store/open ^backend "sqlite" ^dsn ":memory:"))` and (separately) `(var s (genex/db_store/open ^backend "postgres" ^dsn "postgres://..."))`
- **THEN** the subsequent `put`, `get`, `has?`, `delete`, `scan`, and `close` calls MUST have identical signatures and semantics across both stores.

#### Scenario: put without an id assigns a ULID
- **WHEN** a caller invokes `put` against an open store without supplying an id (e.g., `(genex/db_store/put s v)`)
- **THEN** the store MUST generate a fresh ULID (Crockford-base32, monotonic per process), insert the value under that id, and return the generated id to the caller so subsequent `get`/`delete` calls can target the same row.

### Requirement: MySQL Build Target

The build system SHALL produce a loadable MySQL extension (`build/libmysql.dylib` on macOS, `.so` on Linux, `.dll` on Windows) from `src/genex/mysql.nim` as part of `nimble buildext`, on parity with the SQLite and PostgreSQL extensions.

#### Scenario: buildext produces MySQL artifact
- **WHEN** a developer runs `nimble buildext` on a host with MySQL client libraries available
- **THEN** the build MUST emit the MySQL shared library alongside `build/libsqlite.dylib` and `build/libpostgres.dylib`, and `(import genex/mysql)` MUST successfully load it at runtime.
