## 1. Explicit Interception Definitions
- [x] 1.1 Implement `(interceptor ...)` as the Beta class interceptor definition form.
- [x] 1.2 Implement `(fn-interceptor ...)` as the Beta standalone callable interceptor definition form.
- [x] 1.3 Support inline and callable advice entries for `before_filter`, `before`, `invariant`, `around`, and `after`.

## 2. Explicit Interception Application
- [x] 2.1 Apply class interceptors by directly calling the interceptor value with a class and one method mapping per target.
- [x] 2.2 Return wrapper arrays from class application while leaving unlisted class methods unchanged.
- [x] 2.3 Apply function interceptors by directly calling the interceptor value with exactly one callable target.
- [x] 2.4 Return callable wrappers from function application without mutating the original function binding.
- [x] 2.5 Preserve positional arguments, keyword arguments, positional spread, and keyword spread through returned wrappers and intercepted methods when the wrapped callable supports those call shapes.

## 3. Advice Semantics, Enablement, Diagnostics, and Boundaries
- [x] 3.1 Bind inline advice and callable advice references with normal Gene function parameter syntax, including supported keyword matcher bindings.
- [x] 3.2 Pass the wrapped callable to `around` advice as the final argument and support forwarding by calling it with normal Gene call syntax.
- [x] 3.3 Support definition-level `/.enable` / `/.disable` controls.
- [x] 3.4 Support application-level `/.enable` / `/.disable` controls with chain-local bypass semantics.
- [x] 3.5 Emit targeted `GENE.INTERCEPT` diagnostic markers for invalid class/function applications.
- [x] 3.6 Preserve atomic class application failures when any requested method mapping is invalid.
- [x] 3.7 Reject direct interceptor application keyword options while preserving keyword calls through returned wrappers and intercepted methods.
- [x] 3.8 Reject or defer async and macro-style boundaries without presenting them as supported.

## 4. Legacy AOP Removal
- [x] 4.1 Remove `(aspect ...)` as a public definition form.
- [x] 4.2 Remove legacy `.apply`, `.apply-fn`, `.enable-interception`, and `.disable-interception` public methods.
- [x] 4.3 Rename practical runtime-facing internals, source assertions, and current tests toward interception terminology.
- [x] 4.4 Add negative coverage for removed legacy spellings.

## 5. Public Surface
- [x] 5.1 Publish current docs that teach Beta explicit interception and describe historical AOP only as migration history.
- [x] 5.2 Add a runnable explicit interception example and wire it into the examples runner.
- [x] 5.3 Retain the active `add-class-aspects` change id for continuity per D057 while maintaining the `explicit-interception` capability delta as the Beta contract.
- [x] 5.4 Add public-surface assertions that catch stale preferred-legacy, broad-AOP, or outdated pre-Beta wording in tracked docs, examples, OpenSpec, and testsuite surfaces.

## 6. Validation
- [x] 6.1 Run selected class/function interception regression fixtures.
- [x] 6.2 Run `openspec validate add-class-aspects --strict` after updating the OpenSpec delta.
- [x] 6.3 Run the final removal and Beta continuity suite, including build, examples, OpenSpec validation, source assertions, public-surface assertions, selected fixtures, and full testsuite.
