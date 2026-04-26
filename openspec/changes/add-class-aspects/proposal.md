## Why
Gene's public migration surface has moved from broad class-aspect language to explicit runtime interception. This active change keeps the historical `add-class-aspects` change id for continuity per D027, but the current contract now matches the implemented Experimental APIs after legacy AOP compatibility removal.

## What Changes
- Reframe the active change as **explicit runtime interception** for selected class methods and standalone callables.
- Document `(interceptor ...)` plus direct class application as the Experimental class surface.
- Document `(fn-interceptor ...)` plus direct callable wrapper application as the Experimental function surface, with original function bindings left unchanged.
- Specify definition-level and application-level `/.enable` / `/.disable` controls, supported advice forms, targeted `GENE.INTERCEPT` diagnostics, and atomic class application failures.
- **BREAKING** Remove legacy `(aspect ...)`, `.apply`, `.apply-fn`, `.enable-interception`, and `.disable-interception` from the current public runtime surface.
- Explicitly defer keyword, async, macro-style, broad pointcut, and other non-core interception boundaries instead of presenting them as supported.

## Impact
- Affected specs: `explicit-interception` is the current capability delta; the stale `class-aspects` capability delta is removed from the active change to avoid contradictory current contracts.
- Affected code: parser/compiler forms for interceptor definitions, VM interception wrappers, class/function application helpers, slash toggle methods, targeted diagnostics, testsuite fixtures, public docs, and runnable examples.
- Migration impact: existing legacy AOP programs must migrate to explicit interception APIs before running on this runtime.
