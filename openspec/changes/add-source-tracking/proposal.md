## Why
- Parser currently drops location metadata, so syntax, compile, and runtime errors lack precise source reporting.
- Request asks for a parallel tracking structure that survives parsing, can fail gracefully during compilation, and is available in generated IR so execution can report locations.

## What Changes
- Add a parser-managed source tree that mirrors the AST shape and records filename, line, and column for each node as the parser descends and ascends.
- Give the compiler and GIR serializer access to that hierarchical structure so they can track the current location while walking the tree and annotate emitted instructions on the fly.
- Ensure the VM loads location metadata from GIR and includes it in diagnostic output when runtime errors fire.

## Impact
- Touches parser, compiler, GIR encoding/decoding, and VM error reporting.
- Increases memory footprint modestly due to the source trace tree, but keeps debug data optional where feasible.
- Improves developer ergonomics by standardising location reporting across the toolchain.
