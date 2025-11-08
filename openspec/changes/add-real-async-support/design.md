# Design: Real Async Support

## Context

Gene's VM is a stack-based bytecode interpreter written in Nim. The current async implementation provides syntax but no actual concurrency - all operations complete synchronously. Nim provides robust async capabilities through `asyncdispatch`, `asyncfile`, and `asyncnet`, but Gene doesn't integrate with these primitives.

**Current State:**
- VM runs in single thread with no event loop
- `IkAsyncEnd` (vm.nim:4088) completes futures immediately
- I/O uses blocking `readFile()` instead of `asyncfile.readFile()`
- ✅ Scope lifetime fixed - `IkScopeEnd` now correctly uses ref-counting

**Stakeholders:**
- Gene language users expecting real async semantics
- VM maintainers concerned about complexity
- Performance-sensitive applications needing concurrent I/O

**Constraints:**
- Must maintain backward compatibility with async syntax
- Cannot introduce multi-threading (VM is single-threaded)
- Must not degrade performance for non-async code
- **No CPS transformation** - Keep implementation simple
- **No VM suspension** - `await` blocks but event loop continues

## Goals / Non-Goals

### Goals
1. **True Concurrency**: Multiple I/O operations execute concurrently
2. **Event Loop**: Integrate Nim's `asyncdispatch` for scheduling
3. **Polling-based Await**: `await` polls event loop while waiting
4. **Non-Blocking I/O**: Replace synchronous I/O with async primitives
5. **Scope Safety**: ✅ DONE - Fixed scope lifetime to support pending futures
6. **Callback Support**: Implement `.on_success()` / `.on_failure()` chaining

### Non-Goals
1. **CPS Transformation**: Too complex, not needed for concurrent I/O
2. **VM Suspension/Resumption**: `await` blocks but event loop continues
3. **Multi-threading**: Async is concurrent (single-thread), not parallel
4. **Async Generators**: Defer to future work
5. **Custom Schedulers**: Use Nim's asyncdispatch exclusively
6. **Distributed Futures**: No RPC or remote async
7. **WASM Integration**: Defer to separate effort

## Decisions

### Decision 1: Wrapper vs Native Future

**Chosen Approach:** Wrap Nim's `Future[Value]` inside `FutureObj`

**Rationale:**
- Gene's `Value` type is discriminated union (not generic)
- Nim's `Future[T]` requires monomorphic type parameter
- Wrapping allows Gene-level API to remain unchanged
- Nim async primitives return `Future[T]`, need translation layer

**Alternative Considered:** Replace `FutureObj` entirely with Nim `Future[Value]`
- Would require changing all Gene code using futures
- Breaks API compatibility
- Doesn't provide enough benefit to justify breaking change

**Implementation:**
```nim
type FutureObj* = ref object
  nim_future*: Future[Value]    # Wrap Nim's Future
  state*: FutureState           # Mirror for Gene-level access
  value*: Value                 # Cached result when complete
  success_callbacks*: seq[Value]
  failure_callbacks*: seq[Value]
```

### Decision 2: Await Execution Strategy

**Chosen Approach:** Polling-based blocking await with event loop integration

**Rationale:**
- Simple to implement - no CPS transformation needed
- `await` blocks current execution but event loop continues processing
- Other pending futures make progress while waiting
- Maintains straightforward VM execution model
- Good enough for 90% of async use cases

**Alternative Considered:** CPS transformation with VM suspension
- Would require complex compiler changes (state machines, continuation generation)
- Would require VM suspension/resumption mechanism
- Much higher implementation complexity (~2000+ LOC vs ~300 LOC)
- Not needed for concurrent I/O (main use case)

**Implementation Pattern:**
```nim
# In IkAwait handler:
let future = pop_future()
while future.state == FsPending:
  asyncdispatch.poll(timeout = 0)  # Process other futures
  # Check if future completed
if future.state == FsSuccess:
  push(future.value)
else:
  raise future.exception
```

### Decision 3: Event Loop Integration

**Chosen Approach:** Poll event loop periodically in VM main loop

**Rationale:**
- VM already has main execution loop
- Poll event loop between instruction batches
- Non-blocking poll keeps VM responsive
- Allows mixing async and sync code

