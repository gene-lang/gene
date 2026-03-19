# Process Management Specification

## ADDED Requirements

### Requirement: Spawn Child Processes With Piped Stdio

The system SHALL expose a `system/Process/start` API that spawns a child process with piped stdin/stdout/stderr and returns a `Process` instance.

#### Scenario: Start a process with command arguments

- **GIVEN** the `system/Process` class is available
- **WHEN** `(system/Process/start "echo" "hello")` is called
- **THEN** a `Process` instance is returned
- **AND** the instance exposes the spawned process id through `proc/pid`

#### Scenario: Start a process with execution options

- **GIVEN** the `system/Process` class is available
- **WHEN** `(system/Process/start "gene" "run" "src/main.gene" ^cwd "/tmp" ^env {^KEY "value"})` is called
- **THEN** the child process uses the provided working directory and environment overrides

#### Scenario: Start a process with merged stderr

- **GIVEN** the `system/Process` class is available
- **WHEN** `(system/Process/start "sh" "-c" "echo err >&2; echo out" ^stderr_to_stdout true)` is called
- **THEN** stderr is redirected into stdout for that process handle

### Requirement: Write To Child Stdin

The system SHALL allow callers to write to a child process stdin stream until stdin is explicitly closed.

#### Scenario: Write raw text to stdin

- **GIVEN** a running child process with open stdin
- **WHEN** `(proc .write "hello\n")` is called
- **THEN** the bytes are written to the child stdin stream

#### Scenario: Write a line to stdin

- **GIVEN** a running child process with open stdin
- **WHEN** `(proc .write_line "hello")` is called
- **THEN** the child receives `hello` followed by a newline

#### Scenario: Close stdin without killing the child

- **GIVEN** a running child process
- **WHEN** `(proc .close_stdin)` is called
- **THEN** the child stdin stream is closed
- **AND** the child process remains running until it exits or is signaled

### Requirement: Read Child Output With Timeouts

The system SHALL provide timeout-based methods for reading a child process output incrementally.

#### Scenario: Read one stdout line

- **GIVEN** a child process that writes a newline-terminated stdout line
- **WHEN** `(proc .read_line ^timeout 5)` is called
- **THEN** the line content is returned without the trailing newline

#### Scenario: Read until delimiter and consume it

- **GIVEN** a child process that writes `helloXworldX`
- **WHEN** `(proc .read_until "X" ^timeout 5)` is called twice
- **THEN** the first call returns `helloX`
- **AND** the second call returns `worldX`

#### Scenario: Read available stdout without blocking

- **GIVEN** a running child process
- **WHEN** `(proc .read_available)` is called and no stdout bytes are ready
- **THEN** an empty string is returned immediately

#### Scenario: Blocking read times out

- **GIVEN** a running child process that does not produce the requested output before the deadline
- **WHEN** a blocking read method is called with `^timeout`
- **THEN** `nil` is returned

### Requirement: Read Stderr Separately Only When Unmerged

The system SHALL allow stderr reads only when stderr has not been redirected into stdout.

#### Scenario: Read stderr when unmerged

- **GIVEN** a process started without `^stderr_to_stdout true`
- **WHEN** `(proc .read_stderr ^timeout 5)` is called
- **THEN** available stderr output is returned

#### Scenario: Reject stderr reads after merge

- **GIVEN** a process started with `^stderr_to_stdout true`
- **WHEN** `(proc .read_stderr ^timeout 5)` is called
- **THEN** an exception is raised indicating stderr is merged into stdout

### Requirement: Expose Process Lifecycle Control

The system SHALL provide methods and properties to inspect and control child process lifecycle.

#### Scenario: Check liveness

- **GIVEN** a running child process
- **WHEN** `(proc .alive?)` is called
- **THEN** `true` is returned

#### Scenario: Wait for process exit

- **GIVEN** a child process that exits within the deadline
- **WHEN** `(proc .wait ^timeout 5)` is called
- **THEN** the exit code is returned
- **AND** `proc/exit_code` is updated

#### Scenario: Wait times out

- **GIVEN** a child process that remains running past the deadline
- **WHEN** `(proc .wait ^timeout 1)` is called
- **THEN** `nil` is returned
- **AND** the process remains running

#### Scenario: Send a Unix signal

- **GIVEN** a running child process on a supported Unix-like platform
- **WHEN** `(proc .signal "TERM")` is called
- **THEN** the process receives `SIGTERM`

### Requirement: Provide Explicit Shutdown Semantics

The system SHALL provide a staged `.shutdown` operation for explicit process cleanup without relying on implicit finalizers.

#### Scenario: Shutdown succeeds after stdin close

- **GIVEN** a child process that exits after receiving EOF
- **WHEN** `(proc .shutdown ^timeout 5)` is called
- **THEN** stdin is closed
- **AND** the child exits without requiring signals
- **AND** the final exit code is returned

#### Scenario: Shutdown escalates to TERM

- **GIVEN** a child process that ignores EOF but exits after `SIGTERM`
- **WHEN** `(proc .shutdown ^timeout 4)` is called
- **THEN** the runtime closes stdin
- **AND** waits for half of the timeout budget
- **AND** sends `SIGTERM`
- **AND** returns the exit code if the process exits during the remaining budget

#### Scenario: Shutdown escalates to KILL

- **GIVEN** a child process that ignores EOF and `SIGTERM`
- **WHEN** `(proc .shutdown ^timeout 4)` is called
- **THEN** the runtime escalates to `SIGKILL`
- **AND** waits up to one additional second for the process to reap
- **AND** returns the exit code if observed, otherwise `nil`

### Requirement: Require Explicit Caller Cleanup

The system SHALL not promise implicit process cleanup when a `Process` instance is garbage-collected.

#### Scenario: Caller is responsible for cleanup

- **GIVEN** a live `Process` instance
- **WHEN** the caller is done using it
- **THEN** the documented cleanup path is `.shutdown` or `.signal` plus `.wait`
- **AND** the runtime does not guarantee automatic child termination during garbage collection
