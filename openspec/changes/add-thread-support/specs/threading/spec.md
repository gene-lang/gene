# Threading Capability Specification

## ADDED Requirements

### Requirement: Multi-Core Parallel Execution
The system SHALL use OS threads that the operating system can schedule across multiple CPU cores for true parallel execution.

#### Scenario: OS threads created
- **WHEN** a thread is spawned
- **THEN** an OS thread SHALL be created using Nim's createThread
- **AND** the OS thread SHALL map 1:1 to a kernel thread (POSIX pthread or Win32 thread)

#### Scenario: OS scheduler distributes across cores
- **WHEN** multiple threads are executing
- **THEN** the operating system scheduler SHALL be responsible for assigning threads to CPU cores
- **AND** threads SHALL be capable of running simultaneously on different cores

#### Scenario: Parallel speedup on multi-core CPU
- **WHEN** N CPU-intensive tasks are spawned on a system with N or more CPU cores
- **THEN** the tasks SHALL execute in parallel
- **AND** total execution time SHALL be approximately equal to the longest single task
- **AND** speedup SHALL scale near-linearly with available cores

#### Scenario: No global interpreter lock
- **WHEN** threads execute Gene bytecode
- **THEN** there SHALL be no global interpreter lock preventing parallel execution
- **AND** threads SHALL be able to execute bytecode simultaneously on different cores

### Requirement: Main Thread Coordination
The system SHALL designate thread 0 as the main thread, serving as a central coordinator that all worker threads can communicate with.

#### Scenario: Main thread is always thread 0
- **WHEN** the program starts
- **THEN** thread 0 SHALL be initialized as the main thread
- **AND** thread 0 SHALL never be spawned or cleaned up
- **AND** thread 0's metadata SHALL remain valid for the program lifetime

#### Scenario: Main thread accessible from all workers
- **WHEN** a worker thread is initialized
- **THEN** the worker SHALL have access to `$main_thread` variable
- **AND** `$main_thread` SHALL reference thread 0
- **AND** the worker SHALL be able to send messages to the main thread

#### Scenario: Main thread polls its channel
- **WHEN** the main thread executes bytecode
- **THEN** it SHALL periodically poll its channel for incoming messages
- **AND** process messages from worker threads
- **AND** invoke registered message callbacks

#### Scenario: Workers send results to main
- **WHEN** a worker thread sends a message to `$main_thread`
- **THEN** the message SHALL be delivered to thread 0's channel
- **AND** the main thread SHALL receive and process the message
- **AND** the sender SHALL continue execution (non-blocking send)

#### Scenario: Main thread parent reference
- **WHEN** main thread's parent is requested
- **THEN** it SHALL reference itself (thread_id = 0, parent_id = 0)
- **AND** no error SHALL occur

### Requirement: Isolated VM Instances
Each thread SHALL run its own VirtualMachine instance with separate execution state to ensure complete isolation.

#### Scenario: VM is thread-local
- **WHEN** a thread is spawned
- **THEN** a new VirtualMachine instance SHALL be created for that thread
- **AND** the VM instance SHALL be stored in thread-local storage ({.threadvar.})
- **AND** the VM SHALL NOT be shared with other threads

#### Scenario: Separate memory pools
- **WHEN** a thread allocates frames or references
- **THEN** the allocations SHALL come from the thread's own frame_pool and ref_pool
- **AND** no global memory pools SHALL be shared across threads
- **AND** no race conditions SHALL occur during allocation

#### Scenario: Independent execution state
- **WHEN** a thread executes bytecode
- **THEN** it SHALL maintain its own program counter (pc), frame stack, and exception handlers
- **AND** execution state SHALL NOT interfere with other threads

### Requirement: Thread State Reset
Worker threads SHALL reset their VM state between task executions to prevent contamination from previous executions.

#### Scenario: Clean state between executions
- **WHEN** a worker thread completes a task and receives a new message
- **THEN** the VM state SHALL be reset before executing the new task
- **AND** no values, variables, or handlers from the previous execution SHALL persist

#### Scenario: Frame stack cleared
- **WHEN** VM state is reset
- **THEN** all frames SHALL be returned to the frame pool
- **AND** the frame stack SHALL be empty
- **AND** no stack values SHALL remain

#### Scenario: Exception handlers cleared
- **WHEN** VM state is reset
- **THEN** all exception handlers SHALL be removed
- **AND** current_exception SHALL be set to NIL
- **AND** no exception state SHALL carry over

#### Scenario: Callbacks and futures cleared
- **WHEN** VM state is reset
- **THEN** all message callbacks SHALL be cleared
- **AND** all pending futures SHALL be removed from the futures table
- **AND** no callback or future references SHALL persist

#### Scenario: Execution state reset
- **WHEN** VM state is reset
- **THEN** program counter (pc) SHALL be set to 0
- **AND** compilation unit SHALL be cleared
- **AND** generator state SHALL be cleared

#### Scenario: Preserved state after reset
- **WHEN** VM state is reset
- **THEN** the symbol table pointer SHALL remain unchanged
- **AND** frame/ref pools SHALL be preserved (cleared but not recreated)
- **AND** App and class references SHALL remain unchanged

#### Scenario: Sequential task isolation
- **WHEN** two tasks are sent to the same worker thread sequentially
- **THEN** variables defined in the first task SHALL NOT be accessible in the second task
- **AND** each task SHALL execute with clean scope

#### Scenario: Frame pool leak detection
- **WHEN** VM state is reset
- **THEN** the system SHALL validate all frames have been returned to the pool
- **AND** if frames are leaked, a warning SHALL be logged
- **AND** the frame pool index SHALL be forcibly reset

### Requirement: Thread Pool Management
The system SHALL maintain a pool of reusable threads with fixed maximum size for predictable resource usage.

#### Scenario: Fixed pool of 64 threads
- **WHEN** threads are spawned
- **THEN** they SHALL be allocated from a pool of maximum 64 threads
- **AND** attempting to spawn when all threads are in use SHALL raise an error

#### Scenario: Thread reuse
- **WHEN** a thread completes its work
- **THEN** the thread metadata SHALL be marked as available
- **AND** the thread SHALL be reusable for subsequent spawn operations
- **AND** the thread's secret SHALL be rotated to invalidate old references

#### Scenario: Thread allocation
- **WHEN** a new thread is requested
- **THEN** the system SHALL find the first available thread slot
- **AND** initialize thread metadata (id, secret, parent_id, channel)
- **AND** mark the thread as in-use

### Requirement: Message Passing via Channels
Threads SHALL communicate exclusively through message passing using Nim channels, with no shared mutable state.

#### Scenario: Send message without reply
- **WHEN** a thread sends a message with type MtSend
- **THEN** the message SHALL be placed in the recipient thread's channel
- **AND** the sender SHALL continue execution without waiting
- **AND** no return value SHALL be provided

#### Scenario: Send message with reply
- **WHEN** a thread sends a message with type MtSendWithReply
- **THEN** a Future SHALL be created and returned to the sender
- **AND** the message SHALL be sent to the recipient
- **AND** the Future SHALL complete when a reply is received

#### Scenario: Run code without reply
- **WHEN** a thread sends code to execute with type MtRun
- **THEN** the recipient thread SHALL execute the bytecode
- **AND** no result SHALL be sent back to the sender

#### Scenario: Run code with reply
- **WHEN** a thread sends code to execute with type MtRunWithReply
- **THEN** the recipient thread SHALL execute the bytecode
- **AND** send the result back via MtReply message
- **AND** the sender's Future SHALL complete with the result

#### Scenario: Reply message delivery
- **WHEN** a thread sends a MtReply message
- **THEN** the message SHALL be delivered to the original sender's channel
- **AND** the corresponding Future SHALL be completed with the payload
- **AND** the Future SHALL be removed from the VM.futures table

### Requirement: Thread Secret Validation
Thread references SHALL use secret tokens to prevent use-after-free and ensure thread validity.

#### Scenario: Secret assigned on initialization
- **WHEN** a thread is initialized
- **THEN** a random secret token SHALL be generated and assigned
- **AND** the secret SHALL be stored in both ThreadMetadata and thread Value

#### Scenario: Secret validation before message send
- **WHEN** a message is sent to a thread
- **THEN** the thread's current secret SHALL be compared with the reference's secret
- **AND** if secrets do not match, an error SHALL be raised
- **AND** the operation SHALL NOT proceed

#### Scenario: Secret rotation on cleanup
- **WHEN** a thread is cleaned up and marked as free
- **THEN** a new random secret SHALL be generated
- **AND** old thread references with the previous secret SHALL become invalid

### Requirement: Thread Spawning
The system SHALL support spawning threads with or without return values using spawn and spawn_return syntax.

#### Scenario: Spawn thread without return value
- **WHEN** `(spawn expr)` is executed
- **THEN** a new thread SHALL be allocated from the pool
- **AND** the expression SHALL be compiled to bytecode
- **AND** the bytecode SHALL be sent to the thread via MtRun message
- **AND** a thread reference Value SHALL be returned to the caller

#### Scenario: Spawn thread with return value
- **WHEN** `(spawn_return expr)` is executed
- **THEN** a new thread SHALL be allocated from the pool
- **AND** the expression SHALL be compiled to bytecode
- **AND** the bytecode SHALL be sent to the thread via MtRunWithReply message
- **AND** a Future SHALL be returned to the caller

#### Scenario: Thread execution
- **WHEN** a worker thread receives a MtRun or MtRunWithReply message
- **THEN** it SHALL initialize a new VM instance if needed
- **AND** set VM.cu to the received CompilationUnit
- **AND** execute the bytecode from pc = 0
- **AND** capture the result value

#### Scenario: Spawn with arguments
- **WHEN** spawn is called with ^args property
- **THEN** the arguments SHALL be evaluated in the parent thread
- **AND** passed as variables in the child thread's scope
- **AND** the child thread SHALL have access to the argument values

### Requirement: Thread Join
The system SHALL support waiting for thread completion using the join operation.

#### Scenario: Join on spawned thread
- **WHEN** `.join()` is called on a thread reference
- **THEN** the calling thread SHALL block until the target thread completes
- **AND** execution SHALL resume after the thread terminates

#### Scenario: Join on already-completed thread
- **WHEN** `.join()` is called on a thread that has already finished
- **THEN** the operation SHALL return immediately without blocking

### Requirement: Channel Polling
The main VM execution loop SHALL periodically poll the thread's channel to process incoming messages.

#### Scenario: Periodic channel check
- **WHEN** the VM executes instructions
- **THEN** every N instructions (e.g., 100), the channel SHALL be polled
- **AND** polling SHALL be non-blocking (try_recv)

#### Scenario: Process pending messages
- **WHEN** messages are available in the channel
- **THEN** all available messages SHALL be processed in FIFO order
- **AND** message handlers SHALL be invoked accordingly

#### Scenario: Reply message handling
- **WHEN** a MtReply message is received
- **THEN** the corresponding Future SHALL be looked up by message ID
- **AND** the Future SHALL be completed with the reply payload
- **AND** the Future SHALL be removed from the futures table

### Requirement: Thread Methods
Thread values SHALL support methods for communication and lifecycle management.

#### Scenario: Send method without reply
- **WHEN** `.send(thread, message)` is called
- **THEN** the message SHALL be sent to the thread's channel with type MtSend
- **AND** no return value SHALL be provided

#### Scenario: Send method with reply
- **WHEN** `.send(thread, message, ^reply true)` is called
- **THEN** the message SHALL be sent with type MtSendWithReply
- **AND** a Future SHALL be returned
- **AND** the Future SHALL complete when a reply is received

#### Scenario: Parent method
- **WHEN** `.parent()` is called on a thread
- **THEN** it SHALL return a thread reference to the parent thread
- **AND** the parent's thread_id and secret SHALL be used

#### Scenario: Keep alive method
- **WHEN** `.keep_alive()` is called
- **THEN** the thread SHALL enter a message processing loop
- **AND** continue processing messages indefinitely until terminated

### Requirement: Message Callbacks
Threads SHALL support user-defined callbacks for handling incoming messages.

#### Scenario: Register message callback
- **WHEN** `.on_message(callback)` is called
- **THEN** the callback SHALL be added to the thread's callback list
- **AND** the callback SHALL be invoked for MtSend and MtSendWithReply messages

#### Scenario: Callback invocation
- **WHEN** a MtSend or MtSendWithReply message is received
- **THEN** all registered callbacks SHALL be invoked in order
- **AND** each callback SHALL receive a ThreadMessage value

#### Scenario: Message handled flag
- **WHEN** a callback calls `.mark_handled()` on a message
- **THEN** the message's handled flag SHALL be set to true
- **AND** subsequent callbacks SHALL NOT be invoked for that message

#### Scenario: Reply from callback
- **WHEN** a callback calls `.reply(value)` on a MtSendWithReply message
- **THEN** a MtReply message SHALL be sent to the sender
- **AND** the sender's Future SHALL complete with the reply value

### Requirement: Thread Value Type
The system SHALL support a Thread value type for thread references.

#### Scenario: Thread value creation
- **WHEN** a thread is spawned
- **THEN** a Value with kind VkThread SHALL be created
- **AND** it SHALL contain the thread_id and thread_secret
- **AND** it SHALL be returned to the spawning thread

#### Scenario: Thread value validation
- **WHEN** operations are performed on a thread value
- **THEN** the thread_secret SHALL be validated against ThreadMetadata
- **AND** invalid references SHALL raise an error

### Requirement: ThreadMessage Value Type
The system SHALL support a ThreadMessage value type for message handling.

#### Scenario: ThreadMessage value creation
- **WHEN** a message is received
- **THEN** a Value with kind VkThreadMessage SHALL be created
- **AND** it SHALL wrap the ThreadMessage object
- **AND** it SHALL be passed to message callbacks

#### Scenario: Payload extraction
- **WHEN** `.payload()` is called on a ThreadMessage value
- **THEN** the message's payload Value SHALL be returned

#### Scenario: Reply method
- **WHEN** `.reply(value)` is called on a ThreadMessage
- **THEN** a MtReply SHALL be sent to the sender thread
- **AND** the reply SHALL reference the original message ID

### Requirement: Bytecode Compilation Strategy
Code SHALL be compiled to bytecode on the spawning thread and sent to worker threads for execution.

#### Scenario: Compile before spawn
- **WHEN** spawn is executed
- **THEN** the expression SHALL be compiled to a CompilationUnit on the calling thread
- **AND** the CompilationUnit SHALL be immutable and shareable

#### Scenario: Execute pre-compiled bytecode
- **WHEN** a worker thread receives a CompilationUnit
- **THEN** it SHALL execute the bytecode directly without re-parsing or re-compiling
- **AND** execution SHALL be efficient (no translation overhead)

### Requirement: Exception Handling in Threads
Exceptions occurring in worker threads SHALL be propagated to the spawning thread via the Future mechanism.

#### Scenario: Exception in spawn_return
- **WHEN** an exception is thrown during thread execution with spawn_return
- **THEN** the exception SHALL be captured
- **AND** sent back as a MtReply with the exception as payload
- **AND** the Future SHALL complete in failure state

#### Scenario: Exception in spawn
- **WHEN** an exception is thrown during thread execution with spawn (no return)
- **THEN** the exception SHALL be logged or handled internally
- **AND** the thread SHALL terminate

#### Scenario: Await on failed future
- **WHEN** await is called on a Future that completed with an exception
- **THEN** the exception SHALL be re-thrown in the awaiting thread

### Requirement: Class Sharing Strategy
Built-in classes SHALL be shared read-only across threads for memory efficiency.

#### Scenario: Class references initialized per thread
- **WHEN** a worker thread is initialized
- **THEN** its App SHALL be populated with references to built-in classes
- **AND** the Class objects SHALL be shared (not duplicated)
- **AND** method lookup SHALL be read-only (no dynamic method addition)

#### Scenario: Safe method lookup
- **WHEN** a thread performs method lookup on a class
- **THEN** the lookup SHALL be read-only
- **AND** no race conditions SHALL occur
- **AND** all threads SHALL see consistent method definitions

### Requirement: Special Variables
Threads SHALL have access to special variables for thread-specific context.

#### Scenario: $thread variable
- **WHEN** `$thread` is accessed
- **THEN** it SHALL return a thread reference to the current thread
- **AND** the reference SHALL have the correct thread_id and secret

#### Scenario: $main_thread variable
- **WHEN** `$main_thread` is accessed from any thread
- **THEN** it SHALL return a thread reference to thread 0
- **AND** the reference SHALL have thread_id = 0
- **AND** the reference SHALL have the valid secret for thread 0

#### Scenario: $main_thread in main thread
- **WHEN** `$main_thread` is accessed from thread 0
- **THEN** it SHALL reference thread 0 (self-reference)
- **AND** it SHALL be equivalent to `$thread` in the main thread

### Requirement: Performance Characteristics
Thread support SHALL provide performance benefits for CPU-bound workloads through parallelism.

#### Scenario: Parallel speedup for CPU-bound tasks
- **WHEN** multiple CPU-bound tasks are spawned in parallel
- **THEN** the total execution time SHALL be approximately equal to the longest single task
- **AND** speedup SHALL scale near-linearly with available CPU cores (up to core count)

#### Scenario: Minimal single-threaded overhead
- **WHEN** code does not use threading features
- **THEN** performance SHALL be within 5% of pre-threading implementation
- **AND** channel polling SHALL have negligible impact

#### Scenario: Message passing latency
- **WHEN** messages are sent between threads
- **THEN** latency SHALL be in the range of 1-10 microseconds
- **AND** throughput SHALL support thousands of messages per second

### Requirement: Resource Limits
The thread pool SHALL have fixed resource limits for predictable behavior.

#### Scenario: Maximum 64 threads
- **WHEN** threads are spawned
- **THEN** at most 64 threads SHALL be allowed concurrently
- **AND** attempting to spawn more SHALL raise an error

#### Scenario: Channel message limit
- **WHEN** messages are sent to a thread
- **THEN** the channel SHALL have a maximum capacity (e.g., 1000 messages)
- **AND** attempting to send beyond capacity SHALL block or error

### Requirement: Thread Safety Guarantees
The system SHALL guarantee no data races or undefined behavior in multi-threaded execution.

#### Scenario: No shared mutable state
- **WHEN** multiple threads execute concurrently
- **THEN** they SHALL NOT share any mutable state
- **AND** all communication SHALL be via message passing

#### Scenario: Safe symbol table access
- **WHEN** threads access the symbol table
- **THEN** the symbol table SHALL be read-only
- **AND** concurrent access SHALL be safe

#### Scenario: Safe class access
- **WHEN** threads access built-in classes
- **THEN** class objects SHALL be read-only
- **AND** method lookup SHALL be thread-safe

### Requirement: Integration with Async
Threading SHALL work alongside async/await for mixed concurrency patterns.

#### Scenario: Spawn from async context
- **WHEN** spawn is called from within an async block
- **THEN** the thread SHALL be created successfully
- **AND** async execution SHALL continue independently

#### Scenario: Await thread result in async
- **WHEN** a Future from spawn_return is awaited in an async block
- **THEN** the await SHALL suspend until the thread completes
- **AND** both async and thread mechanisms SHALL cooperate

#### Scenario: Mix async and thread concurrency
- **WHEN** code uses both async I/O and thread parallelism
- **THEN** async operations SHALL run concurrently on single thread
- **AND** threads SHALL run in parallel on multiple cores
- **AND** both mechanisms SHALL coexist without interference
