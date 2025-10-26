# Implementation Tasks: Real Async Support

## Phase 0: Scope Lifetime Fix (1-2 weeks)

### 0.1 Analysis
- [ ] 0.1.1 Document current scope ref counting in IkScopeEnd (vm.nim:419)
- [ ] 0.1.2 Identify all scope capture points (IkFunction at vm.nim:3171, async blocks)
- [ ] 0.1.3 Trace scope lifetime through function calls with async blocks

### 0.2 Fix Implementation
- [ ] 0.2.1 Modify IkScopeEnd to only free when ref_count == 0
- [ ] 0.2.2 Ensure async blocks increment scope ref_count on capture
- [ ] 0.2.3 Add scope decrement on future completion/cleanup

### 0.3 Testing
- [ ] 0.3.1 Add test: function returning async block referencing parameters
- [ ] 0.3.2 Add test: nested functions with async scope capture
- [ ] 0.3.3 Run memory sanitizer to detect use-after-free
- [ ] 0.3.4 Validate all existing scope tests still pass

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

## Phase 2: CPS Compiler Transformation (3-6 weeks)

### 2.1 Analysis & Design
- [ ] 2.1.1 Identify async function boundaries in AST
- [ ] 2.1.2 Design state machine structure for continuations
- [ ] 2.1.3 Define continuation data structure (frame state)
- [ ] 2.1.4 Plan instruction sequence for state transitions

### 2.2 Async Function Detection
- [ ] 2.2.1 Mark functions containing `async` blocks as async (compiler.nim)
- [ ] 2.2.2 Detect `await` expressions within functions
- [ ] 2.2.3 Validate no `await` outside async context
- [ ] 2.2.4 Error on unsupported patterns (await in loops initially)

### 2.3 Continuation Point Generation
- [ ] 2.3.1 Split function at each `await` into separate code blocks
- [ ] 2.3.2 Generate state labels for each continuation point
- [ ] 2.3.3 Insert state jump table at function entry
- [ ] 2.3.4 Compile state restoration logic

### 2.4 State Machine Compilation
- [ ] 2.4.1 Generate State 0: Initial execution until first await
- [ ] 2.4.2 Generate State N: Resume from await N, execute until next await
- [ ] 2.4.3 Generate final state: Complete and return
- [ ] 2.4.4 Emit continuation closure creation instructions

### 2.5 Variable Capture
- [ ] 2.5.1 Identify local variables live across await points
- [ ] 2.5.2 Generate capture instructions for continuation closure
- [ ] 2.5.3 Generate restore instructions on resumption
- [ ] 2.5.4 Test variable values preserved across suspension

### 2.6 Testing
- [ ] 2.6.1 Test simple async function with single await
- [ ] 2.6.2 Test multiple awaits in sequence
- [ ] 2.6.3 Test local variables across await boundaries
- [ ] 2.6.4 Test nested async function calls
- [ ] 2.6.5 Validate bytecode generation correctness

## Phase 3: VM Suspension (2-4 weeks)

### 3.1 Frame State Serialization
- [ ] 3.1.1 Define Continuation type (pc, stack_depth, scope, locals)
- [ ] 3.1.2 Implement frame state capture on suspension
- [ ] 3.1.3 Store continuation in future's callback list
- [ ] 3.1.4 Test serialization preserves state correctly

### 3.2 IkAwait Suspension
- [ ] 3.2.1 Check future state in IkAwait handler (vm.nim:4120)
- [ ] 3.2.2 If FsPending: Capture frame state and create continuation
- [ ] 3.2.3 Register continuation with future callbacks
- [ ] 3.2.4 Yield control to event loop (return from VM step)

### 3.3 Continuation Restoration
- [ ] 3.3.1 Implement continuation invocation callback
- [ ] 3.3.2 Restore PC, stack pointer, and scope
- [ ] 3.3.3 Push result value onto stack
- [ ] 3.3.4 Resume VM execution from continuation point

### 3.4 Exception Handling
- [ ] 3.4.1 Preserve exception handlers across suspension
- [ ] 3.4.2 Implement async exception propagation to continuation
- [ ] 3.4.3 Test try/catch with async blocks
- [ ] 3.4.4 Test exception in callback execution

### 3.5 Testing
- [ ] 3.5.1 Test suspension on pending future
- [ ] 3.5.2 Test restoration with correct state
- [ ] 3.5.3 Test multiple concurrent suspensions
- [ ] 3.5.4 Test suspension/resumption cycles (1000 iterations)
- [ ] 3.5.5 Stress test: 100+ pending futures simultaneously

## Phase 4: I/O Conversion (1-2 weeks)

### 4.1 File I/O
- [ ] 4.1.1 Convert `file_read_async` to use asyncfile.readFile()
- [ ] 4.1.2 Convert `file_write_async` to use asyncfile.writeFile()
- [ ] 4.1.3 Add `file_exists_async`, `file_delete_async` as needed
- [ ] 4.1.4 Keep synchronous versions with deprecation notices

