# Gene Test Suite

The Gene test suite combines runnable `.gene` programs, command-suite scripts, and Nim-level unit tests. This directory focuses on executable Gene programs that validate current language and stdlib behavior through the `bin/gene` CLI.

## Layout

Primary spec-aligned sections:

- `01-syntax/` — literals, variables, numbers, Gene values, basic strings
- `02-types/` — gradual typing, type flow, property types, generics
- `03-expressions/` — arithmetic, comparison, `is`, precedence, infix lowering
- `04-control-flow/` — `if`, loops, `do`, `ifel`, and case-oriented control tests
- `05-functions/` — functions plus scope-related callable behavior
- `06-collections/` — arrays and maps
- `07-oop/` — classes, inheritance, callable instances, AOP
- `08-modules/` — imports, namespace paths, comptime import behavior
- `09-errors/` — contracts plus direct throw/catch coverage
- `10-async/` — async I/O, futures, spawn/await, and thread-style reply flows
- `11-generators/` — generator behavior and iteration
- `12-patterns/` — destructuring and `case/when` pattern matching
- `13-regex/` — regex literals and regex/string helpers
- `14-stdlib/` — stdlib-focused coverage, including nested `stdlib/` and `native/`
- `15-serialization/` — tagged JSON and serdes coverage

Additional non-spec command suites and helpers:

- `pipe/`, `examples/`, `fmt/` — command-focused suites with their own runners
- `fixtures/` — shared files used by runnable tests
- `ai/` — app-specific test programs outside the core language spec
- `experimental/` — runnable tests for behavior not currently part of the spec-aligned default suite

Helper modules and fixtures live alongside the tests where needed, for example:

- `08-modules/imports/math_lib.gene`
- `08-modules/imports/string_lib.gene`
- `15-serialization/serdes_objects.gene`
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
./run_tests.sh 02-types/types/5_property_types.gene 10-async/async/7_spawn_var_assignment.gene
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

- some thread internals are still covered more deeply in `tests/test_thread.nim`
- destructuring edge cases are still covered more deeply in `tests/test_pattern_matching.nim`
- wasm/native pipeline internals are covered in dedicated Nim tests
