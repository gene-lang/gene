# Implementation Tasks: Thread Support

## Phase 0: Thread Safety Fixes (1 week)

### 0.1 VM Thread-Local Conversion
- [ ] 0.1.1 Add {.threadvar.} pragma to VM variable (types.nim:3372)
- [ ] 0.1.2 Update VM initialization to work per-thread
- [ ] 0.1.3 Create init_vm_for_thread() function
- [ ] 0.1.4 Test VM can be initialized multiple times (different threads)

### 0.2 Memory Pool Isolation
- [ ] 0.2.1 Add frame_pool: seq[Frame] to VirtualMachine object
- [ ] 0.2.2 Add ref_pool: seq[RefObj] to VirtualMachine object
- [ ] 0.2.3 Add frame_pool_index, ref_pool_index trackers
- [ ] 0.2.4 Update get_frame() to use VM.frame_pool instead of global FRAMES
- [ ] 0.2.5 Update put_frame() to use VM.frame_pool
- [ ] 0.2.6 Update ref allocation to use VM.ref_pool
- [ ] 0.2.7 Remove global FRAMES and REF_POOL variables

### 0.3 Testing & Validation
- [ ] 0.3.1 Run full test suite to ensure no regressions
- [ ] 0.3.2 Test VM initialization/cleanup cycles
- [ ] 0.3.3 Run memory sanitizer to detect leaks
- [ ] 0.3.4 Validate frame pool growth/reuse works correctly
- [ ] 0.3.5 Benchmark single-threaded performance (should be unchanged)

## Phase 1: Thread Infrastructure (2 weeks)

### 1.1 Type Definitions
- [ ] 1.1.1 Add ThreadMessageType enum to types.nim (MtSend, MtSendWithReply, MtRun, MtRunWithReply, MtReply)
- [ ] 1.1.2 Add ThreadMessage object (id, type, payload, from_message_id, from_thread_id, from_thread_secret, handled)
- [ ] 1.1.3 Add ThreadState enum (TsUninitialized, TsFree, TsBusy)
- [ ] 1.1.4 Add ThreadMetadata object (id, secret, state, in_use, parent_id, parent_secret, thread, channel)
- [ ] 1.1.5 Add THREADS: array[1..64, ThreadMetadata] global variable
- [ ] 1.1.6 Add CHANNEL_LIMIT constant (1000)

### 1.2 Thread Pool Management
- [ ] 1.2.1 Implement get_free_thread(): int (find available thread slot)
- [ ] 1.2.2 Implement init_thread(id: int) (initialize thread metadata and channel)
- [ ] 1.2.3 Implement init_thread(id: int, parent_id: int) (with parent tracking)
- [ ] 1.2.4 Implement cleanup_thread(id: int) (mark as free, rotate secret)
- [ ] 1.2.5 Test thread allocation/deallocation cycles
- [ ] 1.2.6 Test exhausting thread pool (all 64 threads in use)

### 1.3 Main Thread Initialization
- [ ] 1.3.1 Implement init_main_thread() to initialize THREADS[0]
- [ ] 1.3.2 Set thread 0 metadata (id=0, parent_id=0, in_use=true, never freed)
- [ ] 1.3.3 Open channel for thread 0
- [ ] 1.3.4 Add $main_thread to global namespace referencing thread 0
- [ ] 1.3.5 Test main thread metadata persists for program lifetime

### 1.4 VM Initialization
- [x] 1.4.1 Implement init_vm_for_thread(thread_id: int) {.gcsafe.}
- [x] 1.4.2 Initialize VM with per-thread pools
- [x] 1.4.3 Initialize App with namespace references (init_gene_namespace, register_io_functions)
- [x] 1.4.4 Copy built-in class references from main thread
- [x] 1.4.5 Set up symbol table pointer (shared read-only)
- [x] 1.4.6 Add $main_thread to worker's global namespace (reference to thread 0)
- [x] 1.4.7 Test VM initialization in separate threads

### 1.5 Channel Operations
- [ ] 1.5.1 Test channel.open() for thread channels
- [ ] 1.5.2 Test channel.send() for message passing
- [ ] 1.5.3 Test channel.recv() blocking receive
- [ ] 1.5.4 Test channel.try_recv() non-blocking receive
- [ ] 1.5.5 Validate message copying (GC safety)

## Phase 2: Thread Handler (2 weeks)

