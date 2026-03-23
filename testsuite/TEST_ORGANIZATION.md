# Gene Test Suite Organization

This document describes how `testsuite/run_tests.sh` organizes and executes the runnable Gene tests.

## Execution Model

The main runner executes flat feature directories in a fixed order:

1. `basics/`
2. `control_flow/`
3. `operators/`
4. `arrays/`
5. `maps/`
6. `strings/`
7. `functions/`
8. `native/`
9. `contracts/`
10. `types/`
11. `scopes/`
12. `callable_instances/`
13. `oop/`
14. `async/`
15. `futures/`
16. `generators/`
17. `imports/`
18. `stdlib/`
19. `stdlib/core/`
20. `stdlib/strings/`
21. `stdlib/arrays/`
22. `stdlib/io/`

The runner currently skips `stdlib/time/` in the default pass even though those tests exist on disk.

Separate command suites are invoked through their own scripts:

- `pipe/run_tests.sh`
- `examples/run_tests.sh`
- `fmt/run_tests.sh` exists but is currently not called by the default runner

## File Naming

Runnable Gene tests follow numeric prefixes for stable ordering:

- `1_*.gene` through `9_*.gene` for most flat feature directories
- `001_*.gene` style names for the pipe command suite

Helper files may live in the same directory and are not always standalone tests. Examples:

- `imports/math_lib.gene`
- `imports/string_lib.gene`
- `imports/fn_ns_lib.gene`
- `stdlib/serdes_objects.gene`

## Metadata

The runner understands these file headers:

- `# Expected:` for output assertions
- `# ExitCode:` for non-zero or otherwise specific exit expectations
- `# Args:` for extra CLI arguments

Tests without `# Expected:` are treated as smoke tests and only need to exit with the expected code.

## Coverage Shape

The runnable suite is organized by user-visible behavior:

- syntax and basic runtime semantics in `basics/`, `operators/`, `control_flow/`
- function/type/contract behavior in `functions/`, `types/`, `contracts/`
- object model behavior in `oop/` and `callable_instances/`
- async behavior in `async/`, `futures/`, and `generators/`
- stdlib behavior in `stdlib/` and its nested subdirectories
- CLI-oriented behavior in `pipe/`, `examples/`, and `fmt/`

Some features still rely more heavily on Nim tests than on `testsuite/` coverage. In particular:

- thread messaging and reply APIs
- destructuring and pattern-matching edge cases
- native codegen and wasm internals
