# Gene Performance Guide

This document covers performance analysis, comparisons, and optimization strategies for the Gene VM.

## Current Performance

### Benchmark Results (fib(24) - 150,049 function calls)

| Language | Time (seconds) | Calls/second | Relative Speed |
|----------|---------------|--------------|----------------|
| Node.js  | 0.001         | 150,049,000  | 245x           |
| Ruby     | 0.004         | 35,074,800   | 57x            |
| Python   | 0.006         | 25,138,012   | 41x            |
| Gene VM (optimized) | 0.040 | 3,765,818 | 6.2x    |
| Gene VM (baseline) | 0.245 | 611,694   | 1x      |

**Note**: None of these languages implement automatic memoization - all make the full 150,049 calls.

### Recent Optimizations (2025)

- **Value Type Optimization**: 21.6% improvement by removing copy/destroy overhead
- **POD Type Implementation**: Zero-cost integer/float operations
- **Manual Reference Counting**: Explicit memory management with retain/release

### Performance by Platform

- macOS ARM64: ~3.76M calls/sec (optimized)
- macOS x86_64: ~297K calls/sec (baseline)
- Linux ARM64 (Vagrant): ~3.6M calls/sec (optimized)
- Under Valgrind: ~10-12K calls/sec (expected slowdown)

## Bottleneck Analysis

### Current Profiling Results (2025)

Total instructions: **6,495,289** (7.3% reduction from baseline)

Top hotspots from callgrind analysis:

1. **Memory Allocation (9.04%)** - Reduced from 15.46%
   - rawAlloc operations: 4.69% + 4.35%
   - Frame pooling achieving 99.3% reuse rate
   - Still the primary bottleneck

2. **Type Checking (1.96%)** - Reduced from 7.85%
   - Value::kind() operations
   - Significantly improved with POD Value type
   - Inline caching opportunity

3. **VM Execution (0.98%)** - Reduced from 11.19%
   - Highly efficient dispatch loop
   - Computed goto optimization
   - Minimal overhead

4. **Value Operations (0%)** - Eliminated!
   - No more eqcopy_/eqdestroy_ overhead
   - POD type with zero-cost copies
   - Direct bit manipulation

### Cache Performance
- Instruction cache miss rate: 3.08%
- Data cache miss rate: 1.3%
- Last-level cache miss rate: 0.2%

Good cache performance indicates algorithmic rather than memory access issues.

## Immediate Optimization Opportunities

Based on current profiling data, these optimizations can be implemented immediately:

### 1. Array/Sequence Pooling (Expected: 5-8% improvement)
```nim
# Pool common array sizes to reduce allocation overhead
var ARRAY_POOLS: Table[int, seq[seq[Value]]]

proc new_array_pooled(size: int): seq[Value] =
  let bucket = next_power_of_2(size)
  if bucket in ARRAY_POOLS and ARRAY_POOLS[bucket].len > 0:
    result = ARRAY_POOLS[bucket].pop()
    result.setLen(size)
  else:
    result = newSeq[Value](size)
```

### 2. String Interning (Expected: 2-3% improvement)
```nim
# Cache common strings and symbols
var STRING_INTERN_TABLE: Table[string, ptr String]

proc intern_string(s: string): ptr String =
  if s in STRING_INTERN_TABLE:
    result = STRING_INTERN_TABLE[s]
    result.ref_count.inc()
  else:
    result = new_str(s)
    STRING_INTERN_TABLE[s] = result
```

### 3. Inline Caching for Type Checks (Expected: 1-2% improvement)
```nim
# Cache the last type seen at each kind() call site
type TypeCache = object
  last_value: uint64
  last_kind: ValueKind

var TYPE_CACHES: array[1024, TypeCache]  # Indexed by call site

template kind_cached(v: Value, cache_id: static int): ValueKind =
  let u = cast[uint64](v)
  if TYPE_CACHES[cache_id].last_value == u:
    TYPE_CACHES[cache_id].last_kind
  else:
    let k = kind(v)
    TYPE_CACHES[cache_id] = TypeCache(last_value: u, last_kind: k)
    k
```

## Optimization Strategies

### 1. Quick Wins (10-30% improvement each)

**Inline Critical Functions**
```nim
template kind_fast(v: Value): ValueKind {.inline.} =
  when NimMajor >= 2:
    {.cast(noSideEffect).}: v.kind
  else:
    v.kind
```

**Pool Common Objects**
```nim
var frame_pool: seq[Frame]
var array_pool: Table[int, seq[seq[Value]]]

proc new_frame_pooled(): Frame =
  if frame_pool.len > 0:
    result = frame_pool.pop()
    result.reset()
  else:
    result = Frame()
```

