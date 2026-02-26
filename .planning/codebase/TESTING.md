# Testing Patterns

**Analysis Date:** 2026-02-26

## Test Framework

**Runner:**
- Nim `unittest` for core test files (`tests/test_*.nim`)
- Project-level aggregation through `nimble test` task in `gene.nimble`

**Assertion Library:**
- Nim unittest built-ins (`suite`, `test`, `check`, `fail`)
- Helper wrappers/macros in `tests/helpers.nim` (`test_vm`, `test_parser`, `test_vm_error`)

**Run Commands:**
```bash
nimble test                                  # curated Nim test matrix
nim c -r tests/test_parser.nim               # single Nim test file
nim c -r tests/test_async.nim                # feature-specific test file
./testsuite/run_tests.sh                     # black-box Gene source tests
./testsuite/run_tests.sh testsuite/basics/1_literals.gene   # targeted testsuite run
```

## Test File Organization

**Location:**
- Nim tests in `tests/`
- Black-box language tests in `testsuite/`

**Naming:**
- Nim tests: `test_<feature>.nim` (for example `test_oop.nim`, `test_stdlib_sqlite.nim`)
- Testsuite files: numbered feature files (`1_*.gene`, `2_*.gene`) inside category directories

**Structure:**
```
tests/
  helpers.nim
  test_basic.nim
  test_parser.nim
  test_async.nim
  fixtures/

testsuite/
  basics/1_literals.gene
  control_flow/1_if.gene
  stdlib/*
  run_tests.sh
```

## Test Structure

**Suite Organization:**
```nim
import unittest
import ./helpers

suite "Feature name":
  test_vm """
    (gene code)
  """, expectedValue
```

**Patterns:**
- Shared initialization through `init_all()` in `tests/helpers.nim`
- Parser and VM behavior tested separately with dedicated helper wrappers
- Behavior-driven test names embedded in test helper call sites

## Mocking

**Framework:**
- No centralized mocking framework detected
- Tests mostly execute real parser/compiler/vm paths

**Patterns:**
- Controlled test fixtures in `tests/fixtures/`
- Conditional execution for environment-dependent tests (for example postgres)
- Small in-test helpers and converters in `tests/helpers.nim`

**What to Mock/Isolate:**
- External services are usually isolated by environment checks (for example `GENE_TEST_POSTGRES_URL`)
- LLM tests can use mock backend flags (`GENE_LLM_MOCK` compile define)

## Fixtures and Factories

**Test Data:**
- Reusable fixture files under `tests/fixtures/`
- In-memory factories/converters in `tests/helpers.nim` (`to_value` converters and test function registration)

**Location:**
- `tests/helpers.nim`: central helper and initialization logic
- `tests/fixtures/`: file-based fixtures
- `testsuite/*`: executable language-level examples with expected-output comments

## Coverage

**Requirements:**
- No enforced numeric coverage gate found
- Quality bar is passing curated test matrix plus testsuite

**Configuration:**
- Coverage tool configuration not found in root config
- CI validates build + tests instead of explicit coverage thresholds

## Test Types

**Unit/Component Tests:**
- Parser/compiler/vm/type-system focused tests in `tests/`
- Fast feedback on individual runtime subsystems

**Integration Tests:**
- Command-level and stdlib integration tests in `tests/` (CLI, db, async, native, threads)
- Optional environment-specific tests for Postgres and LLM-related functionality

**End-to-End Language Tests:**
- `testsuite/` executes `.gene` programs against `bin/gene` and checks expected output/exit code

## Common Patterns

**Async Testing:**
- Async/future behavior validated through VM execution wrappers (`tests/test_async.nim`, `tests/test_future_callbacks.nim`)

**Error Testing:**
- Dedicated helpers for expected exceptions (`test_parser_error`, `test_vm_error`)
- Command tests frequently assert failure paths and error message behavior

**Snapshot Testing:**
- Snapshot test infrastructure not detected; assertions are explicit and value-driven

---
*Testing analysis: 2026-02-26*
*Update when test patterns change*
