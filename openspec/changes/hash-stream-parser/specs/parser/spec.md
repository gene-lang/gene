# Parser Specification: Hash Stream Parser

## MODIFIED Requirements

### Requirement: Parse #[] as Stream Literal
The Gene parser SHALL interpret `#[]` syntax as stream literals that create `VkStream` objects instead of `VkSet` objects.

#### Scenario: Basic Stream Creation
```gene
# Create a stream with integers
(var numbers #[1 2 3 4 5])
# Should create VkStream with stream = [1, 2, 3, 4, 5]
```

#### Scenario: Empty Stream Creation
```gene
# Create an empty stream
(var empty #[])
# Should create VkStream with stream = []
```

#### Scenario: Mixed Type Stream
```gene
# Create a stream with mixed types
(var mixed #["hello" 42 true])
# Should create VkStream with stream = ["hello", 42, true]
```

### Requirement: Maintain Stream State
Created streams SHALL have proper initial state for consumption operations.

#### Scenario: Stream Initial State
```gene
(var stream #[1 2 3])
# Should have stream_index = 0 and stream_ended = false
```

### Requirement: Parser Dispatch Integration
The hash dispatch mechanism SHALL route `#[` patterns to stream creation consistently.

#### Scenario: Dispatch Consistency
```gene
# Multiple stream creations in same file
(var a #[1 2])
(var b #["a" "b"])
(var c #[true false])
# All should create VkStream objects consistently
```

## REMOVED Requirements

### Set Literal Creation
The parser shall no longer create `VkSet` objects from `#[]` syntax. The `read_set` function and `VkSet` dispatch will be removed.

## Implementation Notes

### Parser Integration Points
- File: `src/gene/parser.nim`
- Function: `read_set` → `read_stream`
- Dispatch: `dispatch_macros['['] = read_stream`

### Type System Integration
- Leverage existing `VkStream` type definition
- Use existing `new_stream_value` helper functions
- Maintain compatibility with existing stream operations

### Error Handling
- Preserve existing error handling for malformed syntax
- Handle edge cases (nested streams, empty streams)