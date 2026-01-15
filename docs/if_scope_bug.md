# If/Try Scope Unwinding Bug (IkVarResolve out-of-bounds)

## Symptom

You may see runtime failures like:

```
IkVarResolve: index <n> >= scope.members.len <m>
```

This often shows up after a `try`/`catch` handles an exception thrown from inside a nested scope (commonly an `if`/`loop` body). It is not related to GIR caching.

## Root Cause

Gene scopes are created and destroyed by `IkScopeStart` / `IkScopeEnd`. When an exception is thrown, the VM jumps directly to the active handler’s `catch_pc`, skipping any `IkScopeEnd` instructions that would normally run on the way out.

Before the fix, the VM did not unwind the dynamic scope chain during exception dispatch. That meant the current frame could resume in `catch` (and later code) with a stale inner scope still active. Subsequent variable resolves/assigns that were compiled assuming an outer scope would then index into the wrong `scope.members`, triggering out-of-bounds errors.

## Minimal Repro

This reproduces the crash pattern (nested scope opened, exception jumps over its `IkScopeEnd`, then later access expects the outer scope):

```gene
(var a0 0) (var a1 1) (var a2 2) (var a3 3) (var a4 4) (var a5 5)
(var a6 6) (var a7 7) (var a8 8) (var a9 9) (var a10 10) (var a11 11)

(try
  (if true
    (var b0 0) (var b1 1) (var b2 2) (var b3 3) (var b4 4)
    (var b5 5) (var b6 6) (var b7 7) (var b8 8) (var b9 9)
    (throw "boom")
  )
catch *
  0
)

a11
```

## Fix

The VM now records the active `Scope` when installing an exception handler and unwinds scopes back to that baseline before transferring control to `catch`.

Implementation:
- `src/gene/types/type_defs.nim`: `ExceptionHandler` stores `scope`
- `src/gene/vm.nim`: `dispatch_exception` calls `unwind_scopes_to(handler.scope)` before jumping to `catch_pc`
- `tests/test_exception.nim`: regression test covering the repro above

## Notes

- This fix addresses the common “scope.members truncated / VarResolve out-of-range after catch” class of issues.
- There may still be separate work needed for full `try/finally` semantics and for cleaning up intermediate stack values on exceptional control flow.

