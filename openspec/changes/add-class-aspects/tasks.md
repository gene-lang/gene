## 1. Explicit Interception Definitions
- [x] 1.1 Implement `(interceptor ...)` as the preferred Experimental class interceptor definition form.
- [x] 1.2 Implement `(fn-interceptor ...)` as the preferred Experimental standalone callable interceptor definition form.
- [x] 1.3 Support inline and callable advice entries for `before_filter`, `before`, `invariant`, `around`, and `after`.

## 2. Explicit Interception Application
- [x] 2.1 Apply class interceptors by directly calling the interceptor value with a class and one method mapping per target.
- [x] 2.2 Return wrapper arrays from class application while leaving unlisted class methods unchanged.
- [x] 2.3 Apply function interceptors by directly calling the interceptor value with exactly one callable target.
- [x] 2.4 Return callable wrappers from function application without mutating the original function binding.

## 3. Enablement, Diagnostics, and Boundaries
- [x] 3.1 Support definition-level `/.enable` / `/.disable` controls.
- [x] 3.2 Support application-level `/.enable` / `/.disable` controls with chain-local bypass semantics.
- [x] 3.3 Emit targeted `GENE.INTERCEPT` diagnostic markers for invalid class/function applications.
- [x] 3.4 Preserve atomic class application failures when any requested method mapping is invalid.
- [x] 3.5 Reject or defer keyword, async, and macro-style boundaries without presenting them as supported.

## 4. Public Migration Surface
- [x] 4.1 Publish current docs that prefer explicit interception and demote broad AOP wording to compatibility/history.
- [x] 4.2 Add a runnable explicit interception example and wire it into the examples runner.
- [x] 4.3 Replace the stale `class-aspects` OpenSpec delta with the `explicit-interception` capability delta while retaining the change id for continuity per D027.
- [ ] 4.4 Add public-surface assertions that catch stale preferred-legacy or broad-AOP wording in tracked docs, examples, OpenSpec, and testsuite surfaces.

## 5. Validation
- [x] 5.1 Run selected class/function interception regression fixtures.
- [x] 5.2 Run `openspec validate add-class-aspects --strict` after replacing the OpenSpec delta.
- [ ] 5.3 Run the final slice closure suite, including build, examples, OpenSpec validation, source assertions, public-surface assertions, selected fixtures, and full testsuite.
