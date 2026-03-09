## ADDED Requirements

### Requirement: `gene/serdes` Can Round-Trip Values Through Logical Filesystem Paths

The system SHALL provide `gene/serdes` APIs that read and write Gene values
through logical filesystem root paths.

#### Scenario: root path defaults to one inline file

- **WHEN** `gene/serdes/write_tree` is called with a root path and no matching
  `^separate` selectors
- **THEN** it SHALL store the entire value at `<path>.gene` using Gene-native
  serialized text
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

#### Scenario: exploded array uses `__order__.gene`

- **WHEN** an array node is written as an exploded directory
- **THEN** the directory SHALL contain `__order__.gene`
- **AND** `__order__.gene` SHALL contain the ordered child ids as a Gene array
- **AND** the child payloads SHALL be stored under those ids instead of
  positional filenames

### Requirement: Exploded Gene Values Preserve Type, Props, And Children

The system SHALL encode exploded Gene values with explicit type, props, and
children storage.

#### Scenario: separated Gene value uses `genetype.gene`

- **WHEN** a Gene value node is written as an exploded directory
- **THEN** the directory SHALL contain `genetype.gene`
- **AND** props SHALL be stored under `props/`
- **AND** children SHALL be stored under `children/`

### Requirement: Directory Decoding Uses Deterministic Markers

The system SHALL decode exploded directory roots deterministically.

#### Scenario: `read_tree` distinguishes Gene, array, and map directories

- **WHEN** `gene/serdes/read_tree` reads an exploded directory
- **THEN** `genetype.gene` SHALL identify a Gene root
- **AND** otherwise `__order__.gene` SHALL identify an array root
- **AND** otherwise the directory SHALL be decoded as a map root

#### Scenario: `read_tree` rejects ambiguous logical roots

- **WHEN** both `<path>.gene` and `<path>/` exist for the requested logical root
- **THEN** `gene/serdes/read_tree <path>` SHALL reject the read as ambiguous

### Requirement: Reserved Root Markers Are Documented

The system SHALL document the reserved root markers used for exploded directory
autodetection.

#### Scenario: generic exploded map roots document reserved marker collisions

- **WHEN** the exploded format uses `genetype.gene` and `__order__.gene` as
  root markers
- **THEN** the format SHALL document that generic exploded map roots cannot use
  top-level entries named `genetype` or `__order__` until marker escaping is
  added
