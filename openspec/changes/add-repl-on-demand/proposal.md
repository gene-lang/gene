# Proposal: Add REPL On Demand

## Why

The current REPL evaluates each line in a fresh top-level scope, so variables and definitions do not persist across inputs. We also lack an in-program REPL for debugging, which makes it hard to inspect or update live variables after an error. We need a REPL session that can be launched from running code, uses the caller scope, and returns a value to the caller.

## What Changes

- Add a `$repl` native function that starts an interactive session bound to the caller scope and returns the last evaluated value.
- Keep a persistent session scope for `gene repl`, so variables survive across inputs.
- Add a REPL-specific compile/exec path that reuses a scope tracker and avoids auto-closing the root scope per input.

## Impact

- Affected specs: repl (new)
- Affected code: `src/commands/repl.nim`, `src/gene/compiler.nim`, `src/gene/vm.nim`, `src/gene/stdlib.nim`