**Implementation:**
```nim
# Main VM loop:
while self.running:
  # Execute instructions (batch of ~100)
  for i in 0..<100:
    self.step()

  # Poll async event loop (non-blocking)
  asyncdispatch.poll(timeout = 0)
```

**Alternative Considered:** Dedicated event loop thread
- Would require thread synchronization
- Violates single-threaded constraint
- More complex debugging

### Decision 4: Scope Lifetime Management

**Status:** ✅ COMPLETED

**Chosen Approach:** Scope reference counting - only free when ref_count == 0

**Rationale:**
- Scopes are manually ref-counted
- `IkScopeEnd` calls `scope.free()` which decrements and checks
- Scope only deallocated when ref_count reaches 0
- Maintains existing ref counting infrastructure
- No need for full GC integration

**Implementation:**
```nim
# In IkScopeEnd (vm.nim:970):
of IkScopeEnd:
  var old_scope = self.frame.scope
  self.frame.scope = self.frame.scope.parent
  old_scope.free()  # Decrements and only frees if ref_count == 0
```

**Testing:** All scope lifetime tests pass - futures can safely capture scopes.

### Decision 5: I/O Operation Conversion

**Chosen Approach:** Create async wrappers, deprecate sync versions

**Rationale:**
- `file_read_async` calls `asyncfile.readFile()` (truly async)
- Existing `file_read` remains for backward compatibility
- Users opt-in to async with explicit function names

**Conversion Examples:**
- `file_read()` → `file_read_async()` using `asyncfile.readFile()`
- `file_write()` → `file_write_async()` using `asyncfile.writeFile()`
- `http_get()` → `http_get_async()` using `asyncnet` or `httpclient.AsyncHttpClient`

**Alternative Considered:** Make all I/O async by default
- Would break existing synchronous code
- Forces users into async patterns
- Harder migration path

## Architecture Comparison

### Current (Pseudo-Async)
```
User Code: (async (file_read "x.txt"))
    ↓
Compiler: IkAsyncStart → IkPushValue "x.txt" → IkCallNative file_read → IkAsyncEnd
    ↓
VM Execution:
  IkAsyncStart    → Add exception handler marker
  file_read       → readFile() BLOCKS VM THREAD
  IkAsyncEnd      → future.complete(result) IMMEDIATELY
  Stack: [Future(Complete, value)]
    ↓
User Code: (await future)
    ↓
VM: IkAwait → Check state (always Complete) → Return value

Result: SYNCHRONOUS (no concurrency)
```

### Proposed (Real Async - Polling-Based)
```
User Code: (async (file_read_async "x.txt"))
    ↓
Compiler: IkAsyncStart → IkPushValue "x.txt" → IkCallNative file_read_async → IkAsyncEnd
    ↓
VM Execution:
  IkAsyncStart       → Add exception handler marker
  file_read_async    → asyncfile.readFile() returns Nim Future[string] (PENDING)
                     → Wrap in Gene FutureObj (state = FsPending)
  IkAsyncEnd         → Return Gene Future (still pending)
  Stack: [Future(Pending, nim_future)]
    ↓
User Code: (await future)
    ↓
VM: IkAwait → Check state (Pending)
            → POLL EVENT LOOP while pending:
              while future.state == FsPending:
                asyncdispatch.poll(timeout = 0)  # Process I/O
                # Check if Nim future completed
            → Future now Complete → Return value

Result: ASYNCHRONOUS (true concurrency via polling)
```

**Key Difference from CPS:**
- No state machines or continuations
- `await` blocks but polls event loop
- Other futures make progress during polling
- Much simpler implementation (~300 LOC vs ~2000 LOC)

### Performance Comparison
```
Workload: Read 3 files (100ms each)

Current:
  read file1 → BLOCK 100ms → complete
  read file2 → BLOCK 100ms → complete
  read file3 → BLOCK 100ms → complete
  Total: 300ms

Proposed:
  read file1 → start async → pending
  read file2 → start async → pending
  read file3 → start async → pending
  [Event loop schedules all I/O]
  All complete → ~100ms (limited by slowest I/O)
  Total: ~100ms (3× speedup)
```

## Risks / Trade-offs

### Risk 1: Await Blocks Execution
**Impact:** `await` blocks current execution (no true VM suspension)
**Trade-off:**
- Simpler implementation (no CPS needed)
- Event loop continues processing other futures
- Good enough for most async I/O use cases
- Can add CPS later if needed

