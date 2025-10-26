# Change Proposal: Integrate Streaming Compilation

## Summary
Improve the integration between parsing and compilation to work more closely together while maintaining distinct phases. The flow will parse one item, immediately compile it, and continue until all items are processed, with proper error handling that stops at the first failure.

## Problem Statement
Currently, the parsing and compilation phases are somewhat disconnected. While there is a `parse_and_compile` function that implements streaming compilation, error handling and integration could be improved to:

1. Provide better error reporting that clearly identifies where failures occur (parse vs compile)
2. Stop immediately on parse or compile errors instead of continuing
3. Ensure the streaming approach is used consistently across all commands
4. Provide better debugging and tracing capabilities for the streaming flow

## Proposed Solution
Enhance the existing `parse_and_compile` function to be the primary compilation path across all commands with:

- **Improved error handling**: Distinguish between parse errors and compile errors with clear location information
- **Immediate failure behavior**: Stop compilation immediately on first error
- **Consistent streaming flow**: Use parse-then-compile-then-repeat pattern consistently
- **Enhanced debugging**: Better trace and debugging support for streaming compilation

## Scope
This change focuses on the compilation pipeline:

- **In scope**: Parser-compiler integration, error handling, command integration
- **Out of scope**: Changes to VM execution, language syntax, or new language features

## Related Changes
- This builds on the existing `parse_and_compile` function in `src/gene/compiler.nim`
- No conflicts with current ongoing workstreams

## Success Criteria
1. All commands (`run`, `eval`, `compile`) use consistent streaming compilation
2. Parse and compile errors are clearly distinguished and reported with location info
3. Compilation stops immediately on first error
4. Debugging and tracing work properly with the streaming approach
5. All existing tests continue to pass