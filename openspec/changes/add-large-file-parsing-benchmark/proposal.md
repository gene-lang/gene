## Why
Gene needs parsing performance testing with large files to identify bottlenecks, measure scalability, and establish performance baselines. Currently there are no benchmarks for parsing large (~50k lines) Gene source files.

## What Changes
- Create a tool to generate large, realistic Gene source files (~50k lines)
- Add comprehensive parsing benchmark suite with timing and memory metrics
- Implement performance profiling for parser components
- Add parsing benchmark results tracking and reporting

## Impact
- New parser performance testing capability
- Better understanding of parser scalability and bottlenecks
- Foundation for parser optimization work
- Performance regression detection system
- No changes to core parser functionality