### 2.1 State Reset Implementation
- [ ] 2.1.1 Create reset_vm_state() procedure in vm.nim or vm/thread.nim
- [ ] 2.1.2 Reset execution state (pc = 0, cu = nil, trace = false)
- [ ] 2.1.3 Return all frames to pool (walk frame chain, call put_frame)
- [ ] 2.1.4 Clear exception handlers (setLen(0))
- [ ] 2.1.5 Clear current_exception (set to NIL)
- [ ] 2.1.6 Clear generator state (current_generator = nil)
- [ ] 2.1.7 Clear callbacks and futures (thread_callbacks, futures table)
- [ ] 2.1.8 Clear profiling data if enabled
- [ ] 2.1.9 Validate frame pool index is 0 (leak detection)
- [ ] 2.1.10 Test reset_vm_state clears all state correctly

### 2.2 Thread Handler Module
- [ ] 2.2.1 Create src/gene/vm/thread.nim module
- [ ] 2.2.2 Import required modules (threads, channels, vm, types)
- [ ] 2.2.3 Add thread handler function signature
- [ ] 2.2.4 Implement basic thread lifecycle (init → run → cleanup)

### 2.3 Message Receive Loop
- [ ] 2.3.1 Implement while true loop in thread_handler
- [ ] 2.3.2 Implement blocking recv() for messages
- [ ] 2.3.3 Add MtTerminate check to break loop
- [ ] 2.3.4 Call reset_vm_state() after recv, before execution
- [ ] 2.3.5 Add message type dispatch (case statement)
- [ ] 2.3.6 Test message receive with mock messages

### 2.4 MtRun Handler
- [ ] 2.3.1 Extract CompilationUnit from message payload
- [ ] 2.3.2 Set VM.cu and VM.pc
- [ ] 2.3.3 Execute bytecode (VM.run())
- [ ] 2.3.4 Discard result (no reply)
- [ ] 2.3.5 Test MtRun execution with simple bytecode

### 2.5 MtRunWithReply Handler
- [ ] 2.4.1 Execute bytecode (same as MtRun)
- [ ] 2.4.2 Capture result value
- [ ] 2.4.3 Create reply message (MtReply)
- [ ] 2.4.4 Send reply to parent thread channel
- [ ] 2.4.5 Test MtRunWithReply with result verification

### 2.6 MtReply Handler
- [ ] 2.5.1 Lookup future by from_message_id
- [ ] 2.5.2 Complete future with payload
- [ ] 2.5.3 Remove future from VM.futures table
- [ ] 2.5.4 Test reply delivery to waiting futures

### 2.7 Exception Handling
- [ ] 2.6.1 Wrap bytecode execution in try/catch
- [ ] 2.6.2 Send MtReply with exception on failure
- [ ] 2.6.3 Test exception propagation from worker to parent

## Phase 3: Spawn Implementation (1 week)

### 3.1 Bytecode Instruction
- [ ] 3.1.1 Add IkSpawnThread to InstructionKind enum (types.nim)
- [ ] 3.1.2 Define instruction format (return_value flag)
- [ ] 3.1.3 Document instruction in comments

### 3.2 Compiler Support
- [ ] 3.2.1 Detect (spawn ...) and (spawn_return ...) in compiler
- [ ] 3.2.2 Compile body to separate CompilationUnit
- [ ] 3.2.3 Emit IkPushValue with CompilationUnit
- [ ] 3.2.4 Emit IkPushValue with return_value boolean
- [ ] 3.2.5 Emit IkSpawnThread instruction
- [ ] 3.2.6 Test compiler generates correct bytecode

### 3.3 Spawn Function
- [ ] 3.3.1 Implement spawn_thread(cu: CompilationUnit, return_value: bool): Value
- [ ] 3.3.2 Get free thread from pool
- [ ] 3.3.3 Initialize thread metadata (secret, parent_id)
- [ ] 3.3.4 Create Nim thread with createThread()
- [ ] 3.3.5 Send ThreadMessage with MtRun or MtRunWithReply
- [ ] 3.3.6 Return thread reference or future

### 3.4 Instruction Handler
- [ ] 3.4.1 Implement IkSpawnThread case in vm.nim
- [ ] 3.4.2 Pop return_value and CompilationUnit from stack
- [ ] 3.4.3 Call spawn_thread()
- [ ] 3.4.4 Push result (thread ref or future) to stack
- [ ] 3.4.5 Test instruction execution

