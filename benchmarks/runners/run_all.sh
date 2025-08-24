#!/bin/bash

# Unified Gene Benchmark Runner
# Runs all benchmark categories with proper organization and reporting

set -e

echo "========================================"
echo "    Gene Programming Language"
echo "    Comprehensive Benchmark Suite"
echo "========================================"
echo "Date: $(date '+%Y-%m-%d %H:%M:%S')"
echo "Host: $(hostname)"
echo "OS: $(uname -s) $(uname -r)"
echo ""

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BENCH_DIR="$(dirname "$SCRIPT_DIR")"

# Parse command line arguments
CATEGORIES=""
VERBOSE=false
PROFILE=false
COMPARE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -c|--categories)
            CATEGORIES="$2"
            shift 2
            ;;
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        -p|--profile)
            PROFILE=true
            shift
            ;;
        --compare)
            COMPARE=true
            shift
            ;;
        -h|--help)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  -c, --categories CATS    Run specific categories (comma-separated)"
            echo "                          Available: computation,allocation,data_structures,vm_internals,oop"
            echo "  -v, --verbose           Enable verbose output"
            echo "  -p, --profile           Enable profiling during benchmarks"
            echo "      --compare           Run cross-language comparisons"
            echo "  -h, --help              Show this help message"
            echo ""
            echo "Examples:"
            echo "  $0                                    # Run all benchmarks"
            echo "  $0 -c computation,allocation          # Run specific categories"
            echo "  $0 -v -p                             # Verbose with profiling"
            echo "  $0 --compare                         # Include language comparisons"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use -h or --help for usage information"
            exit 1
            ;;
    esac
done

# Default to all categories if none specified
if [ -z "$CATEGORIES" ]; then
    CATEGORIES="computation,allocation,data_structures,vm_internals,oop"
fi

# Ensure we're in the right directory
cd "$BENCH_DIR/.." || exit 1

# Check for Gene executable
GENE_CMD=""
if [ -f "./gene" ]; then
    GENE_CMD="./gene"
elif [ -f "./bin/gene" ]; then
    GENE_CMD="./bin/gene"
else
    echo "Error: Gene executable not found. Please build Gene first:"
    echo "  nimble build"
    exit 1
fi

echo "Using Gene executable: $GENE_CMD"
echo "Categories to run: $CATEGORIES"
echo ""

# Set environment variables for profiling if requested
if [ "$PROFILE" = true ]; then
    export GENE_MEMORY_STATS=1
    export GENE_POOL_STATS=1
    export GENE_TIMING_STATS=1
    echo "Profiling enabled"
    echo ""
fi

# Function to run a category
run_category() {
    local category=$1
    local runner_script="$SCRIPT_DIR/run_${category}.sh"
    
    if [ -f "$runner_script" ]; then
        echo "========================================="
        echo "Running $category benchmarks..."
        echo "========================================="
        bash "$runner_script"
        echo ""
    else
        echo "Warning: Runner script not found for category: $category"
        echo "Expected: $runner_script"
        echo ""
    fi
}

# Run each requested category
IFS=',' read -ra CATS <<< "$CATEGORIES"
for category in "${CATS[@]}"; do
    category=$(echo "$category" | xargs)  # trim whitespace
    case "$category" in
        computation|allocation|data_structures|vm_internals|oop)
            run_category "$category"
            ;;
        *)
            echo "Warning: Unknown category: $category"
            echo "Available categories: computation, allocation, data_structures, vm_internals, oop"
            echo ""
            ;;
    esac
done

# Run cross-language comparisons if requested
if [ "$COMPARE" = true ]; then
    echo "========================================="
    echo "Running cross-language comparisons..."
    echo "========================================="
    
    if [ -f "$BENCH_DIR/comparison/fibonacci_compare.sh" ]; then
        bash "$BENCH_DIR/comparison/fibonacci_compare.sh"
    fi
    
    if [ -f "$BENCH_DIR/comparison/compare_languages" ]; then
        bash "$BENCH_DIR/comparison/compare_languages"
    fi
    echo ""
fi

echo "========================================"
echo "Benchmark suite complete!"
echo "========================================"
echo ""

# Provide summary and next steps
echo "Summary:"
echo "- All requested benchmark categories have been executed"
echo "- Check individual category outputs above for detailed results"
if [ "$PROFILE" = true ]; then
    echo "- Profiling data has been collected (check memory/pool statistics)"
fi
if [ "$COMPARE" = true ]; then
    echo "- Cross-language performance comparisons included"
fi
echo ""
echo "Next steps:"
echo "- Review performance results for any regressions"
echo "- Compare with historical data if available"
echo "- Use profiling data to identify optimization opportunities"
echo "- Run specific categories with: $SCRIPT_DIR/run_<category>.sh"
