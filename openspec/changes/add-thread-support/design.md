# Design: Thread Support

## Context

Gene's bytecode VM currently has no thread support. The VM is a stack-based interpreter with global state (VM variable) and shared memory pools (FRAMES, REF_POOL). This design makes multi-threading unsafe without significant changes.

**Current Architecture:**
- Single global VM instance (not thread-safe)
- Global frame pool shared across all execution
- App already thread-local (`{.threadvar.}`) but VM is not
- Symbol table is global read-only (safe to share)

**Reference Implementation:**
- gene-new (tree-walking interpreter) has working thread support
- Uses isolated VM per thread with channel-based message passing
- Thread pool of 64 threads with secret-based validation
- Message types: Run, Send, Reply (with/without reply variants)

**Stakeholders:**
- Gene language users needing CPU parallelism
- Performance-sensitive applications (image processing, data analysis)
- VM maintainers concerned about thread safety

**Constraints:**
- Must not break single-threaded code
- Cannot introduce shared mutable state (safety requirement)
- Must work with Nim's GC (stop-the-world, all threads pause)
- Thread pool size limited to 64 (simple allocation strategy)

## Goals / Non-Goals

### Goals
1. **True Parallelism**: Threads run on separate CPU cores for genuine parallel execution
2. **Isolated Execution**: Each thread has separate VM instance, no shared mutable state
3. **Main Thread Coordination**: Thread 0 serves as main coordinator, all threads can communicate with it
4. **Message Passing**: Communication via Nim channels only
5. **Thread Pool**: Reusable pool of 64 threads for efficiency
6. **Bytecode Advantage**: Compile once on main thread, execute in any thread
7. **Safety First**: Secret-based thread validation prevents use-after-free
8. **Integration**: Works alongside async for mixed workloads

### Non-Goals
1. **Shared Memory**: No thread-local storage API or shared mutable state
2. **Custom Scheduling**: Use Nim's default OS thread scheduler (let OS distribute across cores)
3. **Green Threads**: Use OS threads (1:1 mapping for true parallelism)
4. **Work Stealing**: Simple thread pool without advanced scheduling
5. **Thread Locals**: Threads are fully isolated (no TLS needed)
6. **CPU Affinity**: No manual core pinning (let OS optimize placement)

## Multi-Core Execution Model

### OS Threads for True Parallelism

**Design Principle:** Use Nim's OS threads (1:1 mapping to kernel threads) so the OS scheduler distributes work across CPU cores.

```
4-Core CPU System

Core 0          Core 1          Core 2          Core 3
┌──────┐        ┌──────┐        ┌──────┐        ┌──────┐
│Thread│        │Thread│        │Thread│        │Thread│
│  0   │        │  1   │        │  2   │        │  3   │
│(Main)│        │      │        │      │        │      │
└──────┘        └──────┘        └──────┘        └──────┘
   │               │               │               │
   └───────────────┴───────────────┴───────────────┘
            All cores busy = 4× parallelism
```

**How It Works:**
1. **Nim's `createThread()`** creates OS thread (POSIX pthread or Win32 thread)
2. **OS Scheduler** assigns thread to available CPU core
3. **True Parallelism**: Threads execute simultaneously on different cores
4. **GC Coordination**: Stop-the-world GC pauses all threads temporarily

**Why This Matters:**
- ✅ **4 cores = 4× speedup** for CPU-bound tasks (near-linear scaling)
- ✅ **Different from async**: Async = concurrent (1 core), threads = parallel (N cores)
- ✅ **No GIL**: Unlike Python, Nim threads have no global interpreter lock
- ✅ **OS Optimized**: Kernel handles core affinity, SMT, cache locality

**Verification:**
```gene
# Spawn 4 CPU-intensive tasks
(var start (time/now))
(var futures [])
(for i in (range 4)
  (.push futures (spawn_return (compute_intensive i))))

(for f in futures (await f))
(var elapsed (- (time/now) start))

# On 4-core CPU: ~1× time (all cores busy)
# On 1-core CPU: ~4× time (sequential)
```

## Main Thread Architecture

### Thread 0: The Main Thread

**Design Principle:** Thread 0 is always the main/coordinator thread where the program starts and where all worker threads can report back.

