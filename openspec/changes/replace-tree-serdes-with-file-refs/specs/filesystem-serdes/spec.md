## ADDED Requirements

### Requirement: Unified Filesystem Serializer Public API

The system SHALL expose exactly `gene/serdes/write`, `gene/serdes/read`, `gene/serdes/read_file`, and `gene/serdes/read_dir` as the supported public filesystem serialization surface. `gene/serdes/read` SHALL be an alias for `gene/serdes/read_file`. `gene/serdes/serialize` and `gene/serdes/deserialize` SHALL remain text payload APIs and SHALL NOT become filesystem persistence APIs.

#### Scenario: one-file filesystem round trip uses write and read

- **WHEN** code writes a value with `gene/serdes/write` to a file path that does not externalize children
- **THEN** the writer SHALL store a Gene-native serialized text payload at the requested file path
- **AND** `gene/serdes/read` of that file path SHALL return the same logical value as `gene/serdes/read_file`
- **AND** the read SHALL use the same canonical text deserialization behavior as `gene/serdes/deserialize` for the file payload

#### Scenario: serialize and deserialize remain text-only

- **WHEN** code calls `gene/serdes/serialize` or `gene/serdes/deserialize`
- **THEN** those APIs SHALL operate on serialized text payloads only
- **AND** they SHALL NOT accept filesystem paths as their public persistence contract
- **AND** filesystem reads and writes SHALL go through `write`, `read`, `read_file`, or `read_dir`

#### Scenario: old tree API is not part of the filesystem surface

- **WHEN** public docs, tests, examples, or runtime namespace checks enumerate the filesystem serializer surface
- **THEN** `read_tree` and `write_tree` SHALL NOT appear as supported APIs
- **AND** any remaining mention of `read_tree` or `write_tree` SHALL identify them only as removed or superseded prior-art names

### Requirement: Serialized File And Directory References Are Explicit Deserializer Forms

Serialized payloads SHALL represent external file and directory boundaries with explicit serializer-owned forms headed by `gene/serdes/read_file` or `gene/serdes/read_dir`. The deserializer SHALL dispatch these forms using the containing serialized file as path context and SHALL NOT evaluate them as arbitrary Gene runtime calls.

#### Scenario: read_file ref resolves relative to containing file

- **GIVEN** a serialized file at `state/root.gene` contains `(gene/serdes/read_file "sessions/a.gene")`
- **WHEN** `gene/serdes/read_file "state/root.gene"` deserializes that payload
- **THEN** the nested ref SHALL resolve `sessions/a.gene` relative to `state/`
- **AND** the nested file SHALL be deserialized as a serialized payload, not evaluated as source code

#### Scenario: read_dir ref resolves relative to containing file

- **GIVEN** a serialized file at `state/root.gene` contains `(gene/serdes/read_dir "sessions" ^shape ^map ^order ^name)`
- **WHEN** `gene/serdes/read_file "state/root.gene"` deserializes that payload
- **THEN** the nested directory ref SHALL resolve `sessions` relative to `state/`
- **AND** the result SHALL use the `read_dir` shape and ordering contract

#### Scenario: serializer-dispatched refs do not execute arbitrary Gene code

- **GIVEN** a serialized payload contains a Gene form whose head is not an accepted serializer-owned ref form
- **WHEN** the payload is deserialized
- **THEN** the deserializer SHALL treat that form according to the canonical serialized-data format
- **AND** it SHALL NOT invoke user-defined functions, macros, methods, or module loading as arbitrary runtime evaluation while resolving file refs

#### Scenario: malformed ref options are rejected

- **WHEN** a serialized `read_file` or `read_dir` ref contains an unknown keyword, duplicate keyword, non-boolean `^lazy`, unsupported `^shape`, unsupported `^order`, or the wrong arity
- **THEN** deserialization SHALL reject the payload with a diagnostic that includes the ref kind and containing-file context

### Requirement: File References Are Eager By Default And Support Explicit Lazy Loading

`read_file` and serialized `read_file` refs SHALL load and validate their targets eagerly by default. When `^lazy true` is supplied, the system SHALL return a transparent lazy value that behaves like the loaded value on normal access and caches the materialized value after first successful load.

#### Scenario: eager read_file surfaces missing target immediately

- **GIVEN** `state/root.gene` contains `(gene/serdes/read_file "missing.gene")` without `^lazy true`
- **WHEN** `state/root.gene` is read
- **THEN** deserialization SHALL fail before returning the parent value
- **AND** the diagnostic SHALL identify the missing target and the containing file

