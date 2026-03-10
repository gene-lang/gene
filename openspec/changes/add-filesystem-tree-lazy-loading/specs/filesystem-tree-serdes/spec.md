## ADDED Requirements

### Requirement: `read_tree` Can Keep Selected Logical Nodes Lazy

The system SHALL allow callers to mark logical filesystem-tree nodes that remain
backed by the stored tree until accessed.

#### Scenario: `^lazy` uses absolute node selectors

- **WHEN** `gene/serdes/read_tree` is called with `^lazy [/]`,
  `^lazy [/sessions]`, or `^lazy [/sessions/archive]`
- **THEN** the `^lazy` entries SHALL be interpreted as absolute logical node
  selectors
- **AND** the selectors SHALL identify the node itself rather than requiring a
  trailing `/*`

#### Scenario: lazy read preserves the same logical value

- **WHEN** `gene/serdes/read_tree` is called with `^lazy [/sessions]`
- **THEN** it SHALL expose the same logical root value that an eager
  `gene/serdes/read_tree` would return
- **AND** the runtime MAY defer loading the `/sessions` node until it is
  accessed

#### Scenario: lazy session subtree loads touched item on demand

- **WHEN** `/sessions` is stored as an exploded directory whose direct children
  are separate filesystem entries and `gene/serdes/read_tree` is called with
  `^lazy [/sessions]`
- **THEN** accessing `/sessions/session-123` SHALL materialize the requested
  `session-123` entry on demand
- **AND** sibling session entries SHALL remain unloaded until they are accessed

#### Scenario: separate inline child file can still be deferred

- **WHEN** a lazy-selected node is backed by a separate inline child file such
  as `sessions.gene`
- **THEN** the runtime MAY defer opening and parsing that file until the node is
  accessed
- **AND** once accessed it SHALL materialize the full inline value eagerly

#### Scenario: no filesystem boundary falls back to eager behavior

- **WHEN** a lazy-selected node is stored inside an already parsed inline
  `.gene` payload with no separate filesystem boundary
- **THEN** `gene/serdes/read_tree` SHALL still succeed
- **AND** that node SHALL behave eagerly because no finer-grained lazy load is
  possible

#### Scenario: nested lazy selectors remain lazy after parent access

- **WHEN** `gene/serdes/read_tree` is called with
  `^lazy [/sessions /sessions/archive]`
- **AND** code accesses `/sessions`
- **THEN** the resulting `/sessions` value SHALL still preserve lazy behavior
  for `/sessions/archive`

### Requirement: Directory-Backed Lazy Nodes Load Minimal Navigation Metadata

The system SHALL keep directory-backed lazy nodes cheap to open by loading only
the metadata required to navigate them.

#### Scenario: lazy map defers child payloads

- **WHEN** a lazy-selected map node is backed by an exploded directory
- **THEN** the runtime SHALL load the entry names needed to address its direct
  children
- **AND** child payloads SHALL remain unloaded until accessed

#### Scenario: lazy array uses `_genearray.gene` for navigation

- **WHEN** a lazy-selected array node is backed by an exploded directory
- **THEN** the runtime SHALL load `_genearray.gene` to determine child order
  and length
- **AND** array element payloads SHALL remain unloaded until accessed

#### Scenario: lazy Gene node defers type, props, and children payloads

- **WHEN** a lazy-selected Gene value is backed by an exploded directory
- **THEN** the runtime SHALL use the existing Gene directory markers to
  recognize the node and navigate `_geneprops/` and `_genechildren/`
- **AND** `_genetype`, prop values, and child payloads SHALL remain unloaded
  until accessed

### Requirement: Lazy Materialization Is Transparent And Memoized

The system SHALL make lazy tree loading behave like ordinary values once a
caller begins using the loaded tree.

#### Scenario: repeated access reuses the materialized descendant

- **WHEN** the same lazy-loaded descendant is accessed more than once through a
  single `read_tree` result
- **THEN** the runtime SHALL reuse the previously materialized in-memory value
  for that descendant

#### Scenario: lightweight metadata queries do not require child payload loads

- **WHEN** code asks for map keys, map size, or array length on a
  directory-backed lazy node
- **THEN** the runtime SHALL answer from already loaded navigation metadata when
  that metadata is sufficient
- **AND** it SHALL NOT require loading unrelated child payloads

#### Scenario: traversal-compatible operations can force additional loads

- **WHEN** code iterates, serializes, or writes a value that contains lazy nodes
- **THEN** the operation SHALL observe the same logical data as an eager read
- **AND** the runtime MAY materialize any descendants required to complete that
  operation

#### Scenario: lazy read remains read-through only

- **WHEN** code mutates a value returned by `gene/serdes/read_tree` with
  `^lazy [...]`
- **THEN** the mutation SHALL affect the in-memory value only
- **AND** the backing filesystem tree SHALL remain unchanged until an explicit
  `gene/serdes/write_tree`

#### Scenario: `write_tree` materializes remaining lazy descendants in v1

- **WHEN** `gene/serdes/write_tree` receives a value that still contains lazy
  descendants originating from `gene/serdes/read_tree ^lazy [...]`
- **THEN** it SHALL write the same logical value that an eager read would have
  produced
- **AND** it MAY materialize any remaining lazy descendants needed to do so