```
Thread 0 (Main)
┌─────────────────────┐
│ Initial VM          │
│ Spawns workers      │
│ Receives results    │◄──────┐
│ Polls channel       │       │
└──────────┬──────────┘       │
           │                  │
           │ Spawn            │ Reply/Send
           ├─────────────┐    │
           │             │    │
           ▼             ▼    │
    Thread 1         Thread 2 │
    ┌──────────┐    ┌──────────┐
    │ Worker 1 │    │ Worker 2 │
    │ Compute  │    │ Compute  │
    └──────────┘    └──────────┘
```

### Key Characteristics

1. **Always ID 0**: Main thread is always thread_id = 0
2. **Never Spawned**: Main thread exists from program start, not spawned
3. **Never Cleaned Up**: Main thread metadata never marked as "free"
4. **Always Accessible**: Workers can always send messages to THREADS[0]
5. **Polls Channel**: Main thread must poll its channel to receive worker messages

### Access Pattern

**From Worker to Main:**
```gene
# In worker thread:
(.send $main_thread "Result ready")

# Or use parent if spawned from main:
(.send (.parent $thread) result_data)
```

**From Main to Worker:**
```gene
# In main thread:
(var worker (spawn (keep_alive)))
(.send worker "Process this")
```

### Implementation Details

**Thread Metadata Initialization:**
```nim
# At program start (main thread):
proc init_main_thread*() =
  THREADS[0].id = 0
  THREADS[0].secret = rand()
  THREADS[0].in_use = true
  THREADS[0].state = TsBusy
  THREADS[0].parent_id = 0  # Points to itself
  THREADS[0].channel.open(CHANNEL_LIMIT)

  # Make main thread reference available
  VM.global_ns.ns["$main_thread"] = Value(
    kind: VkThread,
    thread_id: 0,
    thread_secret: THREADS[0].secret,
  )
```

**Worker Thread Initialization:**
```nim
proc init_vm_for_thread*(thread_id: int) =
  # ... VM initialization ...

  # All workers get reference to main thread
  VM.global_ns.ns["$main_thread"] = Value(
    kind: VkThread,
    thread_id: 0,
    thread_secret: THREADS[0].secret,
  )
```

**Main Thread Channel Polling:**
```nim
# In main VM execution loop (vm.nim):
of IkCheckChannel:
  # Always poll own channel (including main thread)
  let channel = THREADS[VM.thread_id].channel.addr
  var tried = channel[].try_recv()
  while tried.data_available:
    handle_message(tried.msg)
    tried = channel[].try_recv()
```

### Common Patterns

**Pattern 1: Worker Reports to Main**
```gene
# Main spawns workers:
(for i in (range 10)
  (spawn
    (var result (compute i))
    (.send $main_thread result)))

# Main collects results:
(.on_message $thread (fn [msg]
  (println "Worker result:" (.payload msg))))

# Main keeps running to receive messages:
(keep_alive)  # Or continue main logic
```

**Pattern 2: Main Distributes Work**
```gene
# Main creates worker pool:
(var workers [])
(for i in (range 4)
  (.push workers (spawn (keep_alive))))

# Main distributes tasks:
(var tasks (load_tasks))
(for task in tasks
  (var worker (.get workers (% task.id (.len workers))))
  (.send worker task))
```

**Pattern 3: Bidirectional Communication**
```gene
# Worker requests data from main:
(spawn
  (.on_message $thread (fn [msg]
    (var data (.payload msg))
    (var result (process data))
    (.reply msg result)))
  (keep_alive))

# Main sends work and waits for reply:
(for worker in workers
  (var reply (await (.send worker task ^reply true)))
  (println "Got:" reply))
```

## Thread State Cleanup

### The Problem

When reusing threads from the pool, lingering state from previous execution can cause bugs:

**Potential Contamination:**
- Stack contains leftover values
- Exception handlers not cleared
- Frames not returned to pool
- Callbacks registered but never invoked
- Futures in VM.futures table never completed
- Generator state persists
- Global variables modified

**Critical Requirement:** Each thread execution must start with clean VM state.

### Design Choices