#### Scenario: lazy read_file defers target I/O until access

- **GIVEN** `state/root.gene` contains `(gene/serdes/read_file "large.gene" ^lazy true)`
- **WHEN** `state/root.gene` is read
- **THEN** the result MAY contain a transparent lazy placeholder for `large.gene`
- **AND** normal access to that placeholder SHALL materialize the target value
- **AND** repeated access through the same placeholder SHALL reuse the cached materialized value

#### Scenario: lazy failure is reported at materialization time

- **GIVEN** a lazy file ref targets a missing, unsafe, or invalid file
- **WHEN** code first accesses the lazy value in a way that requires materialization
- **THEN** the access SHALL fail with a diagnostic that includes the target path and the original containing-file context
- **AND** the failure SHALL NOT be converted to `nil`

### Requirement: Directory References Support Shape And Name Ordering

`read_dir` and serialized `read_dir` refs SHALL eagerly load a directory-backed collection using explicit options for result shape and ordering. The supported shapes SHALL include `array` and `map`. The supported order mode SHALL be deterministic name order.

#### Scenario: read_dir returns an ordered array

- **GIVEN** a directory contains serialized child files
- **WHEN** code reads it with `(gene/serdes/read_dir "events" ^shape array ^order name)`
- **THEN** the result SHALL be an array
- **AND** child files SHALL be read in deterministic filename order

#### Scenario: read_dir returns a keyed map

- **GIVEN** a directory contains serialized child files named `a.gene` and `b.gene`
- **WHEN** code reads it with `(gene/serdes/read_dir "sessions" ^shape map ^order name)`
- **THEN** the result SHALL be a map keyed by deterministic child identifiers derived from the file names
- **AND** each map value SHALL be deserialized from the matching child file

#### Scenario: invalid directory targets fail closed

- **WHEN** `read_dir` targets a missing path, a regular file, an unreadable directory, a directory containing invalid serialized payloads, or a path that fails safety checks
- **THEN** the read SHALL fail with a diagnostic that identifies the directory target and containing-file context when present
- **AND** it SHALL NOT silently return an empty collection or `nil`

#### Scenario: unsupported directory options fail closed

- **WHEN** a `read_dir` call or serialized `read_dir` ref requests an unsupported shape, unsupported order such as creation-time ordering, or `^lazy true`
- **THEN** the read SHALL fail with a diagnostic that identifies the unsupported option
- **AND** it SHALL NOT return a partially loaded, lazily backed, or unstably ordered collection

### Requirement: Path Safety And Cycle Detection Are Fail-Closed

Filesystem serializer reads SHALL resolve nested relative refs against the containing serialized file's directory, reject unsafe paths by default, and reject file/directory reference cycles before unbounded recursion or repeated I/O occurs.

#### Scenario: absolute nested path is rejected by default

- **GIVEN** a serialized file contains `(gene/serdes/read_file "/etc/passwd")`
- **WHEN** the file is deserialized under the default path policy
- **THEN** the nested ref SHALL be rejected as an unsafe absolute path
- **AND** the diagnostic SHALL include the containing file and target path

#### Scenario: traversal path escape is rejected by default

- **GIVEN** a serialized file at `state/root.gene` contains `(gene/serdes/read_file "../secret.gene")`
- **WHEN** that file is deserialized under the default path policy
- **THEN** the nested ref SHALL be rejected as a path escape
- **AND** the implementation SHALL NOT open the escaped target

#### Scenario: generated or manifest child ids are treated as untrusted

- **GIVEN** directory-backed reads or writer-generated child names produce child identifiers
- **WHEN** a child identifier is empty, absolute, contains a path separator, contains traversal segments, or otherwise escapes the owning directory
- **THEN** the serializer SHALL reject the id before joining it with the directory path
- **AND** it SHALL NOT read or write outside the owning directory

#### Scenario: file reference cycle is rejected

- **GIVEN** `a.gene` contains `(gene/serdes/read_file "b.gene")`
- **AND** `b.gene` contains `(gene/serdes/read_file "a.gene")`
- **WHEN** `a.gene` is read eagerly
- **THEN** deserialization SHALL reject the cycle with a diagnostic that includes the ref chain
- **AND** it SHALL NOT recurse indefinitely

#### Scenario: directory cycle is rejected

- **GIVEN** a directory-backed read would revisit an ancestor file or directory through nested `read_file`, `read_dir`, symlink, or equivalent filesystem indirection
- **WHEN** the read is performed
- **THEN** the serializer SHALL reject the cycle with a diagnostic that identifies the repeated path

