# Implementation Tasks: Logging Support

## 1. Core Logging Backend
- [x] 1.1 Add logging module with log levels, logger registry, and console sink.
- [x] 1.2 Implement hierarchical level resolution with longest-prefix matching.
- [x] 1.3 Implement fixed-format formatter with thread id and logger name.

## 2. Configuration
- [x] 2.1 Load `config/logging.gene` at startup when present.
- [x] 2.2 Parse Gene config into root level + per-logger settings.

## 3. APIs
- [x] 3.1 Expose Nim helper API for logging from VM/stdlib/extension code.
- [x] 3.2 Expose `genex/logging` with a `Logger` class and level methods.

## 4. Tests & Validation
- [x] 4.1 Add Nim tests for config parsing and level inheritance.
- [x] 4.2 Add Gene tests for log output formatting and level filtering.
- [x] 4.3 Run `nimble test` and `./testsuite/run_tests.sh`.
