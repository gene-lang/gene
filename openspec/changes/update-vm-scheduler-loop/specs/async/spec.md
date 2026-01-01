## ADDED Requirements

### Requirement: Scheduler Mode
The VM SHALL provide a scheduler mode that keeps the main loop running to poll async events and execute callbacks inline when `run_forever` is called.

#### Scenario: Scheduler keeps running
- **WHEN** `run_forever` is invoked and no callbacks are immediately pending
- **THEN** the VM continues to poll and remain active until work arrives or the scheduler is stopped

### Requirement: Polling Executes Callbacks Inline
`poll_event_loop` SHALL execute ready callbacks inline via nested VM execution; it SHALL NOT enqueue handlers for later execution.

#### Scenario: Polling runs callback immediately
- **WHEN** a future becomes ready during `poll_event_loop`
- **THEN** its callback executes inline via `exec_callable`

### Requirement: Nested VM Execution and State Restore
Inline Gene execution (native or callback) SHALL run in a nested VM loop that saves and restores VM state (frame/pc/cu) after completion.

#### Scenario: VM state restored after nested call
- **WHEN** a native method calls a Gene function inline
- **THEN** the VM restores the caller frame/pc after the Gene call completes

#### Scenario: Nested loop polls futures
- **WHEN** the nested call creates a future that becomes ready during execution
- **THEN** polling occurs within the nested loop so callbacks can run inline

### Requirement: Native and Callback Entry Points
Native calls and async callbacks SHALL invoke Gene callables inline using nested execution and return the result directly.

#### Scenario: Native call returns result
- **WHEN** a native method invokes a Gene method (e.g., `.to_s`)
- **THEN** the result is returned to the native caller after nested execution completes

#### Scenario: Async callback returns result
- **WHEN** an async callback invokes a Gene callable
- **THEN** the callback receives the Gene result after nested execution completes

### Requirement: Await Polling
`IkAwait` SHALL poll async events until the awaited future is completed, relying on inline callback execution to resolve the future.

#### Scenario: Await completes after callback
- **WHEN** `await` blocks on a future whose completion requires a callback
- **THEN** polling runs the callback inline and `await` returns the resolved value

### Requirement: HTTP Handler Execution
HTTP request handling SHALL invoke the Gene handler inline and send the response after the handler returns.

#### Scenario: Request handled inline
- **WHEN** an HTTP request arrives for a Gene handler
- **THEN** the handler executes inline and the response is sent on return

### Requirement: Unified run_forever
Only the stdlib `run_forever` entrypoint SHALL run the scheduler loop; extensions SHALL delegate or remove duplicate loops.

#### Scenario: Extension delegates to stdlib
- **WHEN** an extension needs a run-forever loop
- **THEN** it uses the stdlib `run_forever` scheduler instead of starting its own loop

### Requirement: Idle Backoff
When scheduler mode has no pending work, the VM SHALL yield or sleep to avoid busy waiting.

#### Scenario: Idle scheduler yields
- **WHEN** the scheduler loop is idle
- **THEN** it yields or sleeps briefly to prevent high CPU usage