### Risk 2: Performance Regression for Sync Code
**Impact:** Event loop polling adds overhead to non-async workloads
**Mitigation:**
- Use non-blocking poll (timeout = 0)
- Only poll after instruction batches (not per instruction)
- Benchmark non-async code to ensure <1% overhead

### Risk 3: Scope Lifetime
**Status:** ✅ FIXED
**Impact:** Scope lifetime bug could cause use-after-free crashes
**Resolution:** Fixed in Phase 0 - scopes now correctly ref-counted

### Risk 4: Nim Async Coupling
**Impact:** Tightly coupled to Nim's asyncdispatch implementation
**Mitigation:**
- Abstract event loop interface for future portability
- Document Nim version requirements
- Monitor Nim async API stability

### Risk 5: Breaking Semantic Changes
**Impact:** Code expecting synchronous completion will break
**Mitigation:**
- Clear migration guide with examples
- Deprecation warnings for sync-assuming patterns
- Dual API (sync and async versions of I/O functions)

## Migration Plan

### Phase 0: Scope Fix ✅ COMPLETED
1. ✅ Fixed `IkScopeEnd` ref counting bug (vm.nim:970)
2. ✅ Added scope lifetime stress tests
3. ✅ Validated - all tests pass

### Phase 1: Event Loop Integration (1-2 weeks)
1. Add `asyncdispatch.poll()` to VM main loop (every ~100 instructions)
2. Wrap Nim `Future[Value]` in `FutureObj.nim_future` field
3. Implement callback registration/invocation when futures complete
4. Convert one I/O function (e.g., `file_read_async`) as proof of concept

**Rollback:** Remove poll() call, revert I/O function

### Phase 2: Polling-Based Await (1 week)
1. Modify `IkAwait` to poll event loop while future is pending
2. Check Nim future completion and update Gene FutureObj state
3. Test with simple async I/O operations
4. Validate concurrent operations work

**Rollback:** Revert IkAwait to immediate return

### Phase 3: I/O Conversion (1-2 weeks)
1. Convert all I/O functions to async versions
2. Keep sync versions with deprecation warnings
3. Update documentation and examples

**Rollback:** Remove async versions, keep sync as primary

### Phase 4: Testing & Validation (1-2 weeks)
1. Concurrent I/O tests (parallel file reads)
2. Callback chaining tests
3. Exception handling in async context
4. Performance benchmarks
5. Stress tests (100+ pending futures)

### Deployment Strategy
- **Alpha Release**: Event loop + basic async I/O (Phases 0-1)
- **Beta Release**: Polling await + multiple I/O functions (Phases 2-3)
- **Stable Release**: Complete I/O conversion + testing (Phase 4)

### User Migration
**Before (Pseudo-Async):**
```gene
(var f (async (file_read "data.txt")))  # Blocks immediately
(var content (await f))                  # Returns immediately
```

**After (Real Async):**
```gene
(var f (async (file_read_async "data.txt")))  # Returns pending future
(var content (await f))                        # Polls event loop until I/O complete
```

**Breaking Change Example:**
```gene
# Code that WILL break:
(var f (async (some_io)))
(some_side_effect)  # Assumed to run AFTER I/O completes
(await f)

# Fix: Explicit await before side effect
(var f (async (some_io)))
(await f)
(some_side_effect)  # Now guaranteed to run after
```

## Open Questions

1. **How to handle timeout/cancellation?**
   - Consider adding `(await-with-timeout future ms)` or `(cancel future)` API
   - Defer to post-MVP

2. **Should async be opt-in per function or per expression?**
   - Current: `(async expr)` makes any expression async
   - Alternative: `(fn:async name [args] body)` for async functions only
   - Decision: Keep expression-level for flexibility

3. **How to debug suspended frames?**
   - Need tooling to inspect pending continuations
   - Consider debug mode with continuation stack traces
   - Defer to post-MVP

4. **Memory limits for pending futures?**
   - Should there be a max pending futures limit?
   - Consider rate limiting or backpressure mechanisms
   - Monitor in production, add limits if needed

5. **Integration with existing exception handling?**
   - Async exceptions may trigger at different times
   - Need to validate `try/catch` works correctly with continuations
   - Test thoroughly in Phase 5