### 4.2 Network I/O
- [ ] 4.2.1 Create `http_get_async` using AsyncHttpClient
- [ ] 4.2.2 Create `http_post_async` for POST requests
- [ ] 4.2.3 Add connection timeout and retry configuration
- [ ] 4.2.4 Test with real network requests

### 4.3 Timer/Delay
- [ ] 4.3.1 Add `sleep_async(ms)` using asyncdispatch.sleepAsync()
- [ ] 4.3.2 Test precise timing with multiple sleeps
- [ ] 4.3.3 Validate sleep doesn't block other async operations

### 4.4 Documentation
- [ ] 4.4.1 Document all async I/O functions
- [ ] 4.4.2 Add examples for concurrent file/network operations
- [ ] 4.4.3 Write migration guide from sync to async I/O
- [ ] 4.4.4 Update CLAUDE.md with real async semantics

## Phase 5: Testing & Validation (2-3 weeks)

### 5.1 Concurrency Tests
- [ ] 5.1.1 Test 3 parallel file reads complete concurrently
- [ ] 5.1.2 Test interleaved async and sync code execution
- [ ] 5.1.3 Test nested async function calls
- [ ] 5.1.4 Test async recursion (careful with stack depth)

### 5.2 Callback Chaining
- [ ] 5.2.1 Test `.on_success()` chaining with multiple callbacks
- [ ] 5.2.2 Test `.on_failure()` for error handling
- [ ] 5.2.3 Test mixed success/failure callback registration
- [ ] 5.2.4 Test callback execution order

### 5.3 Exception Handling
- [ ] 5.3.1 Test try/catch around async blocks
- [ ] 5.3.2 Test exception propagation through await
- [ ] 5.3.3 Test unhandled async exception behavior
- [ ] 5.3.4 Test finally blocks with async code

### 5.4 Edge Cases
- [ ] 5.4.1 Test await on already-completed future
- [ ] 5.4.2 Test multiple awaits on same future
- [ ] 5.4.3 Test future completion before await
- [ ] 5.4.4 Test scope cleanup with abandoned futures
- [ ] 5.4.5 Test deeply nested async (10+ levels)

### 5.5 Performance Benchmarks
- [ ] 5.5.1 Benchmark 3 parallel file reads (expect ~3x speedup)
- [ ] 5.5.2 Benchmark 10 concurrent HTTP requests
- [ ] 5.5.3 Benchmark non-async code (expect <5% overhead)
- [ ] 5.5.4 Profile event loop overhead per 1000 instructions
- [ ] 5.5.5 Measure memory usage with 1000 pending futures

### 5.6 Stress Tests
- [ ] 5.6.1 Run 10,000 async operations (check for leaks)
- [ ] 5.6.2 Test rapid suspend/resume cycles
- [ ] 5.6.3 Test 100+ simultaneous pending futures
- [ ] 5.6.4 Run full test suite with memory sanitizer
- [ ] 5.6.5 Long-running test (1 hour continuous async operations)

### 5.7 Test Suite Updates
- [ ] 5.7.1 Update testsuite/async/ with concurrency validation
- [ ] 5.7.2 Add expected timing comments (e.g., # Completes in ~100ms)
- [ ] 5.7.3 Remove synchronous assumptions from existing tests
- [ ] 5.7.4 Add new concurrent I/O tests
- [ ] 5.7.5 Validate all tests pass under real async

## Phase 6: Documentation & Release (1 week)

### 6.1 Documentation
- [ ] 6.1.1 Update language guide with real async semantics
- [ ] 6.1.2 Add async best practices and patterns
- [ ] 6.1.3 Document breaking changes and migration path
- [ ] 6.1.4 Add troubleshooting section for common async issues

### 6.2 Examples
- [ ] 6.2.1 Create concurrent file processing example
- [ ] 6.2.2 Create web scraper with parallel requests
- [ ] 6.2.3 Create async pipeline example
- [ ] 6.2.4 Add performance comparison examples

### 6.3 Release Preparation
- [ ] 6.3.1 Update CHANGELOG with async features
- [ ] 6.3.2 Tag alpha release (Phase 1 complete)
- [ ] 6.3.3 Tag beta release (Phases 1-3 complete)
- [ ] 6.3.4 Tag stable release (all phases complete)

### 6.4 Monitoring
- [ ] 6.4.1 Set up performance monitoring for async operations
- [ ] 6.4.2 Add logging for event loop statistics
- [ ] 6.4.3 Track pending future counts in production
- [ ] 6.4.4 Monitor memory usage patterns

---

**Total Estimated Time:** 10-19 weeks
**Critical Path:** Phase 0 → Phase 1 → Phase 2 → Phase 3 (must be sequential)
**Parallel Work:** Phase 4 can overlap with Phase 3, Phase 5 runs after all
