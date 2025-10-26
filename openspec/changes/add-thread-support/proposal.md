# Proposal: Add Thread Support

## Why

Gene currently lacks true parallel execution capabilities. While async/await enables concurrent I/O, it runs in a single thread and cannot leverage multi-core CPUs for CPU-bound workloads. This limits Gene's ability to:

- Utilize multiple CPU cores for parallel computation
- Handle CPU-intensive tasks efficiently
- Scale to modern multi-core hardware
- Compete with languages offering built-in threading (Go, Rust, Java, Python)

**Real-world limitations:**
- Image processing: Cannot process multiple images in parallel
- Data transformation: Large dataset operations are single-threaded
- Web servers: Cannot handle multiple CPU-intensive requests simultaneously
- Scientific computing: Matrix operations run on single core

**Complementary to async:**
- **Async**: Concurrent I/O on single thread (I/O-bound workloads)
- **Threads**: Parallel execution on multiple cores (CPU-bound workloads)

**Reference implementation exists:** gene-new has a working thread implementation using isolated VMs with channel-based message passing. This proposal adapts that design to Gene's bytecode VM architecture.

## What Changes

### Core Architecture
- **Isolated VM Instances**: Each thread runs its own VirtualMachine instance with separate execution state
- **Main Thread Coordination**: Thread 0 is always the main thread, all threads can communicate with it
- **Message Passing**: Threads communicate via Nim channels (no shared mutable state)
- **Thread Pool**: Fixed pool of 64 threads (thread 0 = main, 1-64 = workers) for predictable resource usage
- **Thread Safety**: Make VM thread-local and isolate memory pools

### Specific Changes
- Add `{.threadvar.}` pragma to VM variable (currently global, unsafe)
- Move frame/ref pools from global to per-VM (avoid race conditions)
- Implement ThreadMetadata and Channel[ThreadMessage] infrastructure (thread 0 = main thread)
- Add thread spawning, message sending/receiving, and join operations
- Create Thread and ThreadMessage classes with methods
- Add special variable `$main_thread` for accessing main thread from workers
- Add bytecode instructions: IkSpawnThread, IkSendMessage, IkCheckChannel, IkThreadJoin
- Ensure main thread polls its channel to receive messages from workers

### **BREAKING** Changes
- VM initialization changes (VM becomes thread-local)
- Global state separation (frame/ref pools move to per-VM)
- Memory allocation patterns change (per-thread pools vs global)

### Non-Goals (Out of Scope)
- Thread-local storage API (threads are fully isolated by design)
- Shared memory between threads (message passing only)
- Thread priorities or custom schedulers (use Nim's defaults)
- Green threads or M:N threading (use OS threads directly)
- Work-stealing or advanced scheduling (simple thread pool)

## Impact

### Affected Specs
- **threading** (NEW): Thread spawning, message passing, isolated execution

### Affected Code
- `src/gene/types.nim` (VM variable, ThreadMetadata types, VirtualMachine structure)
- `src/gene/vm.nim` (thread instruction handlers, channel polling)
- `src/gene/vm/thread.nim` (NEW) (thread spawning, message handling, thread pool)
- `src/gene/compiler.nim` (emit thread instructions)
- `src/gene/vm/core.nim` (Thread and ThreadMessage classes)

### Migration Path
- Existing code unaffected (no threading by default)
- Opt-in via `spawn` and `spawn_return` syntax
- No breaking changes to non-threaded code
- Thread support is additive feature

### Risk Assessment
- **VM Thread Safety**: Critical fix required (VM must be {.threadvar.})
- **Memory Pool Isolation**: Frame/ref pools must be per-thread to avoid corruption
- **Class Sharing**: Built-in classes shared read-only across threads (safe)
- **GC Coordination**: Nim's GC is stop-the-world (all threads pause during collection)
- **Channel Overhead**: Message copying has performance cost vs shared memory
- **Debugging Complexity**: Multi-threaded bugs harder to reproduce/diagnose

### Performance Characteristics
- **CPU-bound speedup**: Near-linear scaling with cores (4 cores → ~4× speedup)
- **Message passing overhead**: ~1-10μs per message (acceptable for coarse-grained tasks)
- **Memory overhead**: ~512KB per thread (frame pool + VM state)
- **Thread creation**: ~1-5ms per spawn (amortized via thread pool reuse)

### Timeline Estimate
- Phase 0 (Thread Safety): 1 week
- Phase 1 (Infrastructure): 2 weeks
- Phase 2 (Thread Handler): 2 weeks
- Phase 3 (Spawn): 1 week
- Phase 4 (Message Passing): 2 weeks
- Phase 5 (Thread Methods): 1 week
- Phase 6 (Testing): 2 weeks

**Total: 11 weeks** for complete implementation

### Benefits
- **Multi-core utilization**: Leverage all CPU cores for parallel workloads
- **Improved throughput**: 4× speedup on 4-core CPU for CPU-bound tasks
- **Scalability**: Handle CPU-intensive requests in parallel
- **Isolation safety**: No shared mutable state eliminates race conditions
- **Complementary**: Works alongside async for mixed I/O + CPU workloads
