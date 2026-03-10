## ADDED Requirements

### Requirement: `gene/serdes` Can Round-Trip Values Through Logical Filesystem Paths

The system SHALL provide `gene/serdes` APIs that read and write Gene values
through logical filesystem root paths.

#### Scenario: root path defaults to one inline file

- **WHEN** `gene/serdes/write_tree` is called with a root path and no matching
  `^separate` selectors
- **THEN** it SHALL store the entire value at `<path>.gene` using Gene-native
  serialized text that `gene/serdes/read_tree` can parse back
- **AND** `gene/serdes/read_tree <path>` SHALL load the same value back

#### Scenario: explicit `.gene` root path remains inline

- **WHEN** `gene/serdes/write_tree` is called with a target path ending in
  `.gene`
- **THEN** it SHALL store the entire value in that exact file
- **AND** it SHALL reject any `^separate` selectors that require a directory
  root

### Requirement: `^separate` Selectors Control Which Logical Nodes Become Directories

The system SHALL use `^separate` selectors to choose which logical nodes store
their direct children individually.

#### Scenario: `/*` separates the root children

- **WHEN** `gene/serdes/write_tree` is called with `^separate [/*]`
- **THEN** the root SHALL be written as `<path>/`
- **AND** the root's direct children SHALL be stored as separate descendants
- **AND** descendants below those children SHALL remain inline unless matched by
  a deeper selector

#### Scenario: deeper selectors make ancestors directories

- **WHEN** `gene/serdes/write_tree` is called with `^separate [/a/*]`
- **THEN** the root SHALL be written as a directory
- **AND** `a` SHALL be written as a directory
- **AND** the direct children of `a` SHALL be stored individually

### Requirement: Exploded Arrays Preserve Order Without Positional Filenames

The system SHALL preserve exploded array order through an order manifest and
stable child ids rather than numeric index filenames.

#### Scenario: exploded array uses `_genearray.gene`

- **WHEN** an array node is written as an exploded directory
- **THEN** the directory SHALL contain `_genearray.gene`
- **AND** `_genearray.gene` SHALL contain the ordered child entry names as a
  Gene array
- **AND** the child payloads SHALL be stored under those ids instead of
  positional filenames

### Requirement: Exploded Gene Values Preserve Type, Props, And Children

The system SHALL encode exploded Gene values with explicit type, props, and
children storage.

#### Scenario: separated Gene value uses `_genetype.gene` by default

- **WHEN** a Gene value node is written as an exploded directory
- **THEN** the directory SHALL contain `_genetype.gene`
- **AND** props SHALL be stored under `_geneprops/`
- **AND** children SHALL be stored under `_genechildren/`

#### Scenario: `^separate` can target the Gene type subtree

- **WHEN** a selector such as `^separate [/a/_genetype/*]` targets the type of
  an exploded Gene node
- **THEN** the runtime SHALL treat `_genetype` as a synthetic child path within
  that Gene node
- **AND** `_genetype/` SHALL be written as an exploded structural value instead
  of `_genetype.gene`
- **AND** `gene/serdes/read_tree` SHALL load the same Gene type value back

### Requirement: Directory Decoding Uses Deterministic Markers

The system SHALL decode exploded directory roots deterministically.

#### Scenario: `read_tree` distinguishes Gene, array, and map directories

- **WHEN** `gene/serdes/read_tree` reads an exploded directory
- **THEN** `_genetype.gene` SHALL identify a Gene root
- **AND** otherwise `_genearray.gene` SHALL identify an array root
- **AND** otherwise the directory SHALL be decoded as a map root

#### Scenario: empty exploded directory decodes as map

- **WHEN** `gene/serdes/read_tree` reads an exploded directory with no
  `_genetype.gene` and no `_genearray.gene`
- **THEN** it SHALL decode the directory as a map
- **AND** an empty such directory SHALL decode as an empty map

#### Scenario: `read_tree` rejects ambiguous logical roots

- **WHEN** both `<path>.gene` and `<path>/` exist for the requested logical root
- **THEN** `gene/serdes/read_tree <path>` SHALL reject the read as ambiguous

### Requirement: Reserved Root Markers Are Documented

The system SHALL document the reserved root markers used for exploded directory
autodetection.

#### Scenario: exploded generic map roots document `_genetype` collision

- **WHEN** the exploded format uses `_genetype.gene` as a Gene root marker
- **THEN** the format SHALL document that generic exploded map roots cannot use
  a top-level entry named `_genetype` until marker escaping is added

### Requirement: Tree Serdes Is Optimized For Large State

The system SHALL implement tree serialization and deserialization through a
performance-oriented native runtime path suitable for large directory-backed
state.

#### Scenario: optimization preserves logical format

- **WHEN** the runtime optimizes `gene/serdes/write_tree` and
  `gene/serdes/read_tree`
- **THEN** it SHALL preserve the same logical file-vs-directory model,
  selector behavior, and round-trip results defined by this spec

#### Scenario: optimization can use lower-level runtime support

- **WHEN** profiling shows the existing runtime path is insufficient
- **THEN** the implementation MAY add dedicated VM/runtime support
- **AND** the public `gene/serdes/write_tree` and `gene/serdes/read_tree` API
  SHALL remain the compatibility surface
