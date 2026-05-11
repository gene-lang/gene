## Why
Gene's public migration surface has moved from broad class-aspect language to a narrow **Beta** explicit runtime interception contract. Per D057, this active change keeps the historical `add-class-aspects` change id for continuity while the capability delta now documents the durable Beta contract after legacy AOP compatibility removal.

## What Changes
- Reframe the active change as **Beta explicit runtime interception** for selected class methods and standalone callables.
- Document `(interceptor ...)` plus direct class application as the Beta class method interception surface.
- Document `(fn-interceptor ...)` plus direct callable wrapper application as the Beta function interception surface, with original function bindings left unchanged.
- Specify returned wrapper behavior for positional arguments, keyword arguments, positional spread, keyword spread, advice keyword matcher binding, and `around` forwarding through the wrapped callable.
- Specify definition-level and application-level `/.enable` / `/.disable` controls, supported advice forms, targeted `GENE.INTERCEPT` diagnostics, and atomic class application failures.
- **BREAKING** Keep legacy `(aspect ...)`, `.apply`, `.apply-fn`, `.enable-interception`, and `.disable-interception` outside the current public runtime surface.
- Explicitly defer async, macro-style, broad pointcut, constructor/destructor, exception join point, selector, priority, reset/unapply, async advice isolation, and Stable Core promotion boundaries instead of presenting them as supported.

## Impact
- Affected specs: `explicit-interception` remains the current capability delta under the retained `add-class-aspects` change id; no parallel change id is introduced.
- Affected code: parser/compiler forms for interceptor definitions, VM interception wrappers, class/function application helpers, slash toggle methods, targeted diagnostics, testsuite fixtures, public docs, and runnable examples.
- Migration impact: existing legacy AOP programs must migrate to explicit interception APIs before running on this runtime.
