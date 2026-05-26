## ADDED Requirements

### Requirement: Generic Logical Schema

The system SHALL define a single logical schema — `gene_values`, `gene_blobs`, `gene_store_meta` — that is materialized by per-backend DDL templates for SQLite, MySQL, and PostgreSQL. The same schema MUST be capable of storing multiple unrelated Gene values, each keyed by a caller- or store-supplied unique string id, without backend-specific surface changes.

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

### Requirement: Tiered Storage Routing

The system SHALL route encoded payloads into one of three tiers based on configurable thresholds — `inline_threshold` (default 8 KiB) and `blob_threshold` (default 1 MiB) — and the routing decision MUST be observable through column nullability (`gene_values.inline_payload` vs `gene_values.blob_sha256` vs `gene_blobs.external_uri`).

#### Scenario: Small payload stored inline
- **WHEN** a caller `put`s a value whose encoded byte size is less than or equal to `inline_threshold`
- **THEN** `gene_values.inline_payload` MUST be non-NULL, `gene_values.blob_sha256` MUST be NULL, and no row MUST be inserted into `gene_blobs`.

#### Scenario: Medium payload detached into blob table
- **WHEN** a caller `put`s a value whose encoded byte size exceeds `inline_threshold` but does not exceed `blob_threshold`
- **THEN** `gene_values.inline_payload` MUST be NULL, `gene_values.blob_sha256` MUST equal the SHA-256 of the encoded payload, and a corresponding row MUST exist in `gene_blobs` with `inline_data` non-NULL and `external_uri` NULL.

#### Scenario: Large payload requires external URI
- **WHEN** a caller `put`s a value whose encoded byte size exceeds `blob_threshold` and does not pass `^external_uri`
- **THEN** the call MUST raise a typed error and MUST NOT write any row.

#### Scenario: Large payload accepted with external URI
- **WHEN** a caller `put`s a value whose encoded byte size exceeds `blob_threshold` and passes `^external_uri "s3://bucket/key"`
- **THEN** `gene_blobs.external_uri` MUST equal the supplied URI and `gene_blobs.inline_data` MUST be NULL.

### Requirement: Content-Addressed Deduplication

Detached blobs SHALL be addressed by SHA-256 of the encoded payload, and identical payloads MUST share a single `gene_blobs` row regardless of how many `gene_values` rows reference them. Blob inserts MUST be idempotent and MUST NOT require an application-side existence check.

#### Scenario: Two identical large payloads share one blob row
- **WHEN** two distinct `gene_values` ids `put` values that encode to byte-identical payloads exceeding `inline_threshold`
- **THEN** exactly one row MUST exist in `gene_blobs` and both `gene_values` rows MUST reference the same `blob_sha256`.

#### Scenario: Blob upsert is engine-idempotent
- **WHEN** a caller `put`s a detached-blob value whose `sha256` already exists in `gene_blobs`
- **THEN** the blob write MUST use the dialect's idempotent insert idiom (`INSERT OR IGNORE`, `ON CONFLICT (sha256) DO NOTHING`, or `INSERT IGNORE`) and MUST NOT issue a prior `SELECT` to check existence.

### Requirement: Single-Statement Fast Update Path

`put` SHALL compile into one prepared, idempotent UPSERT statement per dialect, keyed on `id`. For inline payloads (size ≤ `inline_threshold`) `put` MUST issue exactly one statement and MUST NOT perform any read-before-write or touch `gene_blobs` or `gene_value_blobs`. For detached-blob payloads `put` MUST issue at most three statements in a single transaction (idempotent blob upsert + value upsert + conditional orphan-cleanup of the previously-referenced blob; see "Automatic Blob Cleanup on Delete and Update"). When the caller passes `^externalize` selectors (see "Field-Level Externalization") `put` MUST issue at most `1 + 2·N + K` statements in a single transaction, where `N` is the number of selectors and `K ≤ N+1` is the number of previously-referenced blobs (root and per-child) that became orphaned by the operation. Prepared statements MUST be reused across calls on the same connection.

#### Scenario: Inline put issues a single statement
- **GIVEN** a value whose encoded byte size is below `inline_threshold`
- **WHEN** a caller `put`s the value under an existing id
- **THEN** exactly one SQL statement MUST be executed against the underlying connection, and that statement MUST be the dialect's idempotent UPSERT (`INSERT ... ON CONFLICT(id) DO UPDATE` for SQLite/Postgres, `INSERT ... ON DUPLICATE KEY UPDATE` for MySQL).

