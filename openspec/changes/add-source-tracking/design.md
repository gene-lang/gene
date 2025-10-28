## Overview
We restore location tracking by introducing a source map that follows a compilation unit from parsing through execution. The parser records source positions in a table, the compiler threads location IDs into emitted instructions, and the VM consults the table when raising diagnostics.

## Parser Source Tree
- Extend `Parser` with a `SourceTrace` stack that mirrors the AST hierarchy. Every time the parser creates a `Gene`, push a trace node that records the filename, start line, and column, and link it to its parent.
- Update `add_line_col` so each `Gene` stores a pointer to its corresponding `SourceTrace` node instead of duplicating position data.
- Provide traversal helpers (`enter_child`, `leave_child`, `current_trace`) so downstream passes can move up and down the tree while processing children.

## Compiler & GIR Integration
- Propagate the `SourceTrace` pointer (or an equivalent safe handle) through compiler pipelines, using the traversal helpers to stay synchronized with the AST depth.
- Attach instruction metadata by capturing the current trace node when emitting bytecode; store a parallel array keyed by program counter that references the corresponding trace.
- Persist the source trace hierarchy inside the GIR header section. Encode the tree as a pre-order sequence with parent indices (or similar) plus a compact file table.
- Make debug data optional: default to enabled, but allow stripping via existing `--no-debug`-style flags to avoid bloating artefacts when unnecessary.

## VM Error Reporting
- Load the source trace hierarchy when constructing a `CompilationUnit` from GIR.
- On runtime exceptions, use the instruction pointer to look up the stored trace node, rehydrate filename and line, and append that information to the error report.
- If metadata is missing (old bytecode), fall back to current behaviour without crashing.

## Open Questions
- Confirm whether macros or dynamically generated code require special handling to avoid stale trace stacks.
- Determine how to surface multiple frames (e.g., stack traces) once instruction → source mapping exists.
