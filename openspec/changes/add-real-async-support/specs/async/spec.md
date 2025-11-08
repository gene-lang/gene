# Async Capability Specification

## ADDED Requirements

### Requirement: Event Loop Execution
The VM SHALL integrate Nim's asyncdispatch event loop to enable non-blocking I/O operations and true concurrent execution.

#### Scenario: Event loop polls during VM execution
- **WHEN** the VM main loop executes instructions
- **THEN** the asyncdispatch event loop SHALL be polled periodically (every 100 instructions)
- **AND** the poll SHALL be non-blocking (timeout = 0)
- **AND** VM execution SHALL not be blocked by the event loop

#### Scenario: Event loop processes pending I/O
- **WHEN** an async I/O operation completes
- **THEN** the event loop SHALL invoke registered callbacks
- **AND** suspended continuations SHALL be resumed
- **AND** execution SHALL continue from the suspension point

### Requirement: Real Future Suspension
Futures SHALL support pending state where operations have not yet completed, enabling true asynchronous execution.

#### Scenario: Future enters pending state on async I/O
- **WHEN** an async I/O function is called (e.g., file_read_async)
- **THEN** a Future SHALL be returned in FsPending state
- **AND** the I/O operation SHALL execute asynchronously without blocking the VM
- **AND** the Future SHALL transition to FsSuccess or FsFailure when I/O completes

#### Scenario: Await suspends on pending future
- **WHEN** `await` is called on a Future in FsPending state
- **THEN** the current frame SHALL suspend execution
- **AND** control SHALL return to the event loop
- **AND** other code SHALL be able to execute while waiting

#### Scenario: Await returns immediately on completed future
- **WHEN** `await` is called on a Future in FsSuccess or FsFailure state
- **THEN** the result value SHALL be returned immediately without suspension
- **AND** no event loop interaction SHALL occur

### Requirement: Concurrent Execution
Multiple async operations SHALL execute concurrently, allowing overlapping I/O operations to improve performance.

#### Scenario: Multiple file reads execute concurrently
- **WHEN** three file read operations are initiated with `file_read_async`
- **THEN** all three reads SHALL start without waiting for each other
- **AND** the total execution time SHALL be approximately equal to the slowest single read
- **AND** all reads SHALL complete with correct results

#### Scenario: Async and sync code interleave
- **WHEN** async operations are pending
- **THEN** non-async code SHALL continue to execute
- **AND** the VM SHALL remain responsive to both async and sync operations

### Requirement: Continuation Preservation
The VM SHALL preserve execution state across suspension points, enabling resumption with correct context.

#### Scenario: Local variables preserved across await
- **WHEN** a function has local variables before an await
- **THEN** those variables SHALL retain their values after the await completes
- **AND** the function SHALL continue execution with the correct variable state

#### Scenario: Scope captured by async block
- **WHEN** an async block references function parameters or local variables
- **THEN** the scope containing those variables SHALL remain valid until the async block completes
- **AND** no use-after-free errors SHALL occur

#### Scenario: Multiple suspension points in one function
- **WHEN** a function has multiple await expressions
- **THEN** the function SHALL suspend at each await
- **AND** resume from the correct position after each suspension
- **AND** control flow SHALL proceed correctly through all suspension points

### Requirement: CPS Transformation
The compiler SHALL transform async functions into continuation-passing style to enable suspension and resumption.

#### Scenario: Async function compiled to state machine
- **WHEN** a function contains one or more await expressions
- **THEN** the compiler SHALL generate a state machine with states for each await
- **AND** each state SHALL represent code from one await to the next
- **AND** the state machine SHALL correctly transfer control between states

#### Scenario: Continuation captures minimal state
- **WHEN** a continuation is created at a suspension point
- **THEN** it SHALL capture only the necessary frame state (PC, stack depth, scope, live locals)
- **AND** it SHALL NOT copy the entire 256-slot frame stack
- **AND** memory usage SHALL be proportional to the number of live variables

### Requirement: Non-Blocking I/O
I/O operations SHALL use Nim's async primitives to avoid blocking the VM thread.

#### Scenario: File read uses asyncfile
- **WHEN** `file_read_async` is called
- **THEN** it SHALL use Nim's `asyncfile.readFile()` internally
- **AND** the VM thread SHALL not block waiting for I/O
- **AND** a pending Future SHALL be returned immediately

#### Scenario: Network request uses async HTTP client
- **WHEN** an HTTP request is initiated with `http_get_async`
- **THEN** it SHALL use Nim's AsyncHttpClient
- **AND** the request SHALL not block the VM
- **AND** other operations SHALL execute while the request is pending

#### Scenario: Async sleep does not block
- **WHEN** `sleep_async` is called with a duration
- **THEN** it SHALL use `asyncdispatch.sleepAsync()`
- **AND** other async operations SHALL execute during the sleep
- **AND** the sleep SHALL complete after the specified duration

### Requirement: Callback Execution
Futures SHALL support callback registration and execution for success and failure cases.