#### Scenario: Prepared statement is reused across puts
- **GIVEN** a store open against the same connection
- **WHEN** a caller invokes `put` 1000 times with different ids and payloads
- **THEN** the underlying driver MUST prepare the UPSERT statement at most once and MUST re-bind parameters on each subsequent call.

#### Scenario: Updating an inline value performs no extra read
- **GIVEN** an id whose value is already stored inline
- **WHEN** a caller `put`s a new inline value under that id
- **THEN** the store MUST NOT issue a prior `SELECT` or any other read against `gene_values`, and exactly one UPSERT statement MUST be executed.

### Requirement: Automatic Blob Cleanup on Delete and Update

The system SHALL NOT maintain per-update reference counts on `gene_blobs`. When `delete` removes a value whose payload lived in `gene_blobs`, the store SHALL atomically delete the corresponding `gene_blobs` row if and only if no other `gene_values` row still references its `sha256`. When `put` replaces a value's `blob_sha256` (or transitions a value between inline and detached), the store SHALL apply the same orphan-check to the previously-referenced blob. Cleanup MUST run inside the same transaction as the triggering `delete`/`put` and MUST NOT require a separate user-callable GC operation.

#### Scenario: Deleting a value with a unique blob removes the blob
- **GIVEN** a `gene_values` row whose payload is the only reference to a `gene_blobs` sha256
- **WHEN** a caller invokes `delete` on that id
- **THEN** both the `gene_values` row and the `gene_blobs` row MUST be removed in the same transaction.

#### Scenario: Deleting a value with a shared blob retains the blob
- **GIVEN** two `gene_values` rows referencing the same `gene_blobs` sha256
- **WHEN** a caller invokes `delete` on one of them
- **THEN** only the targeted `gene_values` row MUST be removed and the `gene_blobs` row MUST remain because the other value still references it.

#### Scenario: Updating a value to a new blob reclaims the old blob if orphaned
- **GIVEN** a `gene_values` row that uniquely references a `gene_blobs` sha256
- **WHEN** `put` overwrites it with a value whose payload encodes to a different sha256
- **THEN** the `gene_values` row MUST end up pointing at the new sha256, a `gene_blobs` row MUST exist for the new sha256, and the old `gene_blobs` row MUST have been deleted inside the same transaction.

#### Scenario: Inline operations issue no blob-cleanup statement
- **GIVEN** a `gene_values` row whose payload is inline (`blob_sha256` IS NULL)
- **WHEN** a caller invokes `delete` or `put` on that id and the new payload (if any) is also inline
- **THEN** the store MUST NOT execute any `DELETE` or `SELECT` against `gene_blobs`.

### Requirement: Persistable Kind Coverage

The system SHALL persist every `Vk*` kind that the existing text serdes (`src/gene/serdes.nim`) supports, including but not limited to `VkNil`, `VkBool`, `VkInt`, `VkFloat`, `VkChar`, `VkString`, `VkSymbol`, `VkArray`, `VkMap`, `VkGene`, `VkInstance` (named-class form), `VkEnum`, `VkEnumValue`, `VkTupleValue`, and `VkCustom` values that register class hooks.

#### Scenario: Round-trip preserves nested Gene structure
- **WHEN** a `VkGene` value with properties (`^a 1 ^b "x"`) and children (`[1 2 [3 4]]`) is `put` and then `get`
- **THEN** the returned value MUST have the same kind, the same property keys and values, and the same ordered children as the original.

#### Scenario: Named instance round-trips via class hook
- **WHEN** a `VkInstance` of a class registered with `custom_serdes_hooks` is `put` and then `get`
- **THEN** the returned value MUST be an instance of the same class with the same hook-produced payload.

### Requirement: Field-Level Externalization

`put` SHALL accept an optional `^externalize` property whose value is an array of absolute child selectors using the same grammar enforced by the filesystem serdes layer (`src/gene/serdes.nim`). For each accepted selector the store SHALL encode the corresponding sub-tree of the value into its own `gene_blobs` row, replace the sub-tree in the parent payload with a stable placeholder marker, and record the mapping in a `gene_value_blobs(value_id, child_path, blob_sha256)` row. Externalized children MUST be routed to `gene_blobs` regardless of size; the developer hint MUST override the `inline_threshold` size check for the selected sub-trees. Externalized blobs MUST participate in the same content-addressed deduplication and orphan-cleanup rules as root-level detached blobs.

Selector validation MUST reject:
- selectors that are not absolute (do not begin with `/`),
- the root selector `/` (selectors must target a child),
- selectors with empty path segments,
- wildcard or legacy forms (`*`, `**`, `@`, `@@`, `!`),
- duplicate selectors within a single `put` call,
- selectors that are strict ancestors or descendants of another selector in the same call.