### 3.5 Testing
- [x] 3.5.1 Test spawn with simple expression (println) - tests/test_thread.nim passes
- [x] 3.5.2 Test spawn_return with computation - test passes (1+2=3)
- [x] 3.5.3 Test multiple spawns (10 threads) - test_thread.nim tests multiple spawns
- [x] 3.5.4 Test spawn with arguments (variables in scope) - test_thread.nim tests variables
- [ ] 3.5.5 Test thread exhaustion handling

## Phase 4: Message Passing (2 weeks)

### 4.1 Send Message Instruction
- [ ] 4.1.1 Add IkSendMessage to InstructionKind
- [ ] 4.1.2 Update compiler to emit IkSendMessage for (.send thread msg)
- [ ] 4.1.3 Implement instruction handler (pop thread, pop message, send)
- [ ] 4.1.4 Validate thread secret before sending
- [ ] 4.1.5 Test message sending

### 4.2 Check Channel Instruction
- [ ] 4.2.1 Add IkCheckChannel to InstructionKind
- [ ] 4.2.2 Implement non-blocking channel poll
- [ ] 4.2.3 Handle MtSend messages (invoke callbacks)
- [ ] 4.2.4 Handle MtSendWithReply messages
- [ ] 4.2.5 Handle MtReply messages (complete futures)

### 4.3 Channel Polling Integration
- [ ] 4.3.1 Add channel check to VM main loop (every N instructions)
- [ ] 4.3.2 Configure polling frequency (every 100 instructions?)
- [ ] 4.3.3 Test polling doesn't impact single-threaded performance
- [ ] 4.3.4 Test message delivery latency

### 4.4 Future Integration
- [ ] 4.4.1 Add VM.futures table (message_id → Future)
- [ ] 4.4.2 Store future when sending MtRunWithReply or MtSendWithReply
- [ ] 4.4.3 Complete future when MtReply received
- [ ] 4.4.4 Clean up future from table after completion
- [ ] 4.4.5 Test future lifecycle

### 4.5 User Callbacks
- [ ] 4.5.1 Add VM.thread_callbacks: seq[Value] for message handlers
- [ ] 4.5.2 Implement callback registration (.on_message)
- [ ] 4.5.3 Invoke callbacks when MtSend received
- [ ] 4.5.4 Support msg.mark_handled() to stop propagation
- [ ] 4.5.5 Test callback execution and handled flag

### 4.6 Testing
- [ ] 4.6.1 Test send without reply
- [ ] 4.6.2 Test send with reply (future completion)
- [ ] 4.6.3 Test multiple messages to same thread
- [ ] 4.6.4 Test bidirectional communication (parent↔child)
- [ ] 4.6.5 Test message ordering (FIFO guarantee)

## Phase 5: Thread Methods (1 week)

### 5.1 Thread Value Type
- [ ] 5.1.1 Add VkThread to ValueKind enum
- [ ] 5.1.2 Add thread_id and thread_secret fields to Value union
- [ ] 5.1.3 Implement thread value construction
- [ ] 5.1.4 Test thread value creation

### 5.2 Thread Class
- [ ] 5.2.1 Create Thread class in VM initialization
- [ ] 5.2.2 Implement .send(message) method
- [ ] 5.2.3 Implement .send(message ^reply true) variant
- [ ] 5.2.4 Implement .join() method (joinThread wrapper)
- [ ] 5.2.5 Implement .parent() method (return parent thread ref)
- [ ] 5.2.6 Implement .on_message(callback) method
- [ ] 5.2.7 Implement .keep_alive() method (message loop)

### 5.3 ThreadMessage Class
- [ ] 5.3.1 Add VkThreadMessage to ValueKind
- [ ] 5.3.2 Create ThreadMessage class
- [ ] 5.3.3 Implement .payload() method
- [ ] 5.3.4 Implement .reply(value) method
- [ ] 5.3.5 Implement .mark_handled() method

### 5.4 Special Variables
- [ ] 5.4.1 Add $thread to global namespace (current thread reference)
- [ ] 5.4.2 Initialize $thread in init_vm_for_thread()
- [ ] 5.4.3 Test $thread access in main and worker threads

### 5.5 Compiler Integration
- [ ] 5.5.1 Recognize spawn and spawn_return as special forms
- [ ] 5.5.2 Handle ^args property for thread arguments
- [ ] 5.5.3 Handle ^reply property for send with reply
- [ ] 5.5.4 Test syntax compilation

