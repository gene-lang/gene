# Design: Hash Stream Parser

## Current Implementation Analysis

### Parser Dispatch Flow
1. `#` character → `read_dispatch` function
2. `read_dispatch` looks at next character
3. `[` character → `read_set` function (creates `VkSet`)
4. `read_set` creates a set by adding items using `r.set.incl(item)`

### Current Type System
- `VkSet` exists but implementation throws TODO exception
- `VkStream` already exists with fields:
  - `stream*: seq[Value]` - underlying sequence
  - `stream_index*: int64` - current position
  - `stream_ended*: bool` - completion flag
- `new_stream_value(v: varargs[Value])` function exists

## Proposed Implementation

### Parser Changes
**File:** `src/gene/parser.nim`

1. **Replace `read_set` function** with `read_stream`:
```nim
proc read_stream(self: var Parser): Value =
  let r = new_ref(VkStream)
  let list_result = self.read_delimited_list(']', true)
  r.stream = list_result.list
  r.stream_index = 0
  r.stream_ended = false
  result = r.to_ref_value()
```

2. **Update dispatch macro registration**:
```nim
proc init_dispatch_macro_array() =
  dispatch_macros['['] = read_stream  # Changed from read_set
```

### Type System Considerations
- No changes needed to `VkStream` type definition
- Leverage existing `new_stream_value` helper function
- Maintain compatibility with existing stream operations

### Compiler Integration
- Ensure compiler can handle stream literals in expressions
- Update any `VkSet`-specific compilation logic to handle `VkStream`
- Preserve existing stream compilation pathways

## Implementation Strategy

### Phase 1: Parser Update
1. Replace `read_set` with `read_stream`
2. Update dispatch macro registration
3. Test basic stream creation and access

### Phase 2: Type System Integration
1. Verify `VkStream` operations work with new syntax
2. Test stream consumption patterns
3. Ensure garbage collection works correctly

### Phase 3: API Polish
1. Add convenience methods for stream manipulation
2. Document stream behavior and usage patterns
3. Update examples and documentation

## Error Handling
- Maintain existing error handling for malformed syntax
- Provide clear error messages for stream-related operations
- Handle edge cases (empty streams, stream exhaustion)

## Testing Strategy
1. **Unit Tests**: Test parser produces correct `VkStream` objects
2. **Integration Tests**: Verify streams work in expressions and assignments
3. **Behavioral Tests**: Test stream consumption and state management
4. **Performance Tests**: Ensure no performance regressions

## Migration Guide
Since `VkSet` implementation throws TODO exceptions, there's minimal migration impact:
1. Existing code using `#[]` will now work instead of throwing TODO
2. Future set implementation can use different syntax if needed
3. Stream operations provide more functionality than the incomplete set implementation