**Optimize Instruction Dispatch**
```nim
# Use computed goto if available
template dispatch() =
  when defined(computedGoto):
    goto labels[instructions[pc].kind]
  else:
    case instructions[pc].kind
```

### 2. Medium-term Improvements (2-5x speedup)

**Inline Caching**
- Cache method lookups at call sites
- Monomorphic inline caches first
- Polymorphic caches for hot paths

**Specialized Instructions**
```nim
# Instead of: IkPush 1, IkPush 2, IkAdd
# Generate: IkAddImm 1 2
```

**Type Specialization**
- Generate specialized code for common types
- Avoid boxing for primitive operations
- Fast paths for integer arithmetic

### 3. Long-term Architecture (10x+ speedup)

**Just-In-Time Compilation**
- Identify hot functions
- Generate native code
- Inline small functions

**Register-based VM**
- Reduce stack manipulation
- Better instruction-level parallelism
- Easier to JIT compile

**Escape Analysis**
- Stack-allocate non-escaping objects
- Eliminate unnecessary allocations
- Scalar replacement of aggregates

## Profiling Tools

### Built-in Profilers

1. **Simple Profiler** (`src/benchmark/simple_profile.nim`)
   - Shows bytecode statistics
   - Instruction distribution

2. **Trace Profiler** (`src/benchmark/trace_profile.nim`)
   - Captures instruction traces
   - Useful for debugging

3. **VM Profiler** (`src/benchmark/vm_profile.nim`)
   - Detailed instruction timing
   - Identifies hot instructions

### External Tools

**macOS**
```bash
# Instruments
instruments -t "Time Profiler" ./gene run script.gene

# Sample
sample gene 1000 -file samples.txt
```

**Linux**
```bash
# Perf
perf record -g ./gene run script.gene
perf report

# Valgrind
valgrind --tool=callgrind ./gene run script.gene
kcachegrind callgrind.out
```

## Optimization Checklist

When optimizing Gene code:

1. **Profile First**
   - Measure before optimizing
   - Focus on hot paths
   - Use appropriate tools

2. **Algorithm Level**
   - Better algorithms beat micro-optimizations
   - Reduce unnecessary work
   - Cache computed results

3. **VM Level**
   - Minimize allocations
   - Reduce function calls
   - Use efficient data structures

4. **Code Patterns**
   ```gene
   # Avoid
   (map (fnx [x] (+ x 1)) list)
   
   # Prefer (when available)
   (map .+ list 1)
   ```

## Benchmarking

### Running Benchmarks
```bash
# Basic benchmark
./scripts/benchme

# Compare with other languages
./scripts/fib_compare

# Custom benchmark
nim c -d:release src/benchmark/custom.nim
```

### Writing Benchmarks
```nim
import times, strformat

let start = cpu_time()
# ... code to benchmark ...
let duration = cpu_time() - start
echo fmt"Time: {duration:.6f} seconds"
```

## Performance Roadmap 2025

### Completed Optimizations ✓
- Value type as POD (21.6% improvement)
- Removed copy/destroy overhead
- Manual reference counting
- Frame pooling (99.3% reuse rate)

### Phase 1: Memory Optimization (Q1 2025)
**Target**: 5M calls/sec (33% improvement)
- [ ] Array/sequence pooling by size
- [ ] String interning for common strings
- [ ] Arena allocators for temporary objects
- [ ] Generational pools for different lifetimes

### Phase 2: VM Enhancements (Q2 2025)
**Target**: 10M calls/sec (2x improvement)
- [ ] Superinstructions for common patterns
- [ ] Basic inline caching
- [ ] Type feedback collection
- [ ] Profile-guided optimization

### Phase 3: JIT Compilation (Q3-Q4 2025)
**Target**: 50M+ calls/sec (10x improvement)
- [ ] Template-based JIT for hot functions
- [ ] Type specialization
- [ ] Method inlining
- [ ] Native code generation

### Long Term Vision (2026+)
**Target**: Match V8/LuaJIT performance
- [ ] Tiered compilation (interpreter → baseline JIT → optimizing JIT)
- [ ] Advanced optimizations (escape analysis, SROA)
- [ ] SIMD vectorization
- [ ] Concurrent GC

## Monitoring Progress

Track these metrics:
- Instructions per second
- Function calls per second  
- Memory allocations per operation
- Cache hit rates
- Benchmark execution times

Regular benchmarking against reference implementations (Ruby, Python, Lua) ensures Gene remains competitive.