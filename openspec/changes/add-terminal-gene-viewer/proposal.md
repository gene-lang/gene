## Why

Large Gene data files and append-only Gene logs are hard to inspect with the current CLI. Existing commands either print the entire structure as text or execute/compile the file, which is not practical for large nested documents where a user needs to browse incrementally.

## What Changes
- Add a new `gene view <file>` command that opens an interactive terminal viewer for Gene data files and multi-form Gene logs.
- Use a full-screen ncurses-backed interface with arrow-key navigation, a header that shows the file path and current logical path, and a footer that shows supported function keys.
- Make the viewer efficient for large inputs by indexing top-level entries incrementally and loading nested content only when the user drills into it.

## Impact
- Affected specs: `terminal-gene-viewer`
- Affected code: `src/gene.nim`, `src/commands/`, new viewer modules under `src/gene/`, parser integration in `src/gene/parser.nim`, `gene.nimble`, and new tests
