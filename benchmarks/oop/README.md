# OOP Performance Benchmarks

This directory contains benchmarks for measuring and improving Object-Oriented Programming performance in Gene.

## Benchmarks

### 1. `class_instantiation.gene`
Measures the performance of creating class instances compared to simple map creation.
- Tests simple instantiation
- Tests instantiation with property access
- Provides baseline comparison with maps

### 2. `method_calls.gene`
Measures method call overhead and dispatch performance.
- Simple method calls
- Getter methods
- Chained/compound method calls
- Comparison with direct function calls

### 3. `property_access.gene`
Benchmarks property access patterns.
- Property reads
- Property writes
- Nested property access
- Comparison with map and array access

### 4. `oop_vs_functional.gene`
Comprehensive comparison of OOP vs functional approaches.
- Real-world example (BankAccount)
- Tests creation, simple operations, and complex operations
- Shows overall OOP overhead

## Running Benchmarks

### Run all benchmarks:
```bash
cd benchmarks/oop
./run_benchmarks.sh
```

### Run individual benchmark:
```bash
gene run benchmarks/oop/method_calls.gene
```

## Performance Metrics

Each benchmark reports:
- Total execution time
- Per-operation time (microseconds)
- Overhead ratio compared to baseline (maps/functions)

## Optimization Targets

Based on these benchmarks, key areas for optimization:

1. **Method Dispatch** - Currently the biggest overhead
   - Consider inline caching for hot methods
   - Optimize method lookup tables
   - Cache bound methods

2. **Property Access** - Moderate overhead
   - Consider property access inlining
   - Optimize instance property storage

3. **Instance Creation** - Significant overhead
   - Object pooling for frequently created classes
   - Optimize constructor dispatch

4. **Method Binding** - High overhead for bound methods
   - Cache bound methods
   - Optimize self binding

## Expected Performance

Current typical overheads (OOP vs functional/maps):
- Instance creation: 2-5x slower
- Method calls: 3-10x slower  
- Property access: 1.5-3x slower

Target improvements:
- Reduce method call overhead to < 2x
- Reduce property access to near parity
- Reduce instantiation to < 2x

## Adding New Benchmarks

To add a new benchmark:
1. Create a `.gene` file with clear test cases
2. Include baseline comparisons (maps/functions)
3. Report microseconds per operation
4. Add to `run_benchmarks.sh`

## Notes

- Benchmarks use 100,000+ iterations for statistical significance
- Warm-up iterations may be needed for JIT-like optimizations
- Results may vary based on hardware and Gene version
- Focus on relative performance ratios, not absolute times