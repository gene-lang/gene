#!/bin/bash

# Run all OOP benchmarks and generate summary

echo "=========================================="
echo "    Gene OOP Performance Benchmarks"
echo "=========================================="
echo ""
echo "Date: $(date)"
echo "Gene binary: $(which gene)"
echo ""

# Function to run a benchmark with error handling
run_benchmark() {
    local name=$1
    local file=$2
    
    echo "----------------------------------------"
    echo "Running: $name"
    echo "----------------------------------------"
    
    if [ -f "$file" ]; then
        timeout 60 gene run "$file" 2>&1 || echo "ERROR: Benchmark failed or timed out"
    else
        echo "ERROR: File not found: $file"
    fi
    
    echo ""
}

# Run each benchmark
run_benchmark "Class Instantiation" "class_instantiation.gene"
run_benchmark "Method Calls" "method_calls.gene"
run_benchmark "Property Access" "property_access.gene"
run_benchmark "OOP vs Functional" "oop_vs_functional.gene"

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