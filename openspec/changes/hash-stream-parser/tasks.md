# Tasks: Hash Stream Parser

## Ordered Implementation Tasks

### Phase 1: Core Parser Implementation
1. **Replace read_set with read_stream function** (Priority: High)
   - File: `src/gene/parser.nim`
   - Replace `read_set` function with `read_stream` that creates `VkStream`
   - Ensure proper initialization of `stream`, `stream_index`, and `stream_ended` fields
   - Validation: Create basic test with `#[]` syntax

2. **Update dispatch macro registration** (Priority: High)
   - File: `src/gene/parser.nim`
   - Change `dispatch_macros['['] = read_set` to `dispatch_macros['['] = read_stream`
   - Validation: Test parser correctly routes `#[` to stream creation

3. **Remove or comment out VkSet references** (Priority: Medium)
   - File: `src/gene/parser.nim`
   - Remove or comment out `read_set` function
   - Clean up any unused VkSet-related code
   - Validation: Build should succeed without VkSet references

### Phase 2: Testing and Validation
4. **Create basic stream syntax tests** (Priority: High)
   - Location: `tmp/` or `testsuite/`
   - Test empty stream creation: `#[]`
   - Test integer stream: `#[1 2 3]`
   - Test mixed type stream: `#["hello" 42 true]`
   - Validation: All tests should pass without exceptions

5. **Test stream state initialization** (Priority: Medium)
   - Verify `stream_index = 0` on creation
   - Verify `stream_ended = false` on creation
   - Test with various stream contents
   - Validation: Stream objects should have correct initial state

6. **Test stream assignment and usage** (Priority: Medium)
   - Test variable assignment: `(var x #[1 2 3])`
   - Test function arguments: `(fn test [s] (println s)) (test #[1 2])`
   - Test return values: `(fn create [] #[1 2])`
   - Validation: Streams should work in all expression contexts

### Phase 3: Integration and Polish
7. **Update error handling and edge cases** (Priority: Medium)
   - Test malformed syntax: `#[1 2` (missing closing bracket)
   - Test nested structures: `#[[1] [2]]`
   - Test large streams: `#[1 2 3 4 5 6 7 8 9 10]`
   - Validation: Should provide clear error messages

8. **Performance validation** (Priority: Low)
   - Test memory usage with large streams
   - Compare performance before/after change
   - Ensure no regressions in parsing speed
   - Validation: Performance should be comparable or better

### Phase 4: Documentation and Examples
9. **Update documentation and examples** (Priority: Low)
   - Update any references to `#[]` as sets
   - Create examples showing stream usage patterns
   - Update error messages to reference streams instead of sets
   - Validation: Documentation should accurately reflect new behavior

## Dependencies and Prerequisites

- **Prerequisite**: Gene build environment must be working
- **Dependency**: Existing `VkStream` type implementation
- **Dependency**: Understanding of current parser dispatch mechanism

## Validation Criteria

### Success Criteria
- `#[]` syntax creates `VkStream` objects instead of `VkSet`
- All existing tests continue to pass
- No memory leaks or GC issues
- Clear error messages for malformed syntax
- Performance comparable to existing array parsing

### Definition of Done
- Tasks 1-3 completed (parser implementation)
- Tasks 4-6 completed (basic functionality working)
- Tasks 7-8 completed (edge cases and performance validated)
- Optional: Task 9 completed (documentation updated)

## Risk Mitigation

### Potential Issues
- **Breaking Change**: Since `VkSet` throws TODO, minimal impact
- **Memory Management**: Use existing stream memory management patterns
- **Performance**: Stream creation should be as fast as array creation

### Rollback Plan
- Keep original `read_set` function commented out for reference
- Simple change to revert dispatch macro registration
- No complex compiler changes needed