## Context

The VM already polls `asyncdispatch.poll(0)` in `poll_event_loop`, but HTTP requests are handled via a separate async loop that calls `exec_function` directly. This bypasses the VM main loop and creates nested event loops (`run_forever` in stdlib and in genex/http). We need an architecture that supports:

1. **Nested VM execution** - Native code calling Gene code synchronously
2. **Inline callback execution** - Async callbacks invoking Gene code immediately
3. **Both modes working together** with correct state restoration

## Execution Modes

### Mode 1: Nested VM Loop (Synchronous)

When native code needs to execute Gene code and **wait for the result**:

```
Native fn -> exec_callable() -> nested VM loop -> returns result
```

**Use cases:**
- `.to_s`, `.hash`, `.==` called from native code
- Method calls on Gene objects from native functions
- Printing/formatting Gene values
- Any native code that needs a Gene result immediately

**Implementation:**
```nim
proc exec_callable(callable, args): Value =
  save_vm_state()
  setup_new_frame(callable, args, from_exec_function=true)
  
  while true:
    poll(0)           # Poll Nim async
    if execute_batch():  # Execute Gene instructions
      break              # Frame returned
  
  restore_vm_state()
  return result
```

**Key invariant:** Nested execution always completes before returning to caller.

### Mode 2: Inline Callback Execution (Asynchronous)

When async callbacks need to run Gene code:

```
Nim async callback -> exec_callable() -> returns result
```

**Use cases:**
- Future callbacks (`on_success`/`on_failure`)
- HTTP request handlers (Nim async context)
- Timer callbacks from `addTimer`
- File I/O completion callbacks

## Async Callback Handling in Nested Loops

**Question:** If async callbacks are registered during a nested loop, should the nested loop handle them?

**Answer:** YES:
- YES: Poll Nim async dispatcher (shared with main loop)
- YES: Execute callbacks inline via nested execution
- YES: Handle futures created during the nested call

This prevents deadlock where nested code awaits a future that depends on callback execution.

## Deadlock Prevention

### Potential Deadlock Scenario

```
Nested loop running
  -> Gene code awaits future
       -> Future depends on callback execution
           -> If callbacks are not run inline -> DEADLOCK
```

### Solution: Nested loops run callbacks inline

```
Nested loop awaits future
  -> Nested loop runs callback inline
       -> Callback completes the future
            -> Await succeeds -> NO DEADLOCK
```

### Deadlock Analysis Table

| Future depends on... | Nested loop handles? | Result |
|---------------------|---------------------|--------|
| Nim async I/O | YES (poll) | OK |
| Nim timer | YES (poll) | OK |
| Inline callback | YES (exec) | OK |
| Thread reply | YES (poll) | OK |
| THIS nested call | NO (circular) | ERROR |

## Frame Flags and Return Handling

### Frame Flags

```nim
FrameObj = object
  # ... existing fields ...
  from_exec_function: bool  # True if entry point for nested execution
```

### Return Path Logic

```nim
of IkReturn:
  let value = pop()
  
  if frame.from_exec_function:
    # This exact frame was the entry point from exec_callable
    # Exit nested loop, return value to native caller
    restore_saved_state()
    return value
  
  elif frame.caller_frame != nil:
    # Normal return to caller frame
    restore_caller_frame()
    push(value)
    continue
  
  else:
    # Return from top-level (program exit)
    return value
```

**Critical:** Only the frame with `from_exec_function = true` triggers loop exit. Inner frames (method calls within that function) return normally to their callers.

## Scheduler Mode for run_forever

When Gene code calls `run_forever`:

1. VM sets `scheduler_mode = true`
2. VM main loop continues running instead of returning
3. Each iteration:
   - Poll Nim async events
   - Check for stop condition
4. Stop when `scheduler_mode = false` or program exits

```nim
proc run_forever_loop() =
  vm.scheduler_mode = true
  while vm.scheduler_mode:
    poll(1)              # Non-blocking async poll (runs callbacks inline)
    if no_pending_work():
      sleep(1)           # Avoid busy-wait
```

## HTTP Integration

HTTP handlers use Mode 2 (inline execution):

```nim
proc handle_request(req: Request) {.async.} =
  let gene_req = create_server_request(req)
  let response = exec_callable(handler, @[gene_req])
  await send_response(req, response)
```

## Unified Execution Rules

| Context | Method | Blocks? | Polls async? | Executes callbacks? |
|---------|--------|---------|--------------|----------------------|
| Native fn on VM thread | `exec_callable` | Yes | Yes | Inline |
| Nim async callback | `exec_callable` | Yes | Yes | Inline |
| VM instruction | Direct | No | Via poll_event_loop | Inline |

## Goals / Non-Goals

**Goals:**
- Support nested VM execution for synchronous native-to-Gene calls
- Support inline callback execution for async completions
- All loops poll Nim async; callbacks run inline when ready
- Prevent deadlocks via inline callback execution in nested loops
- Single unified `run_forever` with scheduler mode

**Non-Goals:**
- Full CPS transformation or coroutine resumption
- Multi-threaded VM execution
- New public Gene syntax

## Risks / Trade-offs

**Risk:** Deep nesting with callback chains could overflow stack.
- Mitigation: Track exec_depth and add a safety cap with a clear error.

**Risk:** Inline callback execution can block Nim async loop.
- Mitigation: Keep callbacks short; revisit if async throughput becomes an issue.

**Risk:** Frame flag handling regression.
- Mitigation: Extensive tests for all execution paths.

## Migration Plan

1. Update `poll_event_loop` to execute callbacks inline via `exec_callable`
2. Ensure `exec_callable` saves/restores VM state for nested execution
3. Update `IkAwait` to rely on polling + inline callbacks
4. Update HTTP handler to call Gene handler inline
5. Consolidate `run_forever` to single implementation with scheduler mode
6. Update tests and docs

## Open Questions

- Maximum nesting depth before warning/error?
A: deferred
- Do we want a max exec_depth limit or just a warning?
A: deferred
- Should `stop_scheduler` be explicit or automatic on program exit?
A: explicitly set by calling stop_forever() from async callbacks (we may give a unique id to each run_forever call and stop by id)
