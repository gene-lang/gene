## ADDED Requirements

### Requirement: Double-Brace Literals Create HashMap Values
The system SHALL interpret `{{ key1 value1 key2 value2 ... }}` as mutable `HashMap` literals with alternating key/value entries.

#### Scenario: Construct with mixed key types
- **WHEN** a program evaluates `(var x {{ 1 "one" "two" 2 [1 2] "pair" }})`
- **THEN** `x` is a `HashMap` value
- **AND** `(x .get 1)` returns `"one"`
- **AND** `(x .get "two")` returns `2`
- **AND** `(x .get [1 2])` returns `"pair"`

#### Scenario: Empty literal creates an empty HashMap
- **WHEN** a program evaluates `{{}}`
- **THEN** the result is an empty `HashMap` value

#### Scenario: Odd literal entries are rejected
- **WHEN** a program evaluates `{{ 1 "one" 2 }}`
- **THEN** execution fails with a clear runtime error indicating that `HashMap` literals expect alternating key/value entries

#### Scenario: Nested map syntax remains distinct
- **WHEN** a program evaluates `{^outer {^a 1}}`
- **THEN** the inner literal remains a normal `Map`
- **AND** no `HashMap` literal is introduced unless the braces are adjacent as `{{`

### Requirement: HashMap Uses Hash Plus Equality For Key Identity
`HashMap` lookups MUST resolve keys by computed hash and runtime `==`, so hash collisions do not alias unequal keys.

#### Scenario: Unequal keys with the same hash remain distinct
- **WHEN** two different keys produce the same `HashMap` hash but runtime `==` is false
- **THEN** storing both entries in the same `HashMap` preserves both values
- **AND** a subsequent `.get` returns the value associated with the equal key only

#### Scenario: Structurally equal composite keys resolve the same entry
- **WHEN** a program stores a value under `[1 2]` and later looks it up with another `[1 2]`
- **THEN** the `HashMap` resolves the existing entry
- **AND** lookup succeeds without requiring object identity

### Requirement: HashMap Accepts User-Defined Hashable Objects
`HashMap` SHALL accept user-defined objects as keys when the runtime can compute a hash for them via `.hash`.

#### Scenario: Custom object with hash participates in lookup
- **WHEN** a program stores a value in a `HashMap` under an object whose class defines `.hash`
- **THEN** the `HashMap` accepts the key
- **AND** `.get` with the same key object returns the stored value

#### Scenario: Unhashable key is rejected
- **WHEN** a program attempts to insert or look up a key for which `HashMap` cannot compute a hash
- **THEN** execution fails with a clear runtime error indicating the key is not hashable for `HashMap`

### Requirement: HashMap Exposes Core Mutable Map Operations
`HashMap` SHALL expose explicit collection methods for mutable arbitrary-key access.

#### Scenario: Get returns default when key is absent
- **WHEN** a program evaluates `(do (var x {{ 1 "one" }}) (x .get 2 "missing"))`
- **THEN** the result is `"missing"`

#### Scenario: Has is canonical and contains is an alias
- **WHEN** a program checks the same key with `.has` and `.contains`
- **THEN** both calls return the same membership result

#### Scenario: Set, has, delete, clear, and size work together
- **WHEN** a program mutates a `HashMap` via `.set`, checks membership via `.has`, removes an entry via `.delete`, and clears it via `.clear`
- **THEN** `.size` reflects each mutation accurately
- **AND** deleted keys are no longer present

### Requirement: HashMap Exposes Iteration Helpers
`HashMap` SHALL expose iteration helpers so callers can enumerate stored keys, values, and pairs without relying on property-map semantics.

#### Scenario: Keys, values, and pairs reflect inserted entries
- **WHEN** a program stores multiple entries in a `HashMap` and then calls `.keys`, `.values`, and `.pairs`
- **THEN** each helper returns a collection containing the stored entries
- **AND** `.pairs` preserves key/value association for each entry

#### Scenario: Iter yields each stored pair
- **WHEN** a program iterates a `HashMap` through `.iter`
- **THEN** iteration visits every stored entry exactly once
- **AND** each yielded item exposes both the key and the value for that entry

### Requirement: HashMap Renders With Double-Brace Syntax
`HashMap` SHALL render using `{{ ... }}` so printed values round-trip semantically through the literal syntax.

#### Scenario: Printed HashMap uses double braces
- **WHEN** a program prints a `HashMap`
- **THEN** the output uses `{{ ... }}` syntax with alternating key/value entries

### Requirement: Map Remains The Symbol-Keyed Property Map
The introduction of `HashMap` MUST NOT change the existing `{}` / `Map` semantics used for symbol-keyed property access.

#### Scenario: Standard map literals remain symbol-keyed
- **WHEN** a program evaluates `{^count 1}`
- **THEN** the result is a normal `Map`
- **AND** property-style access semantics remain unchanged

#### Scenario: Double-brace literals create HashMap instead of Map
- **WHEN** a program evaluates `{{ "count" 1 }}`
- **THEN** the result is a `HashMap`
- **AND** it is distinct from the `Map` created by `{^count 1}`

### Requirement: HashMap And Map Remain Independent Concrete Types
The system SHALL keep `HashMap` and `Map` as separate concrete map types with different key semantics.

#### Scenario: HashMap covers Any-to-Any while Map narrows keys to symbols
- **WHEN** a program creates `{^count 1}` and `{{ "count" 1 }}`
- **THEN** the `{{ ... }}` value accepts arbitrary keys under `HashMap`
- **AND** the `{ ... }` value remains the symbol-keyed `Map`
- **AND** `Map` preserves its narrower `Symbol -> Any` key semantics
