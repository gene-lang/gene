# Change: Hash Stream Parser

**Status:** Draft
**Created:** 2025-11-12
**Author:** Claude
**Type:** Enhancement

## Problem Statement

Currently, the Gene parser treats `#[]` syntax as a set literal (`VkSet`), but the set implementation is incomplete and throws a TODO exception. The language would benefit more from a stream literal syntax that provides sequential data access, which is more useful for streaming data processing, pipelines, and lazy evaluation patterns.

## Proposed Solution

Change the parser to interpret `#[]` as a stream literal (`VkStream`) instead of a set literal (`VkSet`). This leverages the existing `VkStream` type and provides better semantic meaning for sequential data processing.

## Benefits

- **Functional Programming Support**: Streams enable lazy evaluation and functional programming patterns
- **Data Pipeline Patterns**: Better support for processing data sequentially (map, filter, reduce operations)
- **Memory Efficiency**: Streams can be consumed incrementally without loading all data into memory
- **Semantic Clarity**: `#[]` better represents a flow/stream of data rather than an unordered collection
- **API Consistency**: Aligns with existing stream-related functionality in the language

## Impact Analysis

- **Breaking Change**: This is a breaking change for any code using `#[]` (though current implementation throws TODO exception)
- **Backward Compatibility**: Minimal impact since `VkSet` is not fully implemented
- **Performance**: Stream creation is lightweight and efficient
- **Learning Curve**: Simple concept for developers familiar with streams from other languages

## Questions for Clarification

1. Should we preserve any set-related syntax for future set implementation (e.g., `#{}` or different syntax)?
A: No, let's focus on stream for now.
2. Are there specific stream operations we want to prioritize (map, filter, reduce, take, drop)?
A: let's focus on the parser change for now.
3. Should streams be immutable or allow mutation?
A: Immutable