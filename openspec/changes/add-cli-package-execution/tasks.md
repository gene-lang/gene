## 1. Implementation
- [x] 1.1 Add shared CLI package resolution that accepts either a package name or a package-root path.
- [x] 1.2 Add `--pkg` handling to `gene run` and resolve relative target files from the selected package root.
- [x] 1.3 Add `--pkg` handling to `gene eval`, `gene pipe`, and `gene repl` so inline execution uses the selected package context.
- [x] 1.4 Auto-discover package context for CLI sessions launched from inside a package tree when `--pkg` is omitted.
- [x] 1.5 Expose `$app` in CLI main-thread sessions and keep `$app.pkg` aligned with the selected or discovered package.
- [x] 1.6 Keep process cwd unchanged while package resolution and `$pkg` reflect the selected package.
- [x] 1.7 Add focused tests for run/eval/repl package context, autodiscovery, and pipe file resolution.

## 2. Validation
- [x] 2.1 Run targeted Nim tests for CLI/package behavior.
- [x] 2.2 Run the pipe command suite.
- [x] 2.3 Run `openspec validate add-cli-package-execution --strict`.
