## ADDED Requirements

### Requirement: Hash-Bracket Literals Create Immutable Arrays
The Gene parser SHALL interpret `#[...]` syntax as immutable array literals.

#### Scenario: Immutable array with elements
- **WHEN** the parser reads `#[1 2 3]`
- **THEN** it produces an array value containing `1`, `2`, and `3`
- **AND** the array is marked immutable

#### Scenario: Empty immutable array
- **WHEN** the parser reads `#[]`
- **THEN** it produces an empty array value
- **AND** the array is marked immutable

### Requirement: Immutable Arrays Reject In-Place Mutation
Immutable arrays MUST reject operations that would mutate their contents or length.

#### Scenario: Append is rejected
- **WHEN** a program evaluates `(do (var xs #[1 2]) (xs .add 3))`
- **THEN** execution fails with a clear runtime error indicating the array is immutable

#### Scenario: Indexed assignment is rejected
- **WHEN** a program evaluates `(do (var xs #[1 2]) (xs/0 = 9))`
- **THEN** execution fails with a clear runtime error indicating the array is immutable

### Requirement: Immutable Arrays Remain Readable Array Values
Immutable arrays SHALL behave like normal arrays for non-mutating operations.

#### Scenario: Reads and aliasing preserve contents
- **WHEN** a program evaluates `(do (var xs #[1 2]) (var ys xs) [ys/0 ys/1])`
- **THEN** it reads the original elements successfully
- **AND** no mutation occurs through aliasing

### Requirement: Hash-Bracket Syntax No Longer Denotes Streams
The system SHALL no longer treat `#[...]` as stream literal syntax.

#### Scenario: Former stream literal syntax now yields immutable array
- **WHEN** a program evaluates `#[1 2]`
- **THEN** the result is an immutable array value
- **AND** it is not a `VkStream`
