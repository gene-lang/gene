# Explicit Runtime Interception

Explicit runtime interception is an **Experimental** Gene surface for wrapping
selected class methods or standalone callables with advice. It replaces the old
broad AOP framing for new experiments: use `(interceptor ...)`,
`(fn-interceptor ...)`, direct callable application, and slash enablement
controls for current code.

Post-read action: after reading this page, a Gene user should be able to choose
the current explicit interception API for a class method or standalone function,
recognize legacy AOP spellings as temporary compatibility, and avoid unsupported
keyword, async, and macro-style boundaries.

This is not a stable-core or Beta contract. Treat it as a documented
Experimental runtime surface whose compatibility rules may still change before
promotion.

## Current posture

- **Use for new class experiments:** `(interceptor Name [targets] ...)` and
  direct callable application such as `(Name Class "method")`.
- **Use for new function experiments:** `(fn-interceptor Name [target] ...)` and
  direct callable wrapper application such as `(Name fn_value)`.
- **Use for enablement:** `Name/.enable`, `Name/.disable`,
  `application/.enable`, and `application/.disable`.
- **Keep legacy AOP forms only for compatibility/history:** `(aspect ...)`,
  `.apply`, `.apply-fn`, `.enable-interception`, and `.disable-interception`.
- **Do not treat this as broad AspectJ-style AOP:** there are no public
  pointcuts, constructor/destructor join points, regex method selectors, or
  macro-transparent wrappers.

## Advice forms

Class and function interceptors share the same advice vocabulary:

| Advice | Behavior |
| --- | --- |
| `before_filter` | Runs before other advice. A falsey result skips the wrapped callable and returns `nil`. |
| `before` | Runs before the wrapped callable. Multiple entries run in declaration order. |
| `invariant` | Runs before and after a non-escaped call. |
| `around` | Receives the wrapped callable as the final argument and may delegate to it. Only one `around` advice is allowed per target parameter. |
| `after` | Runs after a non-escaped call. `^^replace_result` lets the advice return replace the wrapped result. |

Advice bodies may be inline Gene bodies or symbols that resolve to callable
advice functions. Inline advice supports the current lexical-capture boundary
validated by the runtime fixtures, but this does not make interception
macro-transparent.

## Class interception

Define a class interceptor with `(interceptor ...)`:

```gene
(interceptor Audit [run stop]
  (before run [x]
    (println "audit before run" x)
  )
  (after run [x result]
    (println "audit after run" result)
  )
  (around stop [x wrapped]
    (println "audit around stop" x)
    (wrapped x)
  )
)
```

Apply it by calling the interceptor value directly with a class and one method
name for each interceptor target:

```gene
(var applications (Audit Service "run" "stop"))
(var run_application applications/0)
```

Class application semantics:

- the second argument must be a class;
- each mapping must be a string or symbol naming an existing method;
- the mapping count must match the interceptor target count;
- application installs wrappers around the selected class methods;
- unlisted methods remain unchanged;
- the return value is an array of interception application wrappers;
- installation is atomic for invalid method mappings, so a later invalid mapping
  does not leave earlier methods partially wrapped.

Interception mutates the selected class method table. Method calls through
instances of that class then run through the installed wrapper chain. Existing
method dispatch assumptions are invalidated when a wrapper is installed; toggle
operations are cheap flag changes and do not rebuild the method table.

## Function interception

Define a standalone function interceptor with `(fn-interceptor ...)`:

```gene
(fn-interceptor Trace [f]
  (before f [x]
    (println "trace before" x)
  )
  (around f [x wrapped]
    (wrapped x)
  )
  (after f [x result]
    (println "trace after" x result)
  )
)
```

Apply it by calling the interceptor value with exactly one callable target:

```gene
(fn inc [x] (x + 1))
(var wrapped (Trace inc))
(wrapped 4)
(inc 4) # still calls the original function without advice
```

Function application semantics:

