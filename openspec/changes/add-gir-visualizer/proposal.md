## Why

The CLI currently compiles Gene sources to GIR files but offers no way to inspect their contents. Developers working on the VM and compiler need human-readable diagnostics to debug compiled output, especially after the Nim 2.2.4 upgrade.

## What Changes
- Add a dedicated `gene gir show` command (with alias `visualize`) that loads an existing `.gir` file and renders a readable listing of header metadata, constants, and instructions.
- Reuse the existing GIR loader to ensure the visualization matches the runtime representation.
- Provide output formatting consistent with the existing `gene compile -f pretty` listing where possible.

## Impact
- Enables debugging of cached GIR artefacts without recompiling source files.
- No behaviour changes to existing commands.
- Minimal code changes scoped to a new command and shared formatting helpers.