A selector that matches no value at write time MUST raise a typed error and MUST NOT write any row.

#### Scenario: Externalized field is written to its own blob row
- **GIVEN** an open store and a value `v` with a 10 KiB `^avatar` field whose total encoded size is also above `inline_threshold`
- **WHEN** the caller invokes `put` with `^externalize [/avatar]`
- **THEN** exactly one row MUST exist in `gene_blobs` whose `sha256` matches the encoded avatar sub-tree, exactly one row MUST exist in `gene_value_blobs` with `(value_id = id, child_path = "/avatar", blob_sha256 = <that sha>)`, and the parent payload stored in `gene_values` MUST contain a placeholder at the `/avatar` path instead of the inline avatar bytes.

#### Scenario: Externalization is independent of size threshold
- **GIVEN** a value whose `^summary` field encodes to 64 bytes (well below `inline_threshold`)
- **WHEN** the caller invokes `put` with `^externalize [/summary]`
- **THEN** the `/summary` sub-tree MUST still be written to `gene_blobs` and recorded in `gene_value_blobs`, and the parent payload stored in `gene_values` MUST contain a placeholder at the `/summary` path.

#### Scenario: Externalized field is returned lazily
- **GIVEN** an id whose value was `put` with `^externalize [/avatar]`
- **WHEN** the caller invokes `get` on that id and does not access the `/avatar` field
- **THEN** the store MUST issue at most one `SELECT` against `gene_value_blobs` keyed by `value_id`, and MUST NOT issue any `SELECT` against `gene_blobs` for the avatar's sha256.

#### Scenario: First access to an externalized field materializes exactly once
- **GIVEN** an id whose value was `put` with `^externalize [/avatar]`
- **WHEN** the caller invokes `get` on that id and then accesses the `/avatar` field two or more times
- **THEN** the store MUST issue exactly one `SELECT` against `gene_blobs` for the avatar's sha256, decode the payload, replace the per-field `VkLazyDbValue` with the materialized value, and MUST NOT re-issue the fetch for subsequent accesses.

#### Scenario: Replacing an externalized field reclaims the old blob
- **GIVEN** an id whose value was `put` with `^externalize [/avatar]` and whose avatar sub-tree is the only reference to its `gene_blobs` sha256 across both `gene_values.blob_sha256` and `gene_value_blobs.blob_sha256`
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

### Requirement: Lazy Materialization of Detached Values

`get` SHALL return a runtime-only lazy wrapper for any value whose payload lives in `gene_blobs`; the blob MUST NOT be fetched, and the payload MUST NOT be decoded, until the caller accesses the value's contents. Values stored inline MUST be returned fully materialized. The lazy wrapper MUST be invisible at the user-visible Gene type system level — callers MUST NOT be able to observe a distinct lazy "class" or "kind name" through Gene-level introspection.

#### Scenario: Inline get materializes immediately
- **GIVEN** an id whose value is stored inline
- **WHEN** `get` is invoked on that id
- **THEN** the returned value MUST be fully decoded and MUST NOT trigger any further query against `gene_blobs`.

#### Scenario: Detached get defers blob fetch
- **GIVEN** an id whose value is stored in `gene_blobs`
- **WHEN** `get` is invoked on that id and the caller does not access the value's contents
- **THEN** the store MUST NOT issue a `SELECT` against `gene_blobs` for that id.

#### Scenario: First content access materializes exactly once
- **GIVEN** an id whose value is stored in `gene_blobs`
- **WHEN** `get` is invoked on that id and the caller then iterates, indexes, or otherwise accesses the value's contents two or more times
- **THEN** the store MUST issue exactly one `SELECT` against `gene_blobs` keyed by `sha256`, decode the payload, and replace the wrapper with the materialized value so that all subsequent accesses MUST NOT re-issue the fetch.

#### Scenario: Lazy wrapper is type-transparent
- **WHEN** a caller `get`s a detached `VkMap` and queries its kind via Gene-level introspection
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

### Requirement: MySQL Build Target

The build system SHALL produce a loadable MySQL extension (`build/libmysql.dylib` on macOS, `.so` on Linux, `.dll` on Windows) from `src/genex/mysql.nim` as part of `nimble buildext`, on parity with the SQLite and PostgreSQL extensions.

#### Scenario: buildext produces MySQL artifact
- **WHEN** a developer runs `nimble buildext` on a host with MySQL client libraries available
- **THEN** the build MUST emit the MySQL shared library alongside `build/libsqlite.dylib` and `build/libpostgres.dylib`, and `(import genex/mysql)` MUST successfully load it at runtime.