#### Scenario: Success callback executed on completion
- **WHEN** a callback is registered with `future.on_success(callback)`
- **THEN** the callback SHALL be invoked when the future completes successfully
- **AND** the callback SHALL receive the result value as an argument

#### Scenario: Failure callback executed on error
- **WHEN** a callback is registered with `future.on_failure(callback)`
- **THEN** the callback SHALL be invoked if the future fails with an exception
- **AND** the callback SHALL receive the exception as an argument

#### Scenario: Multiple callbacks on one future
- **WHEN** multiple callbacks are registered on the same future
- **THEN** all callbacks SHALL be executed in registration order
- **AND** each callback SHALL receive the same result value

#### Scenario: Callbacks invoked by event loop
- **WHEN** a future completes during event loop polling
- **THEN** the event loop SHALL invoke all registered callbacks
- **AND** callbacks SHALL execute within the VM context

### Requirement: Exception Handling in Async Context
Exceptions SHALL propagate correctly through async boundaries and suspension points.

#### Scenario: Exception in async block caught by try/catch
- **WHEN** an exception is thrown within an async block
- **THEN** it SHALL be caught by the nearest enclosing try/catch
- **AND** the exception handler SHALL execute correctly
- **AND** the future SHALL transition to FsFailure state with the exception

#### Scenario: Exception propagates through await
- **WHEN** an awaited future completes with FsFailure
- **THEN** the exception SHALL be re-thrown at the await point
- **AND** it SHALL be catchable by surrounding exception handlers

#### Scenario: Unhandled async exception
- **WHEN** an exception occurs in an async block with no handler
- **THEN** it SHALL propagate to the top-level exception handler
- **AND** the program SHALL terminate or invoke the global exception handler

### Requirement: Scope Lifetime Management
Scopes SHALL remain valid for the lifetime of any pending futures that reference them.

#### Scenario: Scope preserved until future completes
- **WHEN** a future captures a scope reference
- **THEN** the scope SHALL increment its reference count
- **AND** the scope SHALL not be freed until the future completes
- **AND** the scope SHALL only be freed when ref_count reaches 0

#### Scenario: Function returns async block referencing parameters
- **WHEN** a function returns an async block that references its parameters
- **THEN** the scope containing those parameters SHALL remain valid
- **AND** the async block SHALL have correct access to parameter values
- **AND** no memory corruption SHALL occur

#### Scenario: Nested async blocks with scope capture
- **WHEN** nested async blocks reference outer scopes
- **THEN** all referenced scopes SHALL remain valid until the innermost async completes
- **AND** scope cleanup SHALL occur in correct order (inner to outer)

### Requirement: Performance Characteristics
Async operations SHALL provide performance benefits for I/O-bound workloads through concurrency.

#### Scenario: Concurrent I/O faster than sequential
- **WHEN** multiple I/O operations are initiated concurrently
- **THEN** the total time SHALL be approximately equal to the slowest operation
- **AND** it SHALL be significantly less than the sum of all operation times
- **AND** performance gain SHALL scale with the number of concurrent operations

#### Scenario: Non-async code has minimal overhead
- **WHEN** code does not use async features
- **THEN** performance SHALL degrade by less than 5% compared to pre-async VM
- **AND** event loop polling SHALL have negligible impact on sync-only workloads

#### Scenario: Memory usage scales with pending futures
- **WHEN** N futures are pending simultaneously
- **THEN** memory usage SHALL be O(N) in continuation overhead
- **AND** each continuation SHALL use memory proportional to captured state
- **AND** completed futures SHALL release continuation memory

### Requirement: Backward Compatibility
Existing async syntax SHALL continue to work with enhanced semantics for true asynchronous execution.

#### Scenario: Existing async/await syntax unchanged
- **WHEN** code uses `(async expr)` and `(await future)` syntax
- **THEN** the syntax SHALL remain valid and compile correctly
- **AND** the behavior SHALL change from pseudo-async to real async
- **AND** no syntax changes SHALL be required for migration

#### Scenario: Synchronous I/O functions still available
- **WHEN** synchronous I/O functions are called (e.g., `file_read`)
- **THEN** they SHALL continue to work with blocking semantics
- **AND** they SHALL be marked as deprecated in favor of async versions
- **AND** mixing sync and async I/O SHALL be supported

### Requirement: Debugging and Observability
The VM SHALL provide visibility into async execution state for debugging and monitoring.

#### Scenario: Pending future count accessible
- **WHEN** async operations are in progress
- **THEN** the number of pending futures SHALL be queryable
- **AND** this information SHALL be available for debugging

#### Scenario: Event loop statistics available
- **WHEN** the event loop is running
- **THEN** statistics (poll count, callback executions) SHALL be tracked
- **AND** this data SHALL be accessible for performance analysis

#### Scenario: Continuation state inspectable
- **WHEN** a frame is suspended with a continuation
- **THEN** the continuation state SHALL be inspectable in debug mode
- **AND** captured variables SHALL be visible for debugging
