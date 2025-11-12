# Type System Specification: Hash Stream Parser

## MODIFIED Requirements

### Requirement: Stream Type Support
The type system SHALL fully support `VkStream` objects created from `#[]` syntax with proper memory management and garbage collection.

#### Scenario: Stream Memory Management
```gene
(var stream #[1 2 3 4 5])
# Stream should be properly managed by GC
# Should not leak memory when stream goes out of scope
```

#### Scenario: Stream State Persistence
```gene
(var stream #[1 2 3])
(stream .stream_index)  # Should return 0
(stream .stream_ended) # Should return false
```

### Requirement: Stream Operations Compatibility
All existing `VkStream` operations SHALL work with stream literals created from `#[]` syntax.

#### Scenario: Stream Access Patterns
```gene
(var stream #[1 2 3 4 5])
# Should support existing stream operations
# Any existing stream methods should work correctly
```

## ADDED Requirements

### Requirement: Stream Equality and Comparison
Stream objects SHALL support equality comparison operations.

#### Scenario: Stream Equality
```gene
(var a #[1 2 3])
(var b #[1 2 3])
(var c #[3 2 1])
(== a b)  # Should return true
(== a c)  # Should return false
```

### Requirement: Stream Serialization
Stream objects SHALL be serializable to GIR format and deserializable back to identical streams.

#### Scenario: Stream Roundtrip
```gene
(var original #[1 2 3])
# Should serialize to GIR and deserialize back to identical stream
# Stream state should be preserved during roundtrip
```

## Implementation Notes

### Type System Integration
- No changes needed to `VkStream` type definition
- Leverage existing `stream`, `stream_index`, `stream_ended` fields
- Ensure proper GC integration for stream objects

### Memory Management
- Use existing ref-counting mechanisms
- Ensure stream arrays are properly managed
- Test for memory leaks in stream creation/destruction

### Compiler Integration
- Update any `VkSet` compilation paths to handle `VkStream`
- Ensure stream literals work in all expression contexts
- Test stream usage in variable assignments, function calls, etc.