## Context
M005 migrated the public feature from broad Experimental AOP to explicit runtime interception, but it deliberately kept legacy `(aspect ...)`, `.apply`, `.apply-fn`, `.enable-interception`, and `.disable-interception` as compatibility paths. The user has now chosen the public-plus-internals removal scope: remove the public legacy API and reduce internal AOP/Aspect naming where practical, while preserving the explicit interception runtime contract.

## Goals
- Remove the legacy AOP public syntax and method surfaces.
- Preserve `(interceptor ...)`, `(fn-interceptor ...)`, direct class/function application, `/.enable`, `/.disable`, supported advice forms, diagnostics, and class application atomicity.
- Rename practical source/test/doc terminology away from AOP/Aspect toward interception.
- Replace legacy AOP fixtures with explicit interception fixtures or targeted negative removal fixtures.
- Update OpenSpec/docs/assertions so stale AOP names cannot re-enter current public guidance.

## Non-Goals
- Do not remove historical `.gsd/` milestone artifacts.
- Do not add broad pointcuts, constructor/destructor join points, exception join points, regex selectors, priority controls, reset/unapply, keyword forwarding, async wrapping, or macro-transparent wrapping.
- Do not rewrite unrelated runtime systems merely to eliminate incidental substrings in archived/generated files.
- Do not sacrifice working explicit interception behavior for a cosmetic rename; if a deep internal rename is too risky, isolate it behind a documented follow-up.

## Decisions
- Public removal is hard: legacy AOP forms should fail rather than remain aliases or compatibility helpers.
- Internal rename is practical, not absolutist: public/runtime-facing type names, helper names, diagnostics, tests, and docs should move to interception terminology; low-value churn in historical artifacts or generated binaries is excluded.
- Legacy behavior coverage should migrate to explicit interception tests. Where removal behavior matters, add negative fixtures that prove old forms fail clearly.

## Risks / Trade-offs
- Removing compatibility breaks existing legacy AOP programs. Mitigation: docs should provide a concise migration note from each removed spelling to its explicit interception replacement.
- Internal renaming across Nim modules may create broad churn. Mitigation: rename in coherent seams and verify with build, focused fixtures, source assertions, public-surface assertions, and full testsuite.
- Deleting old tests can accidentally drop behavior coverage. Mitigation: map each removed AOP fixture to an explicit interception replacement or record why the behavior is no longer part of the contract.

## Migration Plan
1. Add negative removal diagnostics/fixtures for legacy public forms.
2. Remove legacy registration/application/toggle methods from the runtime surface.
3. Rename practical internal AOP/Aspect concepts to interception terminology while preserving explicit API behavior.
4. Replace stale tests/docs/OpenSpec wording and tighten public-surface assertions.
5. Run build, examples, OpenSpec validation, source/public assertions, selected explicit-interception fixtures, removal fixtures, and full testsuite.
