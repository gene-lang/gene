# Implementation Tasks: REPL On Demand

## 1. Core REPL Session
- [x] 1.1 Add a REPL compile path that reuses a provided `ScopeTracker` and skips top-level `IkScopeStart`/`IkScopeEnd`.
- [x] 1.2 Update `gene repl` to keep a persistent session scope across inputs.

## 2. In-Program REPL
- [x] 2.1 Add a native `$repl` function that enters the REPL with a child scope of the caller.
- [x] 2.2 Ensure `($repl)` returns the last evaluated expression (or `NIL` when empty).

## 3. Tests and Docs
- [x] 3.1 Add tests for REPL scope persistence (definitions survive across inputs).
- [x] 3.2 Add tests for `($repl)` scope behavior and return values.
