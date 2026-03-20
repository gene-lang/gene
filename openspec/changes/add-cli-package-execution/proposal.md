## Why
Gene can resolve packages during imports, but the CLI cannot yet start a package-oriented workflow from an arbitrary directory. That makes package apps like GeneClaw awkward to launch unless the user first changes directories into the package tree.

## What Changes
- Add a `--pkg <package-name-or-root>` option to CLI execution commands so the command can select an explicit package context.
- Auto-discover package context for CLI execution commands when they start inside a package tree or run a package-owned script without `--pkg`.
- Resolve relative source/script paths passed to those commands from the selected package root instead of the process cwd.
- Execute inline `eval`, `pipe`, and `repl` sessions with the selected package context so `$pkg` and unqualified package-local imports behave as if the session started inside that package.
- Create a global application object for CLI main-thread sessions so `$app` is always available and `$app.pkg` matches the active or discovered package.
- Preserve the real process cwd for runtime filesystem behavior such as `cwd` and relative OS operations.

## Impact
- Affected specs: `package-system`
- Affected code:
  - `src/gene/vm/module.nim`
  - `src/gene/vm/entry.nim`
  - `src/commands/run.nim`
  - `src/commands/eval.nim`
  - `src/commands/pipe.nim`
  - `src/commands/repl.nim`
  - CLI/package-focused tests
