# Implementation Tasks: Real Async Support (Polling-Based)

**Note:** This implementation uses a simple polling-based approach. No CPS transformation or VM suspension.

## Phase 0: Scope Lifetime Fix ✅ COMPLETED

### 0.1 Analysis ✅
- [x] 0.1.1 Document current scope ref counting in IkScopeEnd (vm.nim:970)
- [x] 0.1.2 Identify all scope capture points (IkFunction, async blocks)
- [x] 0.1.3 Trace scope lifetime through function calls with async blocks

### 0.2 Fix Implementation ✅
- [x] 0.2.1 Modify IkScopeEnd to call scope.free() (handles ref_count internally)
- [x] 0.2.2 Async blocks already increment scope ref_count on capture
- [x] 0.2.3 Scope decrement handled by free() method

### 0.3 Testing ✅
- [x] 0.3.1 Add test: function returning async block referencing parameters
- [x] 0.3.2 Add test: nested functions with async scope capture
- [x] 0.3.3 All scope lifetime tests pass
- [x] 0.3.4 Validate all existing scope tests still pass

## Phase 1: Event Loop Integration (2-4 weeks)

### 1.1 FutureObj Wrapper
- [ ] 1.1.1 Add `nim_future: Future[Value]` field to FutureObj (types.nim)
- [ ] 1.1.2 Implement wrapper construction: `new_future_from_nim()`
- [ ] 1.1.3 Sync state between Nim future and Gene FutureObj
- [ ] 1.1.4 Handle Future[T] → Value conversion

### 1.2 Event Loop Setup
- [ ] 1.2.1 Add asyncdispatch poll to VM main loop (vm.nim)
- [ ] 1.2.2 Configure non-blocking poll (timeout = 0)
- [ ] 1.2.3 Add instruction batch counter (poll every 100 instructions)
- [ ] 1.2.4 Test event loop runs without blocking VM

### 1.3 Callback Implementation
- [ ] 1.3.1 Implement `future.on_success(callback)` execution (vm/async.nim:24)
- [ ] 1.3.2 Implement `future.on_failure(callback)` execution (vm/async.nim:54)
- [ ] 1.3.3 Register callbacks with Nim future using `addCallback()`
- [ ] 1.3.4 Test callback invocation on future completion

### 1.4 Proof of Concept
- [ ] 1.4.1 Create `file_read_async_real()` using `asyncfile.readFile()`
- [ ] 1.4.2 Return wrapped Nim future from I/O function
- [ ] 1.4.3 Test pending → complete state transition
- [ ] 1.4.4 Validate callback fires when I/O completes

### 1.5 Testing
- [ ] 1.5.1 Test single async I/O operation
- [ ] 1.5.2 Test event loop continues during pending I/O
- [ ] 1.5.3 Benchmark non-async code for performance regression
- [ ] 1.5.4 Validate exception handling with async failures

## Phase 2: Polling-Based Await (1 week)

### 2.1 IkAwait Polling Implementation
- [ ] 2.1.1 Modify IkAwait to check if future is pending (vm.nim:~4280)
- [ ] 2.1.2 Add polling loop: while future.state == FsPending, call poll()
- [ ] 2.1.3 Check Nim future completion and sync to Gene FutureObj
- [ ] 2.1.4 Return value when future completes

### 2.2 Nim Future Integration
- [ ] 2.2.1 Add helper to check if Nim future is finished
- [ ] 2.2.2 Add helper to extract value from completed Nim future
- [ ] 2.2.3 Handle exceptions from failed Nim futures
- [ ] 2.2.4 Update Gene FutureObj state when Nim future completes

### 2.3 Testing
- [ ] 2.3.1 Test await on pending future (polls until complete)
- [ ] 2.3.2 Test await on already-completed future (returns immediately)
- [ ] 2.3.3 Test multiple concurrent awaits
- [ ] 2.3.4 Test exception propagation through await
- [ ] 2.3.5 Validate event loop continues during await

## Phase 3: I/O Conversion (1-2 weeks)

