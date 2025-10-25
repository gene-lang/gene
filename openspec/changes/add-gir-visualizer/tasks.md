## 1. CLI Support
- [x] 1.1 Add a `gir` command module that registers a `show` subcommand (alias `visualize`) under the CLI manager.
- [x] 1.2 Implement GIR loading via `load_gir` with graceful error handling for missing/invalid files.
- [x] 1.3 Render header, constants, symbols, and instruction listings to stdout using a consistent format.

## 2. Validation
- [x] 2.1 Add a regression test that compiles a sample gene file, invokes the show command, and asserts on key output lines.
- [x] 2.2 Update CLI help/documentation to mention the new command.
