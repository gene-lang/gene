#!/bin/bash

# Run all OOP benchmarks and generate summary

# Get the directory where this script is located
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

echo "=========================================="
echo "    Gene OOP Performance Benchmarks"
echo "=========================================="
echo ""
echo "Date: $(date)"
echo "Gene binary: $(which gene || echo "gene not in PATH")"
echo "Running from: $SCRIPT_DIR"
echo ""

# Function to run a benchmark with error handling
run_benchmark() {
    local name=$1
    local file=$2
    
    echo "----------------------------------------"
    echo "Running: $name"
    echo "----------------------------------------"
    
    local full_path="$SCRIPT_DIR/$file"
    
    if [ -f "$full_path" ]; then
        # Try to find gene executable
        if command -v gene &> /dev/null; then
            timeout 60 gene run "$full_path" 2>&1 || echo "ERROR: Benchmark failed or timed out"
        elif [ -f "$SCRIPT_DIR/../../bin/gene" ]; then
            timeout 60 "$SCRIPT_DIR/../../bin/gene" run "$full_path" 2>&1 || echo "ERROR: Benchmark failed or timed out"
        else
            echo "ERROR: gene executable not found"
        fi
    else
        echo "ERROR: File not found: $full_path"
    fi
    
    echo ""
}

# Run each benchmark
# Note: Some benchmarks require full OOP implementation to work
echo "NOTE: Running simple benchmark that works with current implementation"
echo ""
run_benchmark "Simple OOP Benchmark" "simple_oop_benchmark.gene"

# These benchmarks are ready but need OOP features to be fully implemented
# run_benchmark "Class Instantiation" "class_instantiation.gene"
# run_benchmark "Method Calls" "method_calls.gene"
# run_benchmark "Property Access" "property_access.gene"
# run_benchmark "OOP vs Functional" "oop_vs_functional.gene"

echo "=========================================="
echo "    Benchmark Suite Complete"
echo "=========================================="
echo ""
echo "Performance Improvement Opportunities:"
echo "1. Method call dispatch optimization"
echo "2. Property access caching"
echo "3. Instance creation pooling"
echo "4. Inline simple getters/setters"
echo "5. Method lookup table optimization"