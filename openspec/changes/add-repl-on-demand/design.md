## Context

Gene's REPL currently compiles each line as a standalone compilation unit, which creates and tears down a top-level scope every time. This resets variables and makes interactive debugging impractical. We also need a REPL that can be entered from running Gene code (for example inside a catch block) and that returns a value to the caller.

## Goals / Non-Goals

Goals:
- Provide a REPL that can be launched from Gene code via `($repl)`.
- Use a child scope that can read and update variables in the caller scope.
- Persist variables across inputs in `gene repl`.
- Return the last evaluated REPL expression to the caller.

Non-Goals:
- Full debugger features (breakpoints, step-through, etc.).
- Multi-threaded REPL execution.
- New language syntax.

## Decisions

- **Session-scope compilation**: Add a `parse_and_compile_repl` path that reuses a persistent `ScopeTracker` and skips top-level `start_scope`/`end_scope` for each input.
- **Manual scope setup**: The REPL session creates a runtime scope once (a child of the caller scope) and reuses it across inputs. The compiler uses the same `ScopeTracker` for variable resolution across inputs.
- **Return last value**: The REPL loop tracks the last non-void evaluation result and returns it from `($repl)` (or `NIL` if nothing was evaluated).

## Risks / Trade-offs

- **Scope tracker reuse**: Reusing a `ScopeTracker` across inputs must remain consistent with runtime scope chains. This requires careful handling so `IkScopeStart` is not emitted redundantly for the REPL root scope.
- **Interactive flow**: Returning the last value requires the REPL loop to track results even when input is empty or errors occur.

## Migration Plan

1. Add a REPL compile path that accepts a `ScopeTracker` and does not emit top-level scope start/end.
2. Update `gene repl` to create a persistent session scope and reuse the compiler path for each input.
3. Add a native `$repl` function that enters the same REPL loop with the caller scope as parent.
4. Add tests for REPL scope persistence and return values (using a scripted REPL session or direct compile/exec path).

## Open Questions

- Should REPL commands (`exit`, `quit`) be customizable per session?