**Option 1: Create New OS Thread Per Spawn (gene-new approach)**
```nim
# Thread handler runs ONCE then exits
proc thread_handler(thread_id: int) =
  init_vm_for_thread(thread_id)
  var msg = channel.recv()
  execute(msg)
  cleanup_thread(thread_id)
  # Thread terminates, OS reclaims all state
```

✅ Pros: Guaranteed clean state (OS does cleanup)
❌ Cons: 1-5ms overhead per spawn (OS thread creation)

**Option 2: Full VM Reinitialization Per Task**
```nim
proc thread_handler(thread_id: int) =
  while true:
    var msg = channel.recv()
    init_vm_for_thread(thread_id)  # Full reinit
    execute(msg)
```

✅ Pros: Clean state, reuses OS thread
❌ Cons: Overhead of reinitializing App, classes, namespaces every time

**Option 3: Targeted State Reset (Chosen)**
```nim
proc thread_handler(thread_id: int) =
  init_vm_for_thread(thread_id)  # Once

  while true:
    var msg = channel.recv()
    reset_vm_state()  # Fast targeted reset
    execute(msg)
```

✅ Pros: Fast cleanup, reuses OS thread and App/classes
✅ Pros: Minimal overhead (just clear specific fields)
❌ Cons: Must be comprehensive (easy to miss something)

**Decision: Use Option 3** with comprehensive checklist and tests.

### State Reset Implementation

**What Must Be Reset:**

```nim
proc reset_vm_state*() =
  # 1. Execution state
  VM.pc = 0
  VM.cu = nil
  VM.trace = false

  # 2. Frame stack - return all frames to pool
  var current_frame = VM.frame
  while current_frame != nil:
    let caller = current_frame.caller_frame
    put_frame(current_frame)  # Return to pool
    current_frame = caller
  VM.frame = nil

  # 3. Exception handling
  VM.exception_handlers.setLen(0)
  VM.current_exception = NIL

  # 4. Generator state
  VM.current_generator = nil

  # 5. Callbacks and futures
  VM.thread_callbacks.setLen(0)  # Clear message callbacks
  VM.futures.clear()  # Clear pending futures

  # 6. Profiling data (if enabled)
  if VM.profiling:
    VM.profile_data.clear()
    VM.profile_stack.setLen(0)

  # 7. Frame pool - validate no frames are "leaked"
  # All frames should be back in pool after cleanup
  if VM.frame_pool_index != 0:
    echo "WARNING: Frame pool leak detected: ", VM.frame_pool_index, " frames in use"
    # Force reset
    VM.frame_pool_index = 0
```

**What Can Be Preserved (shared across tasks):**
- `VM.symbols` - symbol table pointer (read-only)
- `VM.frame_pool` - the pool itself (frames returned, not recreated)
- `VM.ref_pool` - reference pool (reused)
- `App` and class references (immutable)
- Namespaces (global, gene, genex)

### Thread Handler with State Reset

```nim
proc thread_handler(thread_id: int) {.gcsafe.} =
  # Initialize ONCE per thread
  init_vm_for_thread(thread_id)
  VM.thread_id = thread_id

  # Message loop - reuse thread
  while true:
    # Blocking receive
    let msg = THREADS[thread_id].channel.recv()

    # Check for termination
    if msg.type == MtTerminate:
      break

    # CRITICAL: Reset VM state from previous execution
    reset_vm_state()

    # Execute message with clean state
    case msg.type:
    of MtRun, MtRunWithReply:
      VM.frame = get_frame()
      VM.frame.stack_index = 0
      VM.frame.scope = new_scope()

      VM.cu = msg.payload.compilation_unit
      VM.pc = 0

      let result = VM.run()

      if msg.type == MtRunWithReply:
        send_reply(msg.id, result)

    of MtSend, MtSendWithReply:
      handle_user_message(msg)

    # State automatically reset on next loop iteration

  # Thread terminating
  cleanup_thread(thread_id)
```

### Validation Strategy

