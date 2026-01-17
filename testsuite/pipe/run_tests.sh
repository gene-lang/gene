#!/bin/bash
# Test runner for gene pipe command

cd "$(dirname "$0")/../.."

GENE_BIN="./bin/gene"
PASS=0
FAIL=0

echo "Running gene pipe tests..."
echo

# Function to run a test from a .gene file
run_pipe_test() {
    local test_file=$1
    local test_num=$2
    local test_name=$(basename "$test_file" .gene)

    # Extract input command (e.g., "echo \"test\"" from "# Input: echo \"test\"")
    local input_cmd=$(grep "^# Input:" "$test_file" | head -1 | sed 's/^# Input: //')

    # Extract code (e.g., "$line" from "# Code: $line")
    local code=$(grep "^# Code:" "$test_file" | head -1 | sed 's/^# Code: //')

    # Extract all expected output lines (handle both "# Expected: value" and "# Expected:" for empty lines)
    local expected=$(grep "^# Expected:" "$test_file" | sed 's/^# Expected:[[:space:]]*//')

    if [ -z "$input_cmd" ] || [ -z "$code" ]; then
        echo "Test $test_num: Skipping $test_name (missing Input or Code)"
        return
    fi

    echo "Test $test_num: ${test_name//_/ }"

    # Run the test
    local result=$(eval "$input_cmd" | $GENE_BIN pipe "$code" 2>&1)

    # Compare output
    if [ "$result" = "$expected" ]; then
        echo "  ✓ PASS"
        ((PASS++))
    else
        echo "  ✗ FAIL"
        echo "  Expected:"
        echo "$expected" | sed 's/^/    /'
        echo "  Got:"
        echo "$result" | sed 's/^/    /'
        ((FAIL++))
    fi
}

# Run all numbered test files
test_num=1
for test_file in testsuite/pipe/[0-9]*.gene; do
    if [ -f "$test_file" ]; then
        run_pipe_test "$test_file" "$test_num"
        test_num=$((test_num + 1))
    fi
done

# Test --filter option with string equality
echo "Test $test_num: Filter option (string equality)"
result=$(echo -e "keep\nskip\nkeep" | $GENE_BIN pipe --filter '($line == "keep")')
expected='keep
keep'
if [ "$result" = "$expected" ]; then
    echo "  ✓ PASS"
    ((PASS++))
else
    echo "  ✗ FAIL"
    echo "  Expected:"
    echo "$expected" | sed 's/^/    /'
    echo "  Got:"
    echo "$result" | sed 's/^/    /'
    ((FAIL++))
fi
test_num=$((test_num + 1))

# Test --filter option with length check
echo "Test $test_num: Filter option (length check)"
result=$(echo -e "hello\nhi\nworld" | $GENE_BIN pipe --filter '($line/.size > 4)')
expected='hello
world'
if [ "$result" = "$expected" ]; then
    echo "  ✓ PASS"
    ((PASS++))
else
    echo "  ✗ FAIL"
    echo "  Expected:"
    echo "$expected" | sed 's/^/    /'
    echo "  Got:"
    echo "$result" | sed 's/^/    /'
    ((FAIL++))
fi
test_num=$((test_num + 1))

# Test error handling separately (should exit with error)
echo "Test $test_num: Error handling"
if echo "bad" | $GENE_BIN pipe '(throw "error")' 2>/dev/null; then
    echo "  ✗ FAIL: Should have exited with error"
    ((FAIL++))
else
    echo "  ✓ PASS: Correctly exited with error"
    ((PASS++))
fi

# Summary
echo
echo "========================================"
echo "Results: $PASS passed, $FAIL failed"
echo "========================================"

if [ $FAIL -gt 0 ]; then
    exit 1
fi
