# Gene VM Performance Analysis & Optimization Plan

**Date**: 2026-01-01  
**Baseline Performance**:
- `fib(24)`: 0.025 seconds
- Function calls: ~ 7.5 million/second

## Performance Comparison

| Language | Function calls/sec |
|----------|-------------------|
| Python 3 | ~2-4 million |
| **Gene** | **~7.5 million** |
| Lua 5.4 | ~15-25 million |
| LuaJIT | ~100+ million |

Gene performance is **better than Python** but slower than Lua. For a relatively new VM, this is a solid baseline.

---

## Current Architecture Strengths

- ✅ **NaN-boxed values** (8 bytes) - excellent for cache efficiency
- ✅ **Frame pooling** already implemented (`FRAMES` pool with reuse)
- ✅ **Many `{.push checks: off.}`** pragmas in hot paths

---

## Key Bottlenecks Identified

### 1. Scope Allocation (High Impact)

Every function call creates a new Scope via `alloc0(sizeof(ScopeObj))`. Unlike frames, scopes have **no pooling**:

```nim
# value_core.nim:1363-1368
proc new_scope*(tracker: ScopeTracker): Scope =
  result = cast[Scope](alloc0(sizeof(ScopeObj)))  # <- allocation every call!
  result.ref_count = 1
  result.tracker = tracker
  result.members = newSeq[Value]()  # <- second allocation!
```

**Proposed Fix**: Add scope pooling like frames:

```nim
var SCOPES* {.threadvar.}: seq[Scope]

proc new_scope*(tracker: ScopeTracker): Scope {.inline.} =
  if SCOPES.len > 0:
    result = SCOPES.pop()
    result.reset()  # Clear members, set ref_count
  else:
    result = cast[Scope](alloc0(sizeof(ScopeObj)))
  result.ref_count = 1
  result.tracker = tracker
```

### 2. Members Sequence Allocation (Medium Impact)

Each scope calls `newSeq[Value]()` which heap-allocates. For small functions (1-5 local vars), use a fixed inline array + spill to heap:

```nim
type
  ScopeObj* = object
    # ... other fields
    local_count: int8
    local_storage: array[8, Value]  # Inline for 0-8 locals
    overflow: seq[Value]            # Spill if > 8
```

### 3. Dispatch Table vs Case Statement (Medium-High Impact)

The VM uses a large `case` statement. Consider using a **threaded interpreter** with computed gotos or a jump table:

```nim
# Current (many branches):
case inst.kind:
of IkPushValue: ...
of IkAdd: ...

# Potential (direct dispatch):
const DISPATCH = [proc_push_value, proc_add, ...]
DISPATCH[inst.kind.ord](vm, inst)
```

### 4. Inline More Aggressively (Low Effort)

Mark these as `{.inline.}`:
- `new_scope`
- Stack push/pop operations
- Frequently called argument accessors

### 5. Reference Counting Overhead (Medium Impact)

`ref_count.inc()` / `ref_count.dec()` happens very frequently. Consider:
- Batch reference counting updates
- Use deferred refcount for locals (release at scope end)

---

## Quick Wins Checklist

| Optimization | Impact | Effort | Status |
|-------------|--------|--------|--------|
| Scope pooling | High | Low | ✅ **DONE - 3x improvement!** |
| Inline member array (8 slots) | Medium | Low | ❌ Tested - wrapper overhead negates benefit |
| `{.inline.}` on hot procs | Medium | Very Low | ✅ Done - most already had inline |
| Frame pooling cleanup | Low | Low | ⬜ TODO |
| Reduce `new_scope` for leaf fns | Medium | Medium | ⬜ TODO |
| Computed goto dispatch | High | High | ✅ Already using `{.computedGoto.}` |

### Scope Pooling Results (2026-01-01)

```
zero-arg: 16.1M calls/sec
one-arg:  12.1M calls/sec
four-arg:  8.0M calls/sec
```

---

## Profiling Suggestions

Add instrumentation to measure:
1. Time spent in `new_scope` vs `new_frame`
2. `ref_count` operations per function call
3. Dispatch overhead (case statement vs hypothetical jump table)
4. Cache miss rates for instruction fetch

---

## Implementation Priority

### Phase 1: Low-Hanging Fruit (1-2 days)
1. Scope pooling (reuse like frames)
2. Add `{.inline.}` to hot paths
3. Inline storage for small scopes

### Phase 2: Medium Effort (3-5 days)
1. Deferred reference counting for locals
2. Optimize leaf function calls (skip scope creation)
3. Instruction fusion for common patterns

### Phase 3: Major Refactoring (1-2 weeks)
1. Threaded dispatch / computed gotos
2. JIT compilation for hot loops
3. Inline caching for method dispatch

---

## Target Goals

| Metric | Current | Target | Stretch |
|--------|---------|--------|---------|
| Function calls/sec | 5.5M | 10M | 20M |
| `fib(24)` time | 25ms | 15ms | 8ms |
| Memory per call | TBD | -50% | -75% |