**Unit Tests:**
```nim
test "thread state reset clears stack":
  VM.frame = get_frame()
  VM.frame.push(42.to_value())
  VM.frame.push(99.to_value())

  reset_vm_state()

  check VM.frame == nil  # Frame returned to pool

test "thread state reset clears exception handlers":
  VM.exception_handlers.add(ExceptionHandler(...))
  VM.exception_handlers.add(ExceptionHandler(...))

  reset_vm_state()

  check VM.exception_handlers.len == 0

test "thread state reset clears callbacks":
  VM.thread_callbacks.add(callback1)
  VM.thread_callbacks.add(callback2)

  reset_vm_state()

  check VM.thread_callbacks.len == 0
```

**Integration Tests:**
```gene
# Test: Execute two tasks sequentially, ensure no contamination
(var thread (spawn (keep_alive)))

# Task 1: Set variable
(.send thread (do
  (var x 42)
  (.send $main_thread x)))

(var result1 (await (recv)))
(assert (== result1 42))

# Task 2: Try to access x (should fail - clean state)
(.send thread (do
  (try
    (var y x)  # x should not exist
    (.send $main_thread "LEAKED")
    catch *
    (.send $main_thread "CLEAN"))))

(var result2 (await (recv)))
(assert (== result2 "CLEAN"))
```

### Edge Cases

**Case 1: Thread crashes mid-execution**
- Exception handler in thread_handler catches errors
- Still calls reset_vm_state() before next message
- Thread remains alive and functional