- the target must be an ordinary callable, native callable, or existing
  interception wrapper;
- application returns one callable wrapper;
- the original function binding is not mutated;
- callers must invoke the returned wrapper when they want advice to run;
- nested wrappers are explicit when a returned wrapper is wrapped again.

## Enable and disable controls

Interception has two enablement levels:

1. **Definition-level controls** on the interceptor value:
   `Name/.disable` bypasses advice for every application of that interceptor,
   and `Name/.enable` restores it.
2. **Application-level controls** on a returned wrapper:
   `application/.disable` bypasses only that installed wrapper, and
   `application/.enable` restores it.

Advice runs only when both levels are enabled. When a wrapper is disabled,
dispatch calls the wrapper's stored original callable directly. In a wrapper
chain, disabling one wrapper bypasses only that wrapper; active outer or inner
wrappers still use their own flags.

Legacy `.enable-interception` and `.disable-interception` remain compatibility
controls for old AOP code, not the current spelling for new examples.

## Diagnostics

Invalid interception application fails at application time with catchable
messages that include `GENE.INTERCEPT` markers. The marker is intended to make
migration and tests precise while the human-readable message can improve over
time.

Current marker families include:

| Marker | Typical cause |
| --- | --- |
| `GENE.INTERCEPT.CLASS_TARGET` | A class interceptor was applied without a class or to a non-class target. |
| `GENE.INTERCEPT.MAPPING_ARITY` | Class method mappings do not match the interceptor target count. |
| `GENE.INTERCEPT.MAPPING_NAME` | A class mapping is not a string or symbol. |
| `GENE.INTERCEPT.MISSING_METHOD` | A named class method is not present. |
| `GENE.INTERCEPT.FN_ARITY` | A function interceptor was applied with zero or multiple positional targets. |
| `GENE.INTERCEPT.FN_TARGET` | A function interceptor target is not an ordinary callable target. |
| `GENE.INTERCEPT.KEYWORD_UNSUPPORTED` | Keyword application or a keyword-parameter function target hit a deferred boundary. |
| `GENE.INTERCEPT.MACRO_UNSUPPORTED` | A macro-style target or interception macro value was used where wrapping cannot preserve semantics. |
| `GENE.INTERCEPT.ASYNC_UNSUPPORTED` | An async function target hit the deferred async boundary. |

Diagnostics are targeted for the current migration boundary. Hard removal of
legacy AOP forms is still deferred; compatibility spellings may continue to run
until a later migration milestone removes or rejects them.

## Legacy compatibility

The old AOP spelling remains implemented for compatibility with existing
programs and maintainer tests:

- `(aspect ...)` can still define a compatibility interceptor value;
- `.apply` can still install class method wrappers;
- `.apply-fn` can still create standalone function wrappers;
- `.enable-interception` and `.disable-interception` can still toggle old-style
  wrapper state.

Do not teach these forms first in new docs, examples, or specs. Use them only
when maintaining old code or documenting migration history.

## Unsupported and deferred boundaries

The current Experimental surface is intentionally narrow:

- standalone wrapper calls with keyword arguments are unsupported;
- function interceptor targets with keyword parameters are rejected;
- async function targets are rejected;
- macro-style `fn!` targets are rejected by direct `fn-interceptor` application;
- legacy macro-style wrapping is compatibility behavior and is not
  macro-transparent;
- direct class interceptor application does not accept keyword options;
- broad pointcuts, constructor/destructor interception, exception join points,
  regex or selector method matching, priority controls, reset/unapply controls,
  and async advice isolation are deferred;
- stable-core or Beta promotion requires a later explicit decision and broader
  proof.

Interception can wrap selected runtime callables, but it does not change Gene's
macro evaluation model or promise transparent wrapping of every callable form.

## See also

- [Feature status](feature-status.md) for the public stability boundary.
- [AOP migration and implementation history](proposals/future/aop.md) for the
  earlier audit record and compatibility background.
