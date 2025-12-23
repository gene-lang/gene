## Context

Gene currently relies on Nim's default logging for CLI messages only. There is no unified logging facility for Gene code, extensions, or VM components. The requirement is a minimal, console-only logger with hierarchical naming and configuration from a Gene file.

## Goals / Non-Goals

Goals:
- Provide a shared logging backend for both Gene and Nim callers.
- Configure logging via `config/logging.gene`.
- Support hierarchical logger names (dir/file/namespace/class) with level inheritance.
- Fixed log output format for console logging.

Non-Goals:
- File appenders, rolling, or JSON output.
- Dynamic reloading or runtime config mutation.
- Complex layouts or filters beyond level thresholding.

## Decisions

### Logger Naming
- The logger name is a string: `dir/file/ns/class`.
- `dir/file` is derived from the module path relative to the working directory. If not available, use `unknown`.
- `ns` is the current namespace (if known), and `class` is the current class name (if within a class method). Missing segments are omitted.
- Logger construction is based on a class or namespace reference, never an instance.
- Examples:
  - Module-level code in `examples/app.gene` → `examples/app.gene`
  - Method in class `Todo` under namespace `Http` → `examples/app.gene/Http/Todo`

### Hierarchical Resolution
- Configuration uses longest-prefix matching similar to log4j:
  - `examples` applies to everything under that directory.
  - `examples/app.gene` applies to the file.
  - `examples/app.gene/Http` applies to that namespace.
  - `examples/app.gene/Http/Todo` applies to that class.
- The effective log level is the most specific match; otherwise fallback to root level.

### Config File Format (Gene)
- File location: `config/logging.gene` (root = current working directory).
- Example structure:
  ```gene
  {^level "INFO"
   ^loggers {
     ^"examples" {^level "WARN"}
     ^"examples/app.gene" {^level "DEBUG"}
     ^"examples/app.gene/Http" {^level "TRACE"}
     ^"examples/app.gene/Http/Todo" {^level "ERROR"}
   }}
  ```
- Only `level` and `loggers` are required for v1.

### Logging API
- Nim API: `log_message(level, name, message)` with shared backend and config.
- Gene API: `genex/logging/Logger` class with `.info`, `.warn`, `.error`, `.debug`, `.trace` methods.
  - `Logger` constructor accepts a class or namespace reference; constructing from instances is disallowed.
  - Typical usage: define `/logger = (new Logger self)` inside a class body and call `(logger .info "...")`.
- Both APIs share the same level filtering and output formatting.

### Output Format
- Console only, fixed format:
  `T00 LEVEL yy-mm-dd Wed HH:mm:ss.xxx dir/file/ns/class message`

## Risks / Trade-offs

- Resolving module/class/namespace names in the VM may require extra metadata; keep it minimal to avoid hot-path overhead.
- Longest-prefix matching is fast enough with a small number of configured loggers; a prefix tree can be added later if needed.

## Migration Plan

1. Add logging config loader and runtime logger registry.
2. Add Gene-level logging functions and Nim-level helpers.
3. Wire CLI startup to load `config/logging.gene` if present.
4. Add tests for config parsing, level resolution, and output format.
