## Why
Pattern matching semantics are currently implicit; we need a baseline design for argument matching and the `(match [pattern] value)` expression that preserves performance (no aggregate argument object) and documents scope/shadowing behavior.

## What Changes
- Define the minimal scope of pattern matching (argument binding and single-value `match` expression only).
- Document the performance constraint (no aggregate object for argument matching) and scope rules (reuse scope, allow shadowing).
- Specify compile-time lowering for `match` destructuring and defer pointer-based matcher optimization.
- Capture open questions to resolve before implementation (arity rules, type handling, supported pattern forms).

## Impact
- Affected specs: pattern-matching
- Affected code: compiler.nim (`compile_match` lowering), VM child access, argument binder helpers, documentation/tests
