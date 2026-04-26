## Why
Gene's public migration surface has moved from broad class-aspect language to explicit runtime interception. This active change keeps the historical `add-class-aspects` change id for continuity per D027, but the current contract now needs to match the implemented Experimental APIs, docs, examples, diagnostics, and migration posture.

## What Changes
- Reframe the active change as **explicit runtime interception** for selected class methods and standalone callables.
- Document `(interceptor ...)` plus direct class application as the preferred Experimental class surface.
- Document `(fn-interceptor ...)` plus direct callable wrapper application as the preferred Experimental function surface, with original function bindings left unchanged.
- Specify definition-level and application-level `/.enable` / `/.disable` controls, supported advice forms, targeted `GENE.INTERCEPT` diagnostics, and atomic class application failures.
- Keep legacy `(aspect ...)`, `.apply`, `.apply-fn`, `.enable-interception`, and `.disable-interception` only as temporary compatibility and migration history.
- Explicitly defer keyword, async, macro-style, broad pointcut, and other non-core interception boundaries instead of presenting them as supported.

## Impact
- Affected specs: `explicit-interception` is the current capability delta; the stale `class-aspects` capability delta is removed from the active change to avoid contradictory current contracts.
- Affected code: parser/compiler forms for interceptor definitions, VM interception wrappers, class/function application helpers, slash toggle methods, targeted diagnostics, testsuite fixtures, public docs, and runnable examples.
- Migration impact: existing legacy AOP programs continue to run through compatibility forms, but new public guidance teaches explicit interception first.
