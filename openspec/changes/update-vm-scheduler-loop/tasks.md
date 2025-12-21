# Implementation Tasks: VM Scheduler Loop (Inline Execution)

## Phase 1: Nested Execution Correctness ✓

- [x] 1.1 Added `exec_method` for proper method self binding
- [x] 1.2 Audited `IkReturn` - correctly captures `from_exec_function` before frame update
- [x] 1.3 Audited `IkEnd` - correctly checks `from_exec_function` flag
- [x] 1.4 Verified via existing tests (test_native.nim test_reentry)

## Phase 2: Inline Callback Execution ✓

- [x] 2.1 `poll_event_loop` executes callbacks inline via `execute_future_callbacks`
- [x] 2.2 Inline callback execution restores VM state correctly
- [x] 2.3 `IkAwait` relies on polling + inline callbacks
- [x] 2.4 Verified via test_async.nim tests

## Phase 3: Scheduler Mode ✓

- [x] 3.1 Added `scheduler_running: bool` flag to VirtualMachine
- [x] 3.2 Implemented scheduler loop in `run_forever` with stop condition
- [x] 3.3 Added idle backoff (1-50ms dynamic poll timeout based on pending work)
- [x] 3.4 Added `stop_scheduler()` API
- [x] 3.5 Removed duplicate `vm_run_forever` from genex/http

## Phase 4: HTTP Integration (Deferred)

The HTTP-specific property access issue (`m/action` returns empty) is a separate bug
unrelated to the scheduler loop refactoring. It will be addressed separately.

- [x] 4.1 `handle_request` uses `exec_method` for Gene handlers
- [x] 4.2 Consolidated to single scheduler in stdlib
- [ ] 4.3 Test HTTP with inline handler execution (blocked by separate bug)
- [ ] 4.4 Verify no more VkInstance-as-exception errors (blocked)

## Phase 5: Tests & Docs

- [x] 5.1 Verified nested VM execution via test_native.nim
- [x] 5.2 Verified async/callback execution via test_async.nim
- [ ] 5.3 Add tests for scheduler mode start/stop
- [ ] 5.4 Update docs/IMPLEMENTATION_STATUS.md
- [ ] 5.5 Update docs/http_server_and_client.md
