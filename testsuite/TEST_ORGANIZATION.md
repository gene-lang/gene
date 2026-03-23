# Gene Test Suite Organization

This document describes how `testsuite/run_tests.sh` organizes and executes the runnable Gene tests.

## Execution Model

The main runner executes spec-aligned top-level sections in a fixed order:

1. `01-syntax/`
2. `02-types/`
3. `03-expressions/`
4. `04-control-flow/`
5. `05-functions/`
6. `06-collections/`
7. `07-oop/`
8. `08-modules/`
9. `09-errors/`
10. `10-async/`
11. `11-generators/`
12. `12-patterns/`
13. `13-regex/`
14. `14-stdlib/`
15. `15-serialization/`

Each section may contain nested subdirectories. The runner walks the tree recursively and executes only files whose basename starts with a numeric prefix such as `1_` or `10_`.

Separate command suites are invoked through their own scripts:

- `pipe/run_tests.sh`
- `examples/run_tests.sh`
- `fmt/run_tests.sh` exists but is currently not called by the default runner

Non-spec or not-yet-adopted coverage can live outside the numbered sections, for example under `experimental/`. Those files are not part of the default spec-aligned run.

## File Naming

Runnable Gene tests follow numeric prefixes for stable ordering:

- `1_*.gene`, `2_*.gene`, ..., `10_*.gene`, etc. for runnable section tests
- `001_*.gene` style names for the pipe command suite

Helper files may live in the same directory and are not always standalone tests. Examples:

- `08-modules/imports/math_lib.gene`
- `08-modules/imports/string_lib.gene`
- `08-modules/imports/fn_ns_lib.gene`
- `15-serialization/serdes_objects.gene`

## Metadata

The runner understands these file headers:

- `# Expected:` for output assertions
- `# ExitCode:` for non-zero or otherwise specific exit expectations
- `# Args:` for extra CLI arguments

Tests without `# Expected:` are treated as smoke tests and only need to exit with the expected code.

## Coverage Shape

The runnable suite is organized first by spec section, then by local feature grouping inside each section:

- syntax and literal behavior in `01-syntax/`
- type-system behavior in `02-types/`
- core expression/operator behavior in `03-expressions/`
- function and scope behavior in `05-functions/`
- object model behavior in `07-oop/`
- async behavior in `10-async/`
- stdlib behavior in `14-stdlib/`
- serialization behavior in `15-serialization/`
- CLI-oriented behavior in `pipe/`, `examples/`, and `fmt/`

Some features still rely more heavily on Nim tests than on `testsuite/` coverage. In particular:

- some thread internals and edge cases
- destructuring and pattern-matching edge cases
- native codegen and wasm internals
