## ADDED Requirements

### Requirement: HashSet Constructs Through The Class Constructor
The system SHALL provide `HashSet` as a mutable arbitrary-value set constructed through `(new HashSet item1 item2 item3 ...)`.

#### Scenario: Construct with initial members
- **WHEN** a program evaluates `(var s (new HashSet 1 "two" [3 4]))`
- **THEN** `s` is a `HashSet` value
- **AND** `(s .has 1)` returns `true`
- **AND** `(s .has "two")` returns `true`
- **AND** `(s .has [3 4])` returns `true`

#### Scenario: Empty constructor creates an empty HashSet
- **WHEN** a program evaluates `(new HashSet)`
- **THEN** the result is an empty `HashSet`

#### Scenario: Duplicate constructor members collapse to one stored member
- **WHEN** a program evaluates `(var s (new HashSet 1 1 1))`
- **THEN** `(s .size)` returns `1`

### Requirement: HashSet Uses Hash Plus Equality For Member Identity
`HashSet` membership MUST resolve members by computed hash and runtime `==`, so hash collisions do not alias unequal values.

#### Scenario: Unequal members with the same hash remain distinct
- **WHEN** two different values produce the same `HashSet` hash but runtime `==` is false
- **THEN** adding both members preserves both entries
- **AND** membership tests succeed only for the equal member being checked

#### Scenario: Structurally equal composite members resolve the same entry
- **WHEN** a program adds `[1 2]` and later checks membership with another `[1 2]`
- **THEN** the `HashSet` resolves the existing member
- **AND** `(s .size)` does not increase for the structurally equal duplicate

### Requirement: HashSet Accepts User-Defined Hashable Objects
`HashSet` SHALL accept user-defined objects as members when the runtime can compute a hash for them via `.hash`.

#### Scenario: Custom object with hash participates in membership
- **WHEN** a program adds an object whose class defines `.hash`
- **THEN** the `HashSet` accepts the member
- **AND** `.has` with the same key object returns `true`

#### Scenario: Unhashable member is rejected
- **WHEN** a program attempts to add or check a member for which `HashSet` cannot compute a hash
- **THEN** execution fails with a clear runtime error indicating the value is not hashable for `HashSet`

### Requirement: HashSet Exposes Core Mutable Set Operations
`HashSet` SHALL expose explicit collection methods for mutable membership operations.

#### Scenario: Has is canonical and contains is an alias
- **WHEN** a program checks the same member with `.has` and `.contains`
- **THEN** both calls return the same membership result

#### Scenario: Add, delete, clear, and size work together
- **WHEN** a program mutates a `HashSet` via `.add`, removes a member via `.delete`, and clears it via `.clear`
- **THEN** `.size` reflects each mutation accurately
- **AND** deleted members are no longer present

#### Scenario: Delete returns removed member or nil
- **WHEN** a program deletes a present member and then deletes a missing member
- **THEN** the first call returns the removed member
- **AND** the second call returns `nil`

### Requirement: HashSet Exposes Iteration Helpers
`HashSet` SHALL expose iteration helpers so callers can enumerate stored members without reaching into internal storage.

#### Scenario: To_array returns the stored members
- **WHEN** a program stores multiple members in a `HashSet` and calls `.to_array`
- **THEN** the result is an array containing the stored members

#### Scenario: For-loop iteration visits each stored member once
- **WHEN** a program iterates a `HashSet` in a `for` loop
- **THEN** iteration visits every stored member exactly once

### Requirement: HashSet Exposes Set Algebra
`HashSet` SHALL expose standard set algebra helpers that return new `HashSet` values or membership booleans as appropriate.

#### Scenario: Union, intersect, and diff produce derived sets
- **WHEN** a program evaluates `.union`, `.intersect`, and `.diff` across two `HashSet` values
- **THEN** each operation returns a new `HashSet`
- **AND** the returned members match the standard set operation semantics

#### Scenario: Subset checks containment across sets
- **WHEN** a program evaluates `(a .subset? b)`
- **THEN** the result is `true` only when every member of `a` is present in `b`

### Requirement: HashSet Renders With Constructor Syntax
`HashSet` SHALL render using `(HashSet ...)` so printed values align with the public constructor form.

#### Scenario: Printed HashSet uses constructor-style output
- **WHEN** a program prints a `HashSet`
- **THEN** the output uses `(HashSet item1 item2 item3 ...)` syntax
