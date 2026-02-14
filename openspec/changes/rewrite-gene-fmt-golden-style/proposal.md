## Why

The current formatter output diverges from the style used in `examples/full.gene` and can degrade readability. We need a formatter that treats `examples/full.gene` as the canonical style reference and preserves human-authored structure.

## What Changes

- Rebuild `gene fmt` around a text/token-level formatter that preserves comments, shebang, and top-level section spacing.
- Align formatting behavior with `examples/full.gene` conventions for indentation, short-vs-multiline layout, and inline properties.
- Support `gene fmt file.gene` (in-place) and `gene fmt --check file.gene` (non-destructive validation, non-zero on mismatch).
- Add formatter tests including a golden check for `examples/full.gene`.

## Impact

- Affected specs: `source-formatter`
- Affected code:
  - `src/gene/formatter.nim`
  - `src/commands/fmt.nim`
  - `src/gene.nim`
  - `src/commands/help.nim`
  - `testsuite/fmt/*`
  - `testsuite/run_tests.sh`
