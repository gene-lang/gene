# Proposal: Update VM Scheduler Loop

## Why

Gene currently has multiple event-loop drivers and inconsistent execution paths between VM code, native functions, and async callbacks:
- `gene/run_forever` (stdlib) spins its own loop and directly calls HTTP processing.
- `genex/http` also defines `gene/run_forever` with another loop.
- HTTP handlers are executed inside native async loops via `exec_function`, not via the VM main loop.
- `poll_event_loop` only checks futures, and `EventLoopCallbacks` are unused.
- Native callbacks can re-enter the VM to call Gene methods (e.g., `.to_s`) without a unified scheduling rule.

This creates nested loops, duplicated logic, and potential for:
- **Execution bugs**: Return values treated as exceptions (VkInstance bug)
- **Deadlocks**: Nested loop waiting for something only main loop can provide
- **Reentrancy issues**: Unbounded recursion from callback chains

## What Changes

Key changes:
- Any entry into Gene code (native call or future callback) starts a nested VM loop immediately.
- `poll_event_loop` executes callbacks inline via `exec_callable` rather than queueing.
- VM state (frame/pc/cu) is saved and restored around every nested execution.
- Await continues to poll; callbacks run inline when ready.

### Execution Model

1. **Nested VM Loop (Synchronous)** - For any native-to-Gene call that needs a result
   - `exec_callable(fn, args)` saves state, runs nested VM loop, returns result
   - Used for `.to_s`, method calls, native functions calling Gene
2. **Inline Callback Execution** - For future callbacks and async completions
   - `poll_event_loop` runs ready callbacks immediately via `exec_callable`
   - Callback execution is nested and restores VM state on return

### Scheduler Mode

- `run_forever` remains the entrypoint to keep the VM alive and polling async
- VM keeps running: poll async -> execute callbacks inline -> execute Gene code -> repeat
- Single unified `run_forever` in stdlib; remove per-extension loops

## Impact

- Affected code: `src/gene/vm.nim`, `src/gene/types/*`, `src/gene/stdlib.nim`, `src/genex/http.nim`
- Tests: nested execution, callback execution, HTTP integration
- Behavior: All Gene execution is re-entrant with state save/restore; callbacks run inline
