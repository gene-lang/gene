# Gene Test Suite Organization

## Test Naming Convention

All test files follow a numbered prefix pattern:
- `1_*.gene` - Most basic/fundamental tests
- `2_*.gene` - Secondary features
- `3_*.gene` - More advanced features
- etc.

## Test Execution Order

The `run_tests.sh` script executes tests in this specific order:

### 1. Basic Literals & Variables
- `1_literals.gene` - Basic literal values (numbers, strings, booleans, nil, symbols)
- `2_variables.gene` - Variable declaration and assignment
- `3_numbers.gene` - Number operations and arithmetic
- `4_genes.gene` - Gene expressions (S-expressions)

### 2. Control Flow
- `1_if.gene` - If-else conditions
- `2_loops.gene` - Loop structures (loop, while, break, continue)
- `3_do_blocks.gene` - Do blocks and scoping

### 3. Operators
- `1_arithmetic.gene` - Arithmetic operations (+, -, *, /)
- `2_comparison.gene` - Comparison operators (<, <=, >, >=, ==, !=)

### 4. Data Structures

#### Arrays
- `1_basic_arrays.gene` - Array creation, access, modification

#### Maps
- `1_basic_maps.gene` - Map creation, access, modification

#### Strings
- `1_basic_strings.gene` - String literals and operations

### 5. Functions & Scopes
- `functions/1_basic_functions.gene` - Function definitions and calls
- `scopes/1_basic_scopes.gene` - Variable scoping and shadowing

### 6. Standard Library

#### Core (`stdlib/core`)
- `1_print_and_assert.gene` - Core namespace printing helpers and assertions
- `2_base64.gene` - Base64 encode/decode helpers

#### Strings (`stdlib/strings`)
- `1_string_methods.gene` - String length, casing, and append methods

#### Arrays (`stdlib/arrays`)
- `1_array_methods.gene` - Array size, add, and indexed access

#### IO (`stdlib/io`)
- `1_file_io.gene` - Read/write helpers (sync and async)

#### Time (`stdlib/time`)
- `1_sleep_and_now.gene` - time/now with sync and async sleep helpers

## Running Tests

### Run all tests in order:
```bash
cd testsuite
./run_tests.sh
```

### Run individual test:
```bash
../bin/gene run basics/1_literals.gene
```

### Run tests for a specific feature:
```bash
for f in arrays/*.gene; do ../bin/gene run "$f"; done
```

## Test Output

The test runner provides:
- Color-coded results (green = pass, red = fail)
- Feature grouping with section headers
- Summary statistics with pass rate
- Truncated error messages for failures

## Adding New Tests

When adding new tests:
1. Use the next available number prefix in the feature directory
2. Keep tests focused on a single feature/concept
3. Use `print` statements instead of assertions
4. End each test with a completion message
5. Avoid features that are not yet implemented

## Current Test Coverage

| Feature | Tests | Status |
|---------|-------|--------|
| Basic Literals | 4 | ✅ Working |
| Control Flow | 3 | ✅ Working |
| Operators | 2 | ✅ Working |
| Arrays | 1 | ✅ Working |
| Maps | 1 | ✅ Working |
| Strings | 1 | ✅ Working |
| Functions | 1 | ✅ Working |
| Scopes | 1 | ✅ Working |

Total: 14 working test files
