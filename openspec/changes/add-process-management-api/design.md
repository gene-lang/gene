## Context

Gene already exposes `system/exec` and `system/shell`, but both are one-shot helpers that return only after the child process exits. The existing `system/Process` class is a stub. This change fills out that class with a runtime-backed child-process handle suitable for interactive CLI control.

## Goals

- Provide a Gene-native API for spawning child processes with piped stdio
- Support interactive request/response flows by reading and writing process streams incrementally
- Provide explicit process lifecycle control through signals, wait, and shutdown
- Keep the public API compatible with the reviewed design in `docs/proc_management.md`

## Non-Goals

- PTY or terminal emulation
- Process groups or job control
- Async-aware process I/O integration with the VM poll loop
- Windows support in v1

## Design Decisions

### API Shape

- The API extends `system/Process` instead of creating a new namespace.
- `start` is a static method exposed as `system/Process/start`.
- Blocking methods require `^timeout` and return `nil` on timeout.
- `pid` and `exit_code` are exposed as slash-access instance properties.

### Runtime Model

- `src/gene/stdlib/system.nim` maintains a native process wrapper table keyed by hidden instance state.
- Each wrapper stores the Nim `Process` handle plus any buffered output needed to implement line- and delimiter-based reads correctly.
- The wrapper tracks whether stderr has been merged into stdout so invalid API combinations can fail cleanly.

### Blocking Semantics

- All blocking operations use deadline-based polling rather than unbounded blocking.
- In v1 these operations still block the current VM execution path, which means unrelated futures or thread replies do not progress while blocked.
- Requiring explicit timeouts avoids changing the public contract when async-aware integration is added later.

### Shutdown Contract

- `.shutdown ^timeout N` performs a staged teardown:
  1. Close stdin
  2. Wait for half of the timeout budget
  3. If still alive, send `TERM`
  4. Wait for the remaining half of the timeout budget
  5. If still alive, send `KILL`
  6. Wait up to one additional second for final reap
- The method returns the final exit code if observed, otherwise `nil`.

### Error Model

- Invalid handles, wrong argument types, and unsupported combinations raise Gene exceptions.
- Timeouts are normal control flow for process reads and waits, so they return `nil` rather than raising.
- If stderr has been merged into stdout, `.read_stderr` raises instead of silently returning misleading data.
