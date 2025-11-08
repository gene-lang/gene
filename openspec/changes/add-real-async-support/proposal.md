# Proposal: Add Real Async Support

## Why

Gene currently implements **pseudo-async** where `async`/`await` syntax exists but all operations execute synchronously. There is no event loop, no non-blocking I/O, and no actual concurrency. Futures are completed immediately before execution continues, making async purely syntactic sugar with zero performance benefit.

**Current behavior:**
- Three 100ms file reads take 300ms (sequential blocking)
- I/O operations block the VM thread using synchronous `readFile()`
- `IkAwait` never actually waits (futures always complete immediately)
- Tests pass but provide no concurrency validation

**Real-world impact:**
- Cannot perform concurrent file I/O
- HTTP requests execute sequentially (not in parallel)
- Database queries block other async operations
- No performance benefit from async/await syntax

Real async support would enable:
- Concurrent I/O operations (3× speedup for 3 parallel reads)
- Non-blocking network requests
- Event-driven programming patterns
- Proper async/await semantics

## What Changes

### Core Architecture
- **Event Loop Polling**: Integrate Nim's `asyncdispatch.poll()` in VM main loop
- **Async I/O**: Replace blocking I/O with Nim's async primitives (`asyncfile`, `asyncnet`)
- **Future Tracking**: Store active futures in VM, poll until completion
- **Scope Fix**: ✅ COMPLETED - Fixed scope lifetime management to support pending futures

**Design Principle:** Simple polling-based approach. **No CPS transformation**, no complex state machines, no VM suspension. `await` blocks but the event loop continues processing other futures.

### Specific Changes
- Add `pending_futures: seq[Future[Value]]` to VirtualMachine
- Add `event_loop_counter` and periodic `poll()` in main VM loop
- Modify `FutureObj` to wrap Nim's `Future[Value]`
- Update `IkAwait` to poll event loop while waiting for completion
- Convert I/O functions to use async primitives
- ✅ Fix scope ref counting in `IkScopeEnd` - COMPLETED

### **BREAKING** Changes
- Async I/O operations now return pending futures (not completed immediately)
- `await` may block polling event loop (but other futures continue progressing)
- I/O function names change (e.g., `file_read` → `file_read_async`)

### Non-Goals (Out of Scope)
- **CPS transformation** - Too complex, not needed for concurrent I/O
- **VM suspension/resumption** - `await` blocks the current execution but event loop continues
- **Async generators/iterators** - Future work
- **Multi-threading** - Use threads feature instead
- **Async function detection** - No special compiler analysis needed

## Impact

### Affected Specs
- **async** (NEW): Concurrent async/await with event loop and real I/O

### Affected Code
- `src/gene/types.nim` (VirtualMachine: pending_futures, event_loop_counter)
- `src/gene/vm.nim` (main loop polling, IkAwait handler)
- `src/gene/vm/async.nim` (Future wrapping Nim futures)
- `src/gene/vm/core.nim` (async I/O functions)
- `testsuite/async/` (update tests to validate concurrency)

### Migration Path
- Existing async code continues to work (same syntax)
- I/O functions renamed with `_async` suffix
- Performance improves automatically (I/O becomes concurrent)
- No code changes needed for correct programs

### Risk Assessment
- **Low Complexity**: Simple polling, no CPS (~200-300 lines of changes)
- **Scope Bug**: ✅ FIXED - Scope lifetime now correctly managed
- **Performance**: <1% overhead for non-async code (counter increment)
- **Testing Burden**: Need concurrency tests (multiple concurrent operations)

### Performance Characteristics
- **Concurrent I/O speedup**: 3× for 3 parallel file reads (~100ms vs 300ms)
- **Polling overhead**: ~0.1% (one counter increment per instruction)
- **Event loop**: Poll every 100 instructions (~10-50μs)
- **Await blocking**: Await still blocks execution, but event loop keeps other futures progressing

### Timeline Estimate
- Phase 0 (Scope Fix): ✅ COMPLETED
- Phase 1 (Event Loop Integration): 1-2 weeks
- Phase 2 (Async I/O Functions): 1-2 weeks
- Phase 3 (Await Polling): 1 week
- Phase 4 (Testing & Validation): 1-2 weeks

**Total: 4-7 weeks** for complete implementation (Phase 0 already done)

### Benefits
- **Concurrent I/O**: Multiple file/network operations overlap
- **Simple Implementation**: No CPS complexity
- **Real Speedup**: 3× improvement for 3 concurrent operations
- **Easy Maintenance**: Straightforward polling logic
- **Good Enough**: Satisfies 90% of async use cases