### 5.6 Testing
- [ ] 5.6.1 Test all Thread methods
- [ ] 5.6.2 Test all ThreadMessage methods
- [ ] 5.6.3 Test $thread variable access
- [ ] 5.6.4 Test method chaining
- [ ] 5.6.5 Test argument passing (^args)

## Phase 6: Testing & Validation (2 weeks)

### 6.1 Unit Tests
- [ ] 6.1.1 Test thread spawn without return value
- [ ] 6.1.2 Test thread spawn with return value (future)
- [ ] 6.1.3 Test thread join
- [ ] 6.1.4 Test parent thread reference
- [ ] 6.1.5 Test thread secret validation

### 6.2 Message Passing Tests
- [ ] 6.2.1 Test send without reply
- [ ] 6.2.2 Test send with reply
- [ ] 6.2.3 Test multiple messages to one thread
- [ ] 6.2.4 Test broadcast (one thread → many threads)
- [ ] 6.2.5 Test bidirectional communication

### 6.3 Concurrency Tests
- [ ] 6.3.1 Test 10 threads computing in parallel
- [ ] 6.3.2 Test 64 threads (max pool size)
- [ ] 6.3.3 Test thread pool exhaustion and recovery
- [ ] 6.3.4 Test concurrent message passing (many threads sending)
- [ ] 6.3.5 Test mixed spawn/send operations

### 6.4 Exception Handling
- [ ] 6.4.1 Test exception in thread propagates to future
- [ ] 6.4.2 Test exception in message handler
- [ ] 6.4.3 Test thread crash recovery
- [ ] 6.4.4 Test unhandled exception behavior

### 6.5 Stress Tests
- [ ] 6.5.1 Run 1000 spawns (reuse threads)
- [ ] 6.5.2 Send 10,000 messages through channels
- [ ] 6.5.3 Long-running threads (hours)
- [ ] 6.5.4 Rapid spawn/join cycles
- [ ] 6.5.5 Memory pressure test (large message payloads)

### 6.6 Performance Benchmarks
- [ ] 6.6.1 Benchmark CPU-bound parallel workload (matrix multiply)
- [ ] 6.6.2 Benchmark scaling: 1, 2, 4, 8 threads
- [ ] 6.6.3 Benchmark message passing latency
- [ ] 6.6.4 Benchmark thread spawn overhead
- [ ] 6.6.5 Compare to single-threaded baseline

### 6.7 State Isolation Tests
- [ ] 6.7.1 Test sequential task execution on same thread (no variable leaks)
- [ ] 6.7.2 Test exception handlers don't persist across tasks
- [ ] 6.7.3 Test callbacks cleared between tasks
- [ ] 6.7.4 Test futures cleared between tasks
- [ ] 6.7.5 Test frame pool leak detection warnings

### 6.8 Memory Safety
- [ ] 6.7.1 Run with memory sanitizer (detect use-after-free)
- [ ] 6.7.2 Run with thread sanitizer (detect race conditions)
- [ ] 6.7.3 Profile memory usage (per-thread overhead)
- [ ] 6.7.4 Test for memory leaks (valgrind/instruments)
- [ ] 6.7.5 Validate frame pool doesn't grow unbounded

### 6.9 Integration Tests
- [ ] 6.8.1 Test threads with async/await (mixed concurrency)
- [ ] 6.8.2 Test threads calling native functions
- [ ] 6.8.3 Test threads with exception handlers
- [ ] 6.8.4 Test threads with generators
- [ ] 6.8.5 Test threads with classes/methods

### 6.10 Documentation
- [ ] 6.9.1 Write threading guide (when to use threads vs async)
- [ ] 6.9.2 Document thread safety guarantees
- [ ] 6.9.3 Document limitations (no shared memory, no dynamic methods)
- [ ] 6.9.4 Add examples (parallel map, worker pool pattern)
- [ ] 6.9.5 Add troubleshooting guide

### 6.11 Test Suite Integration
- [ ] 6.10.1 Add testsuite/threading/ directory
- [ ] 6.10.2 Create numbered test files (001_spawn.gene, 002_send.gene, etc.)
- [ ] 6.10.3 Add expected output comments
- [ ] 6.10.4 Update run_tests.sh to include threading tests
- [ ] 6.10.5 Validate all tests pass consistently

---

**Total Estimated Time:** 11 weeks
**Critical Path:** Phase 0 → Phase 1 → Phase 2 → Phase 3 → Phase 4 → Phase 5 → Phase 6 (all sequential)
**Parallel Opportunities:** None (each phase depends on previous)
