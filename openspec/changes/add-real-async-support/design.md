# Design: Real Async Support

## Context

Gene's VM is a stack-based bytecode interpreter written in Nim. The current async implementation provides syntax but no actual concurrency - all operations complete synchronously. Nim provides robust async capabilities through `asyncdispatch`, `asyncfile`, and `asyncnet`, but Gene doesn't integrate with these primitives.

**Current State:**
- VM runs in single thread with no event loop
- `IkAsyncEnd` (vm.nim:4088) completes futures immediately
- I/O uses blocking `readFile()` instead of `asyncfile.readFile()`
- Scope freed in `IkScopeEnd` when `ref_count == 1` (vm.nim:419)

**Stakeholders:**
- Gene language users expecting real async semantics
- VM maintainers concerned about complexity
- Performance-sensitive applications needing concurrent I/O

**Constraints:**
- Must maintain backward compatibility with async syntax
- Cannot introduce multi-threading (VM is single-threaded)
- Must not degrade performance for non-async code
- Scope lifetime bug must be fixed before full async works

## Goals / Non-Goals

### Goals
1. **True Concurrency**: Multiple I/O operations execute concurrently
2. **Event Loop**: Integrate Nim's `asyncdispatch` for scheduling
3. **Real Suspension**: `await` on pending futures yields to event loop
4. **Non-Blocking I/O**: Replace synchronous I/O with async primitives
5. **Scope Safety**: Fix scope lifetime to support pending futures
6. **Callback Support**: Implement `.on_success()` / `.on_failure()` chaining

### Non-Goals
1. **Multi-threading**: Async is concurrent (single-thread), not parallel
2. **Async Generators**: Defer to future work
3. **Custom Schedulers**: Use Nim's asyncdispatch exclusively
4. **Distributed Futures**: No RPC or remote async
5. **WASM Integration**: Defer to separate effort

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

### Decision 2: CPS Transformation Strategy

**Chosen Approach:** Compiler-based continuation generation with state machines