**Case 2: Infinite loop in thread**
- No automatic cleanup (can't interrupt)
- Timeout mechanism needed (future work)
- For now: Document that threads can hang

**Case 3: Memory leak in thread**
- Frame pool validation detects leaked frames
- Warning logged, pool forcibly reset
- Thread continues but with performance impact

**Case 4: Channel overflow**
- Channel has CHANNEL_LIMIT capacity
- Send blocks if full (backpressure)
- Thread should consume messages to prevent deadlock

## Decisions

### Decision 1: VM Thread-Local Storage

**Chosen Approach:** Make VM variable thread-local with `{.threadvar.}` pragma

**Rationale:**
- Each thread needs separate execution state (pc, frame, exception handlers)
- App is already thread-local, VM should be too
- Nim's {.threadvar.} provides automatic per-thread storage
- No manual thread ID tracking needed

**Alternative Considered:** Thread ID parameter passed to all VM functions
- Would require changing every VM function signature
- Error-prone (easy to forget thread ID)
- Less idiomatic in Nim

**Implementation:**
```nim
# Current (WRONG):
var VM = VirtualMachine(...)

# Fixed:
var VM* {.threadvar.}: VirtualMachine

# Initialize per thread:
proc init_vm_for_thread*(thread_id: int) {.gcsafe.} =
  VM = VirtualMachine(
    exception_handlers: @[],
    current_exception: NIL,
    symbols: addr SYMBOLS,  # Shared read-only
  )
  VM.frame_pool = newSeqOfCap[Frame](256)
  VM.ref_pool = newSeqOfCap[RefObj](256)
```

### Decision 2: Isolated Memory Pools

**Chosen Approach:** Move frame/ref pools to per-VM instance

**Rationale:**
- Current global pools are thread-unsafe (concurrent access corrupts state)
- Each thread allocating/freeing frames concurrently would race
- Per-VM pools provide full isolation
- Trade-off: More memory (256 frames × 64 threads = 16K frames) for safety

**Alternative Considered:** Locked global pools
- Would create contention bottleneck
- Lock overhead on every frame allocation/deallocation
- Serializes frame allocation across threads (defeats parallelism)

**Implementation:**
```nim
# Before (UNSAFE):
var FRAMES: seq[Frame]  # Global
var REF_POOL: seq[RefObj]  # Global

# After (SAFE):
VirtualMachine* = ref object
  # ... existing fields ...
  frame_pool*: seq[Frame]
  ref_pool*: seq[RefObj]

proc get_frame*(): Frame =
  # Access VM.frame_pool instead of global FRAMES
  if VM.frame_pool.len > VM.frame_pool_index:
    result = VM.frame_pool[VM.frame_pool_index]
    VM.frame_pool_index.inc()
  else:
    result = cast[Frame](alloc0(sizeof(FrameObj)))
    VM.frame_pool.add(result)
    VM.frame_pool_index.inc()
```

### Decision 3: Message Passing via Channels

**Chosen Approach:** Nim's std/channels for inter-thread communication

**Rationale:**
- Channels provide type-safe FIFO message passing
- Built-in to Nim standard library (no dependencies)
- Automatically handles message copying (GC-safe)
- Blocking recv() and non-blocking try_recv() both available
- Proven in gene-new reference implementation

**Alternative Considered:** Shared memory with locks
- Violates isolation goal
- Race conditions and deadlocks possible
- Harder to debug and reason about

**Message Structure:**
```nim
ThreadMessageType* = enum
  MtSend          # Send data, no reply
  MtSendWithReply # Send data, expect reply
  MtRun           # Run code, no reply
  MtRunWithReply  # Run code, expect reply
  MtReply         # Reply to previous message

ThreadMessage* = object
  id*: int                    # Unique message ID
  type*: ThreadMessageType
  payload*: Value             # Data or CompilationUnit
  from_message_id*: int       # For MtReply
  from_thread_id*: int        # Sender thread ID
  from_thread_secret*: int    # Sender thread secret
  handled*: bool              # For user callbacks
```

### Decision 4: Thread Pool with Secret Validation

**Chosen Approach:** Fixed pool of 64 threads with random secret tokens

**Rationale:**
- Fixed size simplifies allocation (array vs dynamic structures)
- Secret prevents use-after-free (thread reference becomes invalid after cleanup)
- 64 threads sufficient for most workloads (CPU-bound limited by core count)
- Reusing threads amortizes spawn cost

**Secret Validation:**
```nim
ThreadMetadata* = object
  id*: int
  secret*: int              # Random token, changes on cleanup
  in_use*: bool
  parent_id*: int
  channel*: Channel[ThreadMessage]
  thread*: Thread[int]

# Usage:
let thread = spawn(...)  # Returns VkThread(id=5, secret=12345)
# ... later ...
if THREADS[thread.thread_id].secret != thread.thread_secret:
  raise "Thread no longer valid (already cleaned up)"
```

**Alternative Considered:** No validation (use-after-free possible)
- Thread could be reused while old reference still exists
- Messages sent to wrong thread
- Security issue (accidental cross-thread communication)

### Decision 5: Bytecode Compilation Strategy

**Chosen Approach:** Compile on main thread, send CompilationUnit to workers

**Rationale:**
- Bytecode is immutable (safe to share across threads)
- Compilation happens once, execution happens many times
- More efficient than gene-new's re-translation per thread
- Leverages bytecode VM architecture advantage

**Flow:**
```
Main Thread                    Worker Thread
─────────────                  ─────────────
Parse source
↓
Compile to bytecode (CU)
↓
Spawn thread ─────────────────→ Receive CU
                                ↓
                                Execute bytecode
                                ↓
                                Send result ────→ Receive result (Future)
```

**Alternative Considered:** Send source code, compile in worker
- Duplicates compilation work
- Compiler may not be thread-safe (needs investigation)
- Slower than sending pre-compiled bytecode

### Decision 6: Class Sharing Strategy

**Chosen Approach:** Share read-only class definitions across threads

**Rationale:**
- Built-in classes are immutable after initialization (Object, String, Array, etc.)
- Each thread's App references same Class objects
- Method lookup is read-only (no mutations)
- Memory efficient (don't duplicate 30+ classes × 64 threads)

**Implementation:**
```nim
# Main thread initializes classes once
proc init_builtin_classes() =
  App.app.object_class = new_class("Object")
  App.app.string_class = new_class("String")
  # ... 30+ classes ...

# Worker thread copies references
proc init_vm_for_thread*(thread_id: int) =
  # Create new App
  App = new_app_value()

  # Copy class references from main thread
  # (Classes themselves are shared read-only)
  App.app.object_class = MAIN_THREAD_APP.object_class
  App.app.string_class = MAIN_THREAD_APP.string_class
  # ...
```

**Alternative Considered:** Per-thread class duplication
- Wastes memory (64 copies of each class)
- More initialization work per thread
- Allows dynamic method addition per thread (not a requirement)

**Trade-off Accepted:** Cannot add methods dynamically from worker threads (acceptable constraint)

## Architecture Comparison

### Current (Single-Threaded)
```
┌─────────────────────┐
│   Main Thread       │
│                     │
│  ┌───────────────┐  │
│  │ VM (global)   │  │
│  │ App (threadvar)│ │
│  │ FRAMES (global)│ │
│  └───────────────┘  │
└─────────────────────┘
```

### Proposed (Multi-Threaded)
```
Main Thread            Worker Thread 1        Worker Thread 2
┌─────────────┐       ┌─────────────┐        ┌─────────────┐
│ VM (thread) │       │ VM (thread) │        │ VM (thread) │
│ App (local) │       │ App (local) │        │ App (local) │
│ Frame Pool  │       │ Frame Pool  │        │ Frame Pool  │
└──────┬──────┘       └──────┬──────┘        └──────┬──────┘
       │                     │                       │
       │ Channel[Message]    │                       │
       ├─────────────────────┤                       │
       │                     │                       │
       └─────────────────────┴───────────────────────┘
                      │
              Shared (Read-Only)
          ┌──────────────────────┐
          │ SYMBOLS (global)     │
          │ Classes (immutable)  │
          └──────────────────────┘
```

### Execution Flow: spawn_return

```
1. Main Thread: Compile code to bytecode
   Gene source → Parser → Compiler → CompilationUnit

2. Main Thread: Spawn worker thread
   get_free_thread() → thread_id = 5
   init_thread(5, parent_id = 0)
   createThread(THREADS[5].thread, thread_handler, 5)

3. Main Thread: Send bytecode to worker
   msg = ThreadMessage(
     type: MtRunWithReply,
     payload: compilation_unit,
     id: 123,
     from_thread_id: 0
   )
   THREADS[5].channel.send(msg)

4. Main Thread: Create future for result
   future = new_future_value()
   VM.futures[123] = future
   return future

5. Worker Thread: Receive and execute
   msg = THREADS[5].channel.recv()  # Blocking
   VM.cu = msg.payload.compilation_unit
   VM.pc = 0
   result = VM.run()

6. Worker Thread: Send reply
   reply = ThreadMessage(
     type: MtReply,
     payload: result,
     from_message_id: 123
   )
   THREADS[0].channel.send(reply)

7. Main Thread: Complete future (via channel poll)
   check_channel()
   msg = try_recv()
   VM.futures[123].complete(msg.payload)

8. Main Thread: Await returns result
   await future → result
```

## Risks / Trade-offs

### Risk 1: VM Not Truly Thread-Local
**Impact:** If VM remains global, threads will corrupt each other's state (crashes)
**Mitigation:**
- Add {.threadvar.} pragma (1 line change)
- Test thoroughly with concurrent execution
- Use thread sanitizer in development

### Risk 2: Memory Pool Corruption
**Impact:** Global pools with concurrent access causes frame corruption
**Mitigation:**
- Move pools to per-VM (isolated by design)
- Validate with stress tests (1000+ threads)
- Use memory sanitizer to detect corruption

### Risk 3: GC Stop-the-World Pauses
**Impact:** All threads pause during GC, reduces parallelism efficiency
**Mitigation:**
- Accept trade-off (Nim's GC architecture limitation)
- Minimize allocations in hot paths
- Consider future migration to ARC/ORC (deterministic memory management)

### Risk 4: Channel Message Copying Overhead
**Impact:** Large messages (e.g., large arrays) are copied, not shared
**Mitigation:**
- Document best practice: send small messages, compute in thread
- For large data: send reference + read-only access pattern
- Profile message sizes in production

### Risk 5: Debugging Multi-Threaded Code
**Impact:** Race conditions, deadlocks harder to diagnose than single-threaded
**Mitigation:**
- Provide debug mode with thread execution traces
- Add logging for thread spawn/join/message events
- Recommend message passing patterns (less error-prone than shared state)

### Risk 6: Class Method Addition
**Impact:** Cannot dynamically add methods from worker threads (classes are shared read-only)
**Mitigation:**
- Document limitation in thread safety guide
- If needed: add locking around class method tables
- Not a requirement for initial implementation

## Migration Plan

### Phase 0: Thread Safety Fixes (1 week)
1. Add `{.threadvar.}` to VM variable (types.nim:3372)
2. Move frame_pool/ref_pool to VirtualMachine object
3. Update get_frame()/put_frame() to use VM.frame_pool
4. Test single-threaded execution still works
5. Run memory sanitizer to detect issues

**Rollback:** Revert VM to global (but keep pools in struct for future)

### Phase 1: Thread Infrastructure (2 weeks)
1. Add ThreadMessage, ThreadMetadata types to types.nim
2. Implement get_free_thread(), init_thread(), cleanup_thread()
3. Add THREADS array[1..64, ThreadMetadata]
4. Implement channel operations (send/recv wrappers)
5. Add init_vm_for_thread() function

**Rollback:** Remove thread types (no runtime impact yet)

### Phase 2: Thread Handler (2 weeks)
1. Create vm/thread.nim module
2. Implement thread_handler(thread_id) with message loop
3. Handle MtRun: execute bytecode, no reply
4. Handle MtRunWithReply: execute bytecode, send result
5. Handle MtReply: complete future
6. Test basic message receive/send

**Rollback:** Don't call thread_handler yet (not exposed to users)

### Phase 3: Spawn Implementation (1 week)
1. Add IkSpawnThread instruction to InstructionKind
2. Update compiler to emit IkSpawnThread for (spawn ...) syntax
3. Implement spawn_thread() function
4. Handle spawn vs spawn_return variants
5. Test spawn with simple expressions

**Rollback:** Compiler doesn't emit IkSpawnThread (feature disabled)

### Phase 4: Message Passing (2 weeks)
1. Add IkSendMessage, IkCheckChannel, IkThreadJoin instructions
2. Implement message sending to thread
3. Implement channel polling in main VM loop
4. Handle MtSend, MtSendWithReply message types
5. Integrate Future completion with channel replies
6. Test send/receive patterns

**Rollback:** Remove message instructions (spawn still works, no communication)

### Phase 5: Thread Methods (1 week)
1. Create Thread class with methods (send, join, parent, keep_alive)
2. Create ThreadMessage class with methods (payload, reply, mark_handled)
3. Add $thread special variable (current thread reference)
4. Implement on_message callback registration
5. Test full API surface

**Rollback:** Remove classes (use lower-level API)

### Phase 6: Testing & Validation (2 weeks)
1. Unit tests for thread spawn/join
2. Message passing tests (send/recv/reply)
3. Concurrent execution tests (multiple threads running simultaneously)
4. Stress tests (64 threads, 1000+ messages)
5. Memory leak detection (valgrind/sanitizer)
6. Performance benchmarks (CPU-bound parallelism)

### Deployment Strategy
- **Alpha Release**: Thread safety fixes + basic spawn (Phases 0-3)
- **Beta Release**: Full message passing (Phases 4-5)
- **Stable Release**: All testing complete (Phase 6)

### User Migration
**Before (single-threaded):**
```gene
(var results [])
(for i in (range 10)
  (.push results (* i i)))  # Sequential
```

**After (multi-threaded):**
```gene
(var futures [])
(for i in (range 10)
  (.push futures (spawn_return (* i i))))  # Parallel

(var results [])
(for f in futures
  (.push results (await f)))
```

**No Breaking Changes:** Existing code runs unchanged, threading is opt-in.

## Open Questions

1. **Should thread pool size be configurable?**
   - Current: Fixed 64 threads
   - Alternative: Environment variable GENE_MAX_THREADS
   - Decision: Start with fixed, add config if needed

2. **How to handle thread panics/crashes?**
   - Current: Thread dies, channel closed
   - Alternative: Send exception message to parent
   - Decision: Send MtReply with exception payload

3. **Should threads auto-terminate or wait for join?**
   - Current: Auto-terminate after MtRun completes
   - Alternative: Keep alive until explicit .join() or .terminate()
   - Decision: Auto-terminate (simpler lifecycle)

4. **How to debug suspended threads?**
   - Need tooling to inspect thread states
   - Consider debug mode with thread state dump
   - Defer to post-MVP

5. **Integration with async event loop?**
   - Threads poll channels like async polls event loop
   - Can spawn threads from async code and vice versa
   - Test interaction patterns thoroughly

6. **Memory limit per thread?**
   - No built-in limit (relies on OS/GC)
   - Could add frame pool size limit
   - Monitor in production, add limits if needed
