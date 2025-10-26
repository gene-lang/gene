# Async Proposal Changelog

## 2025-10-26: Removed CPS Transformation, Simplified to Polling-Based Approach

### Summary

Updated the async proposal to remove CPS (Continuation-Passing Style) transformation and VM suspension in favor of a simpler polling-based approach. This significantly reduces implementation complexity while still achieving concurrent I/O.

### Key Changes

#### 1. **Design Philosophy**
- **Before:** Complex CPS transformation with state machines and VM suspension
- **After:** Simple polling-based await that blocks but polls event loop

#### 2. **Implementation Complexity**
- **Before:** ~2000+ LOC (CPS compiler + VM suspension)
- **After:** ~200-300 LOC (event loop polling + await polling)

#### 3. **Timeline**
- **Before:** 10-19 weeks total (5 phases)
- **After:** 4-7 weeks total (4 phases, Phase 0 already complete)

#### 4. **Await Behavior**
- **Before:** True VM suspension - execution yields to event loop, resumes later
- **After:** Polling-based blocking - `await` blocks but polls event loop continuously

### What Was Removed

1. **Phase 2: CPS Compiler Transformation (3-6 weeks)**
   - Async function detection
   - State machine generation
   - Continuation point splitting
   - Variable capture across await points

2. **Phase 3: VM Suspension (2-4 weeks)**
   - Frame state serialization
   - Continuation restoration
   - Suspension/resumption mechanism

### What Remains

1. **Phase 0: Scope Fix** ✅ COMPLETED
   - Fixed scope lifetime bug
   - All tests pass

2. **Phase 1: Event Loop Integration (1-2 weeks)**
   - Add `asyncdispatch.poll()` to VM main loop
   - Wrap Nim futures in Gene FutureObj
   - Implement callbacks

3. **Phase 2: Polling-Based Await (1 week)**
   - Modify `IkAwait` to poll while future is pending
   - Sync Nim future state to Gene FutureObj

4. **Phase 3: I/O Conversion (1-2 weeks)**
   - Convert I/O functions to async versions
   - File, network, timer operations

5. **Phase 4: Testing & Validation (1-2 weeks)**
   - Concurrency tests
   - Performance benchmarks
   - Stress tests

### Trade-offs

#### Advantages of Polling Approach
- ✅ Much simpler implementation (~10x less code)
- ✅ Easier to debug and maintain
- ✅ No complex compiler changes needed
- ✅ Still achieves concurrent I/O (main use case)
- ✅ Faster to implement (4-7 weeks vs 10-19 weeks)

#### Limitations
- ⚠️ `await` blocks current execution (no true VM suspension)
- ⚠️ Cannot interleave sync code during await
- ⚠️ Event loop only progresses during polling

#### Why This Is Good Enough
- 90% of async use cases are concurrent I/O
- Event loop continues processing other futures during await
- Multiple concurrent operations still overlap
- Can add CPS later if truly needed (but probably won't be)

### Example: How It Works

```gene
# Start 3 concurrent file reads
(var f1 (async (file_read_async "file1.txt")))
(var f2 (async (file_read_async "file2.txt")))
(var f3 (async (file_read_async "file3.txt")))

# All 3 I/O operations are now pending and running concurrently

# Await first future - polls event loop while waiting
(var content1 (await f1))  # Blocks here, but f2 and f3 continue

# Await second future
(var content2 (await f2))  # May already be complete

# Await third future
(var content3 (await f3))  # May already be complete

# Total time: ~100ms (limited by slowest I/O)
# vs 300ms with synchronous I/O
```

### Files Updated

1. **openspec/changes/add-real-async-support/proposal.md**
   - Marked Phase 0 as completed
   - Updated timeline to 4-7 weeks
   - Clarified "No CPS" in design principles
   - Updated risk assessment

2. **openspec/changes/add-real-async-support/design.md**
   - Removed Decision 2 (CPS Transformation)
   - Removed Decision 3 (Frame Suspension)
   - Replaced with Decision 2 (Polling-Based Await)
   - Updated architecture comparison
   - Simplified migration plan to 4 phases

3. **openspec/changes/add-real-async-support/tasks.md**
   - Marked Phase 0 as completed
   - Removed Phase 2 (CPS Compiler) - 38 tasks
   - Removed Phase 3 (VM Suspension) - 20 tasks
   - Replaced with Phase 2 (Polling-Based Await) - 13 tasks
   - Renumbered remaining phases
   - Updated total time estimate

### Next Steps

With Phase 0 complete and the proposal simplified, the next step is:

**Phase 1: Event Loop Integration**
- Add `asyncdispatch.poll()` to VM main loop
- Wrap Nim futures in FutureObj
- Implement one async I/O function as proof of concept

Estimated time: 1-2 weeks