### Requirement: Writer Externalizes Selected Sub-Values With Deterministic References

`gene/serdes/write` SHALL support selector-driven externalization of selected sub-values. Externalized sub-values SHALL be written to deterministic child files or directories, and the parent payload SHALL contain explicit `read_file` or `read_dir` forms that point at those child targets.

#### Scenario: write externalizes a selected map entry to a child file

- **GIVEN** a map contains a `sessions` entry selected by `^externalize`
- **WHEN** `gene/serdes/write "state/root.gene" value ^externalize [/sessions]` writes the value
- **THEN** the root file SHALL contain an explicit `read_file` or `read_dir` ref in place of the selected entry
- **AND** the selected value SHALL be written under a deterministic child target derived from the selector, key, or content hash according to the implementation's documented naming policy

#### Scenario: write externalizes directory-backed collections with read_dir refs

- **GIVEN** a selected sub-value is written as a directory-backed collection
- **WHEN** the parent payload is written
- **THEN** the parent SHALL contain `(gene/serdes/read_dir ...)` with enough options to reconstruct the chosen shape and ordering
- **AND** reading the parent SHALL round-trip to the same logical value

#### Scenario: deterministic child naming is stable across identical writes

- **WHEN** the same logical value is written twice with the same `^externalize` selectors and no intervening content changes
- **THEN** the generated child names and parent ref paths SHALL be stable
- **AND** output diffs SHALL not change due only to non-deterministic naming

#### Scenario: unsafe generated child name is rejected

- **WHEN** a selector, map key, array metadata entry, or content-derived name would produce an empty name, absolute name, traversal segment, or name containing a path separator
- **THEN** `gene/serdes/write` SHALL reject the write before touching that child path
- **AND** the diagnostic SHALL identify the selector or source value responsible for the unsafe name

#### Scenario: malformed externalization selectors are rejected

- **WHEN** `^externalize` contains a malformed selector, a selector that targets no value, duplicate/conflicting selectors, or a selector that would require an unsupported filesystem shape
- **THEN** `gene/serdes/write` SHALL fail with a diagnostic that identifies the selector
- **AND** it SHALL NOT leave a partially successful parent payload that claims the externalized ref exists

### Requirement: Old Tree Serdes Public API Is Removed Rather Than Aliased

The system SHALL remove `gene/serdes/read_tree` and `gene/serdes/write_tree` as supported public APIs. They SHALL NOT remain as compatibility aliases for `read`, `read_file`, `read_dir`, or `write`.

#### Scenario: runtime namespace omits old tree APIs

- **WHEN** the `gene/serdes` namespace is initialized after M012 implementation
- **THEN** `read_tree` and `write_tree` SHALL not be exported as supported public members
- **AND** code that attempts to call them SHALL fail with the ordinary unknown-member behavior rather than silently using the new APIs

#### Scenario: public materials do not teach old tree APIs

- **WHEN** public specs, docs, examples, tests, or GeneClaw storage helpers are scanned after migration
- **THEN** live examples SHALL use only `write`, `read`, `read_file`, and `read_dir` for filesystem serialization
- **AND** any remaining `read_tree` or `write_tree` mention SHALL be limited to migration, removal, or superseded-prior-art context

### Requirement: Implementation Approval And Verification Gates Are Required

Runtime implementation of this filesystem serializer SHALL be gated by approval of this OpenSpec change. Completion of M012 SHALL require focused filesystem-serdes tests, old API removal assertions, GeneClaw storage helper smoke tests, public cleanup checks, OpenSpec strict validation, `nimble build`, and the full language testsuite.

#### Scenario: S02 implementation waits for approval

- **WHEN** this OpenSpec change has not been reviewed and accepted
- **THEN** S02 runtime implementation SHALL NOT begin
- **AND** S01 work SHALL remain limited to contract, public spec draft, and verification gate artifacts

#### Scenario: OpenSpec validates the contract

- **WHEN** a future agent runs `openspec validate replace-tree-serdes-with-file-refs --strict`
- **THEN** the change SHALL validate successfully
- **AND** validation failures SHALL be treated as contract defects to fix, not as reasons to weaken requirements

#### Scenario: final implementation gate covers runtime and public surfaces

- **WHEN** M012 is ready for completion
- **THEN** the final gate SHALL include focused filesystem-serdes tests, old API removal assertions, GeneClaw storage helper smoke tests, public docs/spec/example cleanup checks, strict OpenSpec validation, `nimble build`, and `./testsuite/run_tests.sh`
- **AND** failures in any proof class SHALL block completion until fixed or explicitly replanned
