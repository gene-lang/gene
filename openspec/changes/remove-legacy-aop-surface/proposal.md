## Why
M005 intentionally left legacy AOP syntax and names available as temporary compatibility while explicit interception became the preferred Experimental surface. The next step is to stop carrying the old AOP public contract and remove stale AOP naming from tests/docs and practical internals so Gene exposes one interception model.

## What Changes
- **BREAKING** Remove legacy user-facing AOP forms: `(aspect ...)`, `.apply`, `.apply-fn`, `.enable-interception`, and `.disable-interception` are no longer supported compatibility APIs.
- Replace or delete legacy AOP fixtures; keep behavior coverage only through explicit `(interceptor ...)`, `(fn-interceptor ...)`, direct application, and `/.enable` / `/.disable` fixtures.
- Update docs, examples, testsuite docs, and OpenSpec so AOP appears only as historical migration context where unavoidable, not as current syntax or test terminology.
- Rename practical internal AOP/Aspect concepts toward interception naming where feasible without changing the explicit interception runtime behavior.
- Preserve explicit interception behavior, diagnostics, enablement semantics, class application atomicity, and public-surface drift guards.

## Impact
- Affected specs: `explicit-interception`; supersedes the migration-only compatibility requirement in the active `add-class-aspects` change.
- Affected code: stdlib interception/aspect implementation, compiler native macro registrations, method registration for legacy application/toggle names, VM/runtime type naming where Aspect/AOP leaks into practical internals, testsuite fixtures, source assertion scripts, public-surface assertions, docs, examples, and OpenSpec.
- Migration impact: existing programs using legacy AOP APIs will break and must migrate to explicit interception APIs before upgrading.
