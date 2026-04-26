## 1. Runtime Surface Removal
- [x] 1.1 Remove `(aspect ...)` as a registered native macro / public definition form.
- [x] 1.2 Remove legacy `.apply` class application and `.apply-fn` function application methods from the public runtime surface.
- [x] 1.3 Remove legacy `.enable-interception` and `.disable-interception` public toggle methods.
- [x] 1.4 Add targeted failure coverage for removed legacy forms so failures are intentional and catchable where the runtime reaches the interception subsystem.

## 2. Internal Naming Cleanup
- [x] 2.1 Rename practical public/runtime-facing `Aspect`/AOP identifiers toward `Interceptor`/`Interception` terminology where feasible.
- [x] 2.2 Update source assertion scripts to track interception-named helpers and invariants.
- [x] 2.3 Keep any unavoidable internal compatibility aliases local, documented, and invisible to Gene programs.

## 3. Tests and Fixtures
- [x] 3.1 Map each existing `*_aop_*` fixture to explicit interception coverage, a removal-negative fixture, or deletion with rationale.
- [x] 3.2 Rename remaining interception fixtures so current testsuite names do not advertise AOP as a current feature.
- [x] 3.3 Update selected regression commands and testsuite docs to use explicit interception fixtures only.

## 4. Docs, Examples, and OpenSpec
- [x] 4.1 Update `docs/interception.md`, `docs/feature-status.md`, `docs/architecture.md`, examples docs, and testsuite docs for hard legacy removal.
- [x] 4.2 Update `docs/proposals/future/aop.md` or replace it with historical/migration-only wording that does not teach current AOP syntax.
- [x] 4.3 Modify the active `add-class-aspects` / `explicit-interception` OpenSpec delta to remove the legacy compatibility requirement.
- [x] 4.4 Tighten `interception_public_surface_assertions.py` to fail on legacy AOP public syntax outside explicit historical/GSD allowlists.

## 5. Validation
- [x] 5.1 Run `nimble build`.
- [x] 5.2 Run the explicit interception public example and examples runner.
- [x] 5.3 Run `openspec validate add-class-aspects --strict` and `openspec validate remove-legacy-aop-surface --strict`.
- [x] 5.4 Run interception source/public assertion scripts.
- [x] 5.5 Run selected explicit-interception and legacy-removal fixtures.
- [x] 5.6 Run full `./testsuite/run_tests.sh`.
