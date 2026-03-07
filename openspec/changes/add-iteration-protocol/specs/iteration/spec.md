## ADDED Requirements

### Requirement: Native Iteration Protocol
The runtime SHALL support a native iteration protocol based on `.iter`, `.next`, and `.next_pair`.

#### Scenario: Array value iteration
- **GIVEN** an array `[1 2 3]`
- **WHEN** code evaluates `(for x in [1 2 3] ...)`
- **THEN** the loop consumes values through an iterator contract

#### Scenario: Generator value iteration
- **GIVEN** a generator function producing values
- **WHEN** code evaluates `(for x in (counter* 3) ...)`
- **THEN** the loop consumes yielded values until `.next` returns `NOT_FOUND`

### Requirement: Pair Iteration
The runtime SHALL support pair iteration through `.next_pair`.

#### Scenario: Array index-value iteration
- **GIVEN** an array `[10 20]`
- **WHEN** code evaluates `(for [i v] in [10 20] ...)`
- **THEN** the loop binds index-value pairs from the iterator

#### Scenario: Map key-value iteration
- **GIVEN** a map `{^a 1 ^b 2}`
- **WHEN** code evaluates `(for [k v] in m ...)`
- **THEN** the loop binds key-value pairs from the iterator

### Requirement: Selector Iterable Expansion
Selector expansion SHALL consume iterable values through the same protocol when direct container expansion is not available.

#### Scenario: Selector expands generator values
- **GIVEN** a generator yielding maps with `^name`
- **WHEN** code evaluates `(@*/name generator)`
- **THEN** selector `*` consumes the generator and returns collected names