### 3.1 File I/O
- [ ] 3.1.1 Convert `file_read_async` to use asyncfile.readFile()
- [ ] 3.1.2 Convert `file_write_async` to use asyncfile.writeFile()
- [ ] 3.1.3 Add `file_exists_async`, `file_delete_async` as needed
- [ ] 3.1.4 Keep synchronous versions with deprecation notices

### 3.2 Network I/O
- [ ] 3.2.1 Create `http_get_async` using AsyncHttpClient
- [ ] 3.2.2 Create `http_post_async` for POST requests
- [ ] 3.2.3 Add connection timeout and retry configuration
- [ ] 3.2.4 Test with real network requests

### 3.3 Timer/Delay
- [ ] 3.3.1 Add `sleep_async(ms)` using asyncdispatch.sleepAsync()
- [ ] 3.3.2 Test precise timing with multiple sleeps
- [ ] 3.3.3 Validate sleep doesn't block other async operations

### 3.4 Documentation
- [ ] 3.4.1 Document all async I/O functions
- [ ] 3.4.2 Add examples for concurrent file/network operations
- [ ] 3.4.3 Write migration guide from sync to async I/O
- [ ] 3.4.4 Update CLAUDE.md with real async semantics

## Phase 4: Testing & Validation (1-2 weeks)

### 4.1 Concurrency Tests
- [ ] 4.1.1 Test 3 parallel file reads complete concurrently
- [ ] 4.1.2 Test interleaved async and sync code execution
- [ ] 4.1.3 Test nested async function calls
- [ ] 4.1.4 Validate concurrent operations actually overlap

### 4.2 Callback Chaining
- [ ] 4.2.1 Test `.on_success()` chaining with multiple callbacks
- [ ] 4.2.2 Test `.on_failure()` for error handling
- [ ] 4.2.3 Test mixed success/failure callback registration
- [ ] 4.2.4 Test callback execution order

### 4.3 Exception Handling
- [ ] 4.3.1 Test try/catch around async blocks
- [ ] 4.3.2 Test exception propagation through await
- [ ] 4.3.3 Test unhandled async exception behavior
- [ ] 4.3.4 Test finally blocks with async code

### 4.4 Edge Cases
- [ ] 4.4.1 Test await on already-completed future
- [ ] 4.4.2 Test multiple awaits on same future
- [ ] 4.4.3 Test future completion before await
- [ ] 4.4.4 Test scope cleanup with abandoned futures
- [ ] 4.4.5 Test deeply nested async (10+ levels)

### 4.5 Performance Benchmarks
- [ ] 4.5.1 Benchmark 3 parallel file reads (expect ~3x speedup)
- [ ] 4.5.2 Benchmark 10 concurrent HTTP requests
- [ ] 4.5.3 Benchmark non-async code (expect <1% overhead)
- [ ] 4.5.4 Profile event loop overhead per 1000 instructions
- [ ] 4.5.5 Measure memory usage with 100 pending futures

### 4.6 Stress Tests
- [ ] 4.6.1 Run 1,000 async operations (check for leaks)
- [ ] 4.6.2 Test 100+ simultaneous pending futures
- [ ] 4.6.3 Run full test suite with memory sanitizer
- [ ] 4.6.4 Long-running test (30 min continuous async operations)

### 4.7 Test Suite Updates
- [ ] 4.7.1 Update testsuite/async/ with concurrency validation
- [ ] 4.7.2 Add expected timing comments (e.g., # Completes in ~100ms)
- [ ] 4.7.3 Remove synchronous assumptions from existing tests
- [ ] 4.7.4 Add new concurrent I/O tests
- [ ] 4.7.5 Validate all tests pass under real async

---

**Total Estimated Time:** 4-7 weeks (Phase 0 already complete)
**Critical Path:** Phase 0 ✅ → Phase 1 → Phase 2 → Phase 3 → Phase 4
**Simplified Approach:** No CPS transformation, no VM suspension - just polling-based await
