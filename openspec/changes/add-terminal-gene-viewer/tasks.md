## 1. CLI Surface
- [x] 1.1 Add a `view` command module and register it in the main CLI help/dispatch path.
- [x] 1.2 Define startup/help/error behavior for `gene view <file>` including missing-file and invalid-input cases.
- [x] 1.3 Add any required ncurses dependency or build linkage needed by the terminal backend.

## 2. Viewer Data Model
- [x] 2.1 Implement a document model that can represent either a single root value or a synthetic root sequence for multi-form logs.
- [x] 2.2 Reuse parser streaming to index top-level entries without recursively loading unopened descendants.
- [x] 2.3 Implement lazy child expansion and a path model that preserves array indices, map keys, and Gene child/property navigation.

## 3. Terminal UI
- [x] 3.1 Implement the full-screen layout with header, scrollable body, and footer legend.
- [x] 3.2 Implement keyboard handling for Up, Down, Left, Right, `F1`, `F5`, and `F10`.
- [x] 3.3 Render concise row summaries for scalar values and composite containers, including current selection highlighting.

## 4. Validation
- [x] 4.1 Add tests for top-level streaming/index behavior on multi-form Gene logs.
- [x] 4.2 Add tests for navigation/path behavior in the non-TTY viewer state machine.
- [x] 4.3 Add a CLI-level regression test for command startup/help/error handling.
- [x] 4.4 Run `openspec validate add-terminal-gene-viewer --strict`.
