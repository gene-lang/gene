## Why

Tooling and AI agents need a stable, machine-readable view of module structure and type metadata. Current CLI output is human-oriented (instruction listings) and requires ad-hoc parsing.

## What Changes

- Add a structured metadata output mode to `gene compile`.
- Expose module/type/function metadata in JSON for tooling/AI use.
- Keep descriptor IDs and signature details in the exported payload.
- Add tests that verify metadata output for typed and untyped declarations.

## Impact

- Affected specs: `ai-tooling-metadata-surface`
- Affected code:
  - `src/commands/compile.nim`
  - `tests/test_cli_compile.nim` (new)
  - `docs/README.md`
