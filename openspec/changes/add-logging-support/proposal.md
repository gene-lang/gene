# Proposal: Add Logging Support

## Why

The runtime lacks a unified logging system across Gene and Nim, making diagnostics inconsistent and difficult to configure. We need a logging subsystem with hierarchical logger names, file-based configuration, and consistent output formatting for both Gene and Nim callers.

## What Changes

- Introduce a logging subsystem shared by Gene and Nim code with standard levels (ERROR, WARN, INFO, DEBUG, TRACE).
- Load logging configuration from `config/logging.gene` (project root / current working directory).
- Provide hierarchical logger names derived from `dir/file/ns/class` with inheritance of level settings.
- Add `genex/logging` Gene APIs and Nim-facing helpers that route through the same backend.
- Emit console-only logs with fixed format: `T00 LEVEL yy-mm-dd Wed HH:mm:ss.xxx dir/file/ns/class message`.

## Impact

- Affected specs: logging (new)
- Affected code: new logging module, stdlib bindings, CLI startup/config loading, tests
