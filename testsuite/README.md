# Gene Test Suite

The Gene test suite combines runnable `.gene` programs, command-suite scripts, and Nim-level unit tests. This directory focuses on executable Gene programs that validate current language and stdlib behavior through the `bin/gene` CLI.

## Layout

Primary feature categories:

- `basics/` — literals, variables, numbers, Gene values
- `control_flow/` — `if`, loops, `do`, `case`, `ifel`
- `operators/` — arithmetic, comparison, `is`, precedence, infix lowering
- `arrays/`, `maps/`, `strings/` — core collection/string behavior
- `functions/`, `types/`, `contracts/`, `scopes/` — callable behavior, gradual typing, and scope rules
- `oop/`, `callable_instances/` — classes, inheritance, AOP, unified object behavior
- `async/`, `futures/`, `generators/` — async I/O, futures, generators, spawn/await flows
- `imports/` — module loading, namespace exports, comptime import behavior
- `stdlib/` — top-level stdlib coverage plus nested `core/`, `arrays/`, `strings/`, `io/`, and `time/` groups
- `native/` — runtime-native dispatch coverage
- `pipe/`, `examples/`, `fmt/` — command-focused suites with their own runners

Helper modules and fixtures live alongside the tests where needed, for example:

- `imports/math_lib.gene`
- `imports/string_lib.gene`
- `stdlib/serdes_objects.gene`
- `fixtures/`

## Running Tests

Run the main Gene testsuite:

```bash
cd testsuite
./run_tests.sh
```

Run selected test files:

```bash
cd testsuite
./run_tests.sh types/5_property_types.gene async/7_spawn_var_assignment.gene
```

Run command-specific suites directly:

```bash
testsuite/pipe/run_tests.sh
testsuite/examples/run_tests.sh
testsuite/fmt/run_tests.sh
```

## Test Conventions

Gene test files use comment-based metadata:

- `# Expected:` — expected output line(s)
- `# ExitCode:` — expected process exit code
- `# Args:` — extra CLI args passed to `bin/gene run`

If a file has no `# Expected:` lines, the runner only checks that it exits successfully.

## Coverage Notes

This directory is not the whole test story:

- `tests/` contains Nim unit tests for parser/compiler/VM internals
- some features are covered in both places
- some lower-level behaviors currently exist only in Nim tests

Examples today:

- thread messaging APIs are primarily covered in `tests/test_thread.nim`
- destructuring edge cases are primarily covered in `tests/test_pattern_matching.nim`
- wasm/native pipeline internals are covered in dedicated Nim tests