**Rationale:**
- Nim's `{.async.}` macro uses CPS transformation successfully
- Compiler has full visibility into control flow
- Can split function at every `await` point
- State machines proven effective for async in other languages (JS, C#, Rust)

**Alternative Considered:** Interpreter-level coroutines
- Would require rewriting VM execution model
- Higher runtime overhead
- Harder to debug and maintain

**Implementation Pattern:**
```gene
# Source:
(fn fetch_data [url]
  (var response (await (http/get url)))
  (var parsed (await (json/parse response)))
  parsed)

# Compiles to state machine:
State 0: Call http/get, register continuation -> State 1
State 1: Resume with response, call json/parse, register continuation -> State 2
State 2: Resume with parsed, return value
```

### Decision 3: Frame Suspension Mechanism

**Chosen Approach:** Serialize minimal frame state, store continuation closure

**Rationale:**
- Full frame serialization is expensive (256 Value slots)
- Only need: PC, stack pointer, scope reference, local variables in use
- Continuation closure captures context, stored in future's callback list

**Alternative Considered:** Full frame cloning
- Would copy entire 256-slot stack
- Wastes memory for unused slots
- Slower suspension/resumption

**Implementation:**
```nim
type Continuation = ref object
  frame_id: int
  pc: int
  stack_depth: int
  scope: Scope
  captured_locals: seq[Value]
```

### Decision 4: Scope Lifetime Management

**Chosen Approach:** Scope reference counting with future ownership

**Rationale:**
- Futures increment scope ref_count when capturing
- Scope only freed when ref_count == 0
- Maintains existing ref counting infrastructure
- No need for full GC integration

**Critical Fix Location:** `vm.nim:419` (IkScopeEnd)
```nim
# CURRENT (BUGGY):
if old_scope.ref_count > 1:
  old_scope.ref_count.dec()
else:
  old_scope.free()  # FREED TOO EARLY if future pending!

# FIXED:
old_scope.ref_count.dec()
if old_scope.ref_count == 0:
  old_scope.free()  # Only free when no references
```

**Alternative Considered:** Copy-on-capture
- Would duplicate scope for every async block
- Higher memory usage
- Doesn't align with existing ref counting design

### Decision 5: Event Loop Integration

**Chosen Approach:** Run `asyncdispatch` poll in VM main loop

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

### Decision 6: I/O Operation Conversion

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

### Proposed (Real Async)
```
User Code: (async (file_read_async "x.txt"))
    ↓
Compiler: IkAsyncStart → CPS_State0 → IkAwait → CPS_State1 → IkAsyncEnd
    ↓
VM Execution:
  IkAsyncStart       → Create continuation context
  file_read_async    → asyncfile.readFile() returns Future[string] (PENDING)
  IkAwait            → Future pending? YES
                     → Save frame state (PC, stack, scope)
                     → Register continuation callback
                     → YIELD to event loop
    ↓
Event Loop:
  poll() → Check I/O readiness
  File ready → Invoke continuation
    ↓
VM Resumption:
  CPS_State1      → Restore frame, push result
  IkAsyncEnd      → Wrap in Gene Future
  Stack: [Future(Complete, value)]
    ↓
User Code: (await future)
    ↓
VM: IkAwait → Check state (Complete) → Return value

Result: ASYNCHRONOUS (true concurrency)
```

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

### Risk 1: Complexity Increase
**Impact:** CPS transformation and frame suspension add ~2000+ LOC
**Mitigation:**
- Implement in phases (event loop first, then CPS)
- Comprehensive unit tests for each component
- Document design patterns for maintainers

### Risk 2: Performance Regression for Sync Code
**Impact:** Event loop polling adds overhead to non-async workloads
**Mitigation:**
- Use non-blocking poll (timeout = 0)
- Only poll after instruction batches (not per instruction)
- Benchmark non-async code to ensure <5% overhead

### Risk 3: Scope Lifetime Bug Must Be Fixed First
**Impact:** Real async will expose use-after-free crashes
**Mitigation:**
- Fix scope ref counting in Phase 0 (before async changes)
- Add memory sanitizer tests
- Validate with stress tests

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

### Phase 0: Scope Fix (1-2 weeks)
1. Fix `IkScopeEnd` ref counting bug (vm.nim:419)
2. Add scope lifetime stress tests
3. Validate with memory sanitizer

### Phase 1: Event Loop Integration (2-4 weeks)
1. Add `asyncdispatch.poll()` to VM main loop
2. Wrap Nim `Future[Value]` in `FutureObj`
3. Implement callback registration/invocation
4. Convert one I/O function (e.g., `file_read_async`) as proof of concept

**Rollback:** Remove poll() call, revert I/O function

### Phase 2: CPS Compiler (3-6 weeks)
1. Identify async function boundaries
2. Split at `await` points into state machine
3. Generate continuation closures
4. Test with simple async functions

**Rollback:** Keep old compiler path, disable CPS with feature flag

### Phase 3: VM Suspension (2-4 weeks)
1. Implement frame state serialization
2. Modify `IkAwait` to suspend on pending futures
3. Implement continuation restoration
4. Test suspension/resumption cycles

**Rollback:** Disable suspension, fall back to immediate completion

### Phase 4: I/O Conversion (1-2 weeks)
1. Convert all I/O functions to async versions
2. Keep sync versions with deprecation warnings
3. Update documentation and examples

**Rollback:** Remove async versions, keep sync as primary

### Phase 5: Testing & Validation (2-3 weeks)
1. Concurrent I/O tests (parallel file reads)
2. Callback chaining tests
3. Exception handling in async context
4. Performance benchmarks
5. Stress tests (1000+ pending futures)

### Deployment Strategy
- **Alpha Release**: Event loop + basic async I/O (Phases 0-1)
- **Beta Release**: Full CPS + suspension (Phases 2-3)
- **Stable Release**: Complete I/O conversion + testing (Phases 4-5)

### User Migration
**Before (Pseudo-Async):**
```gene
(var f (async (file_read "data.txt")))  # Blocks immediately
(var content (await f))                  # Returns immediately
```

**After (Real Async):**
```gene
(var f (async (file_read_async "data.txt")))  # Returns pending future
(var content (await f))                        # Suspends until I/O complete
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
