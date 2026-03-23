# Proposal: Add Process Management API

## Why

Gene currently supports one-shot process execution through `system/exec` and `system/shell`, but it cannot manage an interactive child process with piped stdin/stdout/stderr. GeneClaw CLI orchestration and process-driven tests need a first-class runtime API for spawning and controlling child processes.

## What Changes

- **ADDED**: `system/Process/start` static method for spawning child processes with piped stdio
- **ADDED**: `Process` instance methods for writing to stdin, reading stdout/stderr, sending signals, waiting, and shutdown
- **ADDED**: `Process` instance properties for `pid` and `exit_code`
- **ADDED**: Timeout-based contract for all blocking process operations
- **ADDED**: Optional stderr-to-stdout merging for interactive use cases
- **ADDED**: Nim tests covering process lifecycle, timeout behavior, merged stderr, and delimiter consumption
- **MODIFIED**: `src/gene/stdlib/system.nim` to fill out the existing `system/Process` stub

## Impact

- **Affected specs**: New capability - `process-management`
- **Affected code**:
  - Modified: `src/gene/stdlib/system.nim`
  - New or modified: process management tests under `tests/`
  - Referenced design doc: `docs/proposals/implemented/proc_management.md`

## Compatibility Notes

- v1 is Unix/macOS only; Windows support remains out of scope.
- Blocking process I/O will block the current VM execution path in v1, so the API requires explicit timeouts instead of promising async-aware progress.
- No process-group management is introduced in v1; shutdown semantics operate on the spawned process handle only.
