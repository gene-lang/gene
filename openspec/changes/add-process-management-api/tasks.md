# Implementation Tasks

## 1. Runtime Foundation
- [x] 1.1 Extend `src/gene/stdlib/system.nim` with process wrapper state
  - [x] Track native process handles behind `Process` instances
  - [x] Track buffered stdout/stderr state needed by `read_line` and `read_until`
  - [x] Track `exit_code`, stderr merge mode, and closed stdin state
- [x] 1.2 Implement helper routines for timeout parsing and process lookup
  - [x] Parse `^timeout` keyword arguments consistently
  - [x] Validate required string/integer arguments
  - [x] Surface closed or invalid process-handle errors cleanly

## 2. Process API Implementation
- [x] 2.1 Implement `system/Process/start`
  - [x] Accept command plus positional args
  - [x] Support `^cwd`, `^env`, and `^stderr_to_stdout`
  - [x] Register `start` as a static method exposed as `system/Process/start`
- [x] 2.2 Implement stdin methods
  - [x] `.write`
  - [x] `.write_line`
  - [x] `.close_stdin`
- [x] 2.3 Implement stdout/stderr read methods
  - [x] `.read_line`
  - [x] `.read_until`
  - [x] `.read_available`
  - [x] `.read_stderr`
- [x] 2.4 Implement process control methods
  - [x] `.alive?`
  - [x] `.signal`
  - [x] `.wait`
  - [x] `.shutdown`
- [x] 2.5 Expose process properties
  - [x] `proc/pid`
  - [x] `proc/exit_code`

## 3. Test Coverage
- [x] 3.1 Add Nim tests for process spawning and stream I/O
  - [x] Basic echo/read/wait behavior
  - [x] Interactive stdin/stdout round-trip
  - [x] Timeout behavior for blocking reads
  - [x] Exit-code propagation
- [x] 3.2 Add lifecycle and buffering tests
  - [x] Graceful shutdown on EOF
  - [x] TERM/KILL shutdown branches without process-group assumptions
  - [x] Merged stderr behavior
  - [x] `read_until` delimiter consumption

## 4. Validation
- [x] 4.1 Run `openspec validate add-process-management-api --strict`
- [x] 4.2 Run targeted Nim tests for the new process API
- [x] 4.3 Run broader regression coverage as needed
