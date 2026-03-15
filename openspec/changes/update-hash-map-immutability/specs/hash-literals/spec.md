## ADDED Requirements

### Requirement: Hash-Brace Literals Create Immutable Maps
The Gene parser SHALL interpret `#{...}` syntax as immutable map literals.

#### Scenario: Immutable map with entries
- **WHEN** the parser reads `#{^a 1 ^b 2}`
- **THEN** it produces a map value containing keys `a` and `b`
- **AND** the map is marked immutable

#### Scenario: Empty immutable map
- **WHEN** the parser reads `#{}`
- **THEN** it produces an empty map value
- **AND** the map is marked immutable

### Requirement: Immutable Maps Reject In-Place Mutation
Immutable maps MUST reject operations that would mutate their entries.

#### Scenario: Map.set is rejected
- **WHEN** a program evaluates `(do (var m #{^a 1}) (m .set "a" 2))`
- **THEN** execution fails with a clear runtime error indicating the map is immutable

#### Scenario: Property assignment is rejected
- **WHEN** a program evaluates `(do (var m #{^a 1}) (m/a = 2))`
- **THEN** execution fails with a clear runtime error indicating the map is immutable

### Requirement: Immutable Maps Remain Readable Map Values
Immutable maps SHALL behave like normal maps for non-mutating operations.

#### Scenario: Reads and aliasing preserve entries
- **WHEN** a program evaluates `(do (var m #{^a 1 ^b 2}) (var n m) [n/a n/b])`
- **THEN** it reads the original values successfully
- **AND** no mutation occurs through aliasing

### Requirement: Immutable Maps Expose Frozen-State Inspection
Immutable maps SHALL expose a predicate that reports whether a map is immutable.

#### Scenario: immutable? distinguishes frozen and mutable maps
- **WHEN** a program evaluates `[(#{^a 1} .immutable?) ({^a 1} .immutable?)]`
- **THEN** the first result is `true`
- **AND** the second result is `false`

### Requirement: Hash-Brace Syntax No Longer Denotes Sets
The system SHALL reserve `#{...}` syntax for immutable maps and SHALL NOT use the same notation for sets.

#### Scenario: Immutable map syntax is unambiguous
- **WHEN** a program evaluates `#{^a 1}`
- **THEN** the result is an immutable map value
- **AND** it is not a `VkSet`
