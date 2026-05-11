# Explicit Runtime Interception

Explicit runtime interception is a **Beta** Gene surface for wrapping selected
class methods or standalone callables with advice. Use it when you want a
specific wrapper at a specific runtime boundary and you can name the callable or
method you are wrapping.

After reading this page, a Gene user or contributor should be able to choose
between `(interceptor ...)` and `(fn-interceptor ...)`, apply the interceptor
directly, preserve keyword and spread calls through the wrapper, use
`/.enable` / `/.disable`, and avoid removed AOP-era APIs.

## Beta boundary

The Beta contract is intentionally narrow:

- class method interception uses `(interceptor Name [targets] ...)` and direct
  application such as `(Name Class "method")`;
- standalone callable interception uses `(fn-interceptor Name [f] ...)` and
  direct application such as `(Name callable)`;
- returned wrappers preserve expanded positional arguments and keyword pairs for
  supported method/function calls, including calls made with positional spread
  and keyword spread;
- advice matchers can bind positional and keyword parameters using normal Gene
  function parameter syntax;
- `around` advice receives a wrapped callable as its final argument and may
  forward to it with normal Gene calls;
- definition-level and application-level `/.enable` / `/.disable` controls are
  supported;
- direct interceptor application keyword options are rejected with
  `GENE.INTERCEPT.KEYWORD_UNSUPPORTED`.

Beta does not mean stable core. It also does not revive broad AOP features:
there are no public pointcuts, constructor/destructor interception, exception
interception, regex selectors, priority ordering, reset/unapply controls, or
macro-transparent wrappers.

## Choosing the interceptor form

| Goal | Use | Application result |
| --- | --- | --- |
| Wrap one or more named class methods | `(interceptor Name [targets] ...)` | An array of method wrapper applications installed on the class. |
| Wrap one standalone callable | `(fn-interceptor Name [f] ...)` | One callable wrapper; the original binding is unchanged. |

Both forms use the same advice vocabulary: `before_filter`, `before`,
`invariant`, `around`, and `after`.

## Advice forms

| Advice | Behavior |
| --- | --- |
| `before_filter` | Runs before other advice. A falsey result skips the wrapped callable and returns `nil`. |
| `before` | Runs before the wrapped callable. Multiple entries run in declaration order. |
| `invariant` | Runs before and after a non-escaped call. |
| `around` | Receives the wrapped callable as the final argument and may delegate to it. Only one `around` advice is allowed for each target placeholder. |
| `after` | Runs after a non-escaped call. `^^replace_result` lets the advice return replace the wrapped result. |

Advice bodies may be inline Gene bodies or helper functions referenced by name.
Inline advice uses the same parameter matcher shape as the wrapped call. Helper
advice functions receive the receiver slot first; use a throwaway name such as
`_self` for standalone callable wrappers when the receiver is not needed.

## Class method interception

Define a class interceptor with `(interceptor ...)`:

```gene
(interceptor AccountAudit [charge]
  (before charge [amount ^currency]
    (println "charge before" amount currency)
  )
  (after charge [amount ^currency result]
    (println "charge after" result)
  )
)
```

Define or use a class with a matching method:

```gene
(class Account
  (method charge [amount ^currency]
    (println "charge body" amount currency)
    amount
  )
)
```

Apply the interceptor by calling the interceptor value directly with a class and
one method name for each target placeholder:

```gene
(var applications (AccountAudit Account "charge"))
(var charge_audit applications/0)
```

Class application semantics:

- the first application argument must be a class;
- each mapping must be a string or symbol naming an existing method;
- the mapping count must match the interceptor target count;
- application installs wrappers around the selected class methods;
- unlisted methods remain unchanged;
- the return value is an array of wrapper applications;
- installation is atomic for invalid mappings, so a later invalid method name
  does not leave earlier methods partially wrapped.

Calls to the intercepted method then run through the wrapper:

```gene
(var args [10 5])
(var kws {^currency "USD"})
(account .charge args... ^... kws)
```

The wrapper receives the expanded call shape: positional arguments become
positional arguments, keyword pairs remain keyword pairs, and advice keyword
parameters bind normally. The runtime does not preserve whether a caller used
literal arguments or spread syntax; it preserves the expanded arguments that the
call produced.

## Standalone callable interception

Define a function interceptor with `(fn-interceptor ...)`:

```gene
(fn-interceptor Trace [f]
  (before f [x y ^limit]
    (println "trace before" x y limit)
  )
  (around f [x y ^limit wrapped]
    (wrapped x y ^limit limit)
  )
  (after f [x y ^limit result]
    (println "trace after" result)
  )
)
```

Apply it by calling the interceptor value with exactly one callable target:

```gene
(fn bounded_add [x y ^limit]
  (+ x y limit)
)

(var traced_add (Trace bounded_add))
(traced_add 2 3 ^limit 5)
(bounded_add 2 3 ^limit 5) # still calls the original function without advice
```

Function application semantics:

- the target must be an ordinary callable, native callable, or existing
  interception wrapper;
- application returns one callable wrapper;
- the original function binding is not mutated;
- callers must invoke the returned wrapper when they want advice to run;
- wrapping an existing wrapper creates an explicit wrapper chain, and each
  wrapper keeps its own enablement state.

## Keyword, spread, and `around` forwarding

Wrapper calls preserve supported keyword and spread call shapes for both class
methods and standalone function wrappers:

```gene
(var args [2 3])
(var kws {^limit 5})
(traced_add args... ^... kws)
```

Advice can bind the same keyword parameters as the wrapped callable:

```gene
(before f [x y ^limit = 10]
  (println "limit" limit)
)
```

`around` advice should forward with an ordinary Gene call to the provided
`wrapped` callable. Inline `around` advice can forward directly:

```gene
(around f [x y ^limit wrapped]
  (wrapped x y ^limit limit)
)
```

Helper-function `around` advice uses the same forwarding rule. Accept the
receiver slot first, then the wrapped call arguments, then the `wrapped` callable
as the final argument:

```gene
(fn forward_with_spread [_self x y ^limit wrapped]
  (var xs [x y])
  (var kw {^limit limit})
  (wrapped xs... ^... kw)
)

(fn-interceptor ForwardingTrace [f]
  (around f forward_with_spread)
)
```

For class method helpers, the first argument is the receiver instance. For
standalone callable helpers, use `_self` if that slot is not meaningful.

## Enable and disable controls

Interception has two enablement levels:

1. **Definition-level controls** on the interceptor value:
   `Name/.disable` bypasses advice for every application created from that
   interceptor, and `Name/.enable` restores it.
2. **Application-level controls** on a returned wrapper:
   `application/.disable` bypasses only that wrapper, and
   `application/.enable` restores it.

Advice runs only when both levels are enabled. In a wrapper chain, disabling one
wrapper bypasses only that wrapper; active outer or inner wrappers keep their
own flags.

## Diagnostics

Invalid interception application fails at application time with catchable
messages that include `GENE.INTERCEPT` markers. The marker is intended to make
tests precise while human-readable wording can improve over time.

Current marker families include:

| Marker | Typical cause |
| --- | --- |
| `GENE.INTERCEPT.CLASS_TARGET` | A class interceptor was applied without a class or to a non-class target. |
| `GENE.INTERCEPT.MAPPING_ARITY` | Class method mappings do not match the interceptor target count. |
| `GENE.INTERCEPT.MAPPING_NAME` | A class mapping is not a string or symbol. |
| `GENE.INTERCEPT.MISSING_METHOD` | A named class method is not present. |
| `GENE.INTERCEPT.FN_ARITY` | A function interceptor was applied with zero or multiple positional targets. |
| `GENE.INTERCEPT.FN_TARGET` | A function interceptor target is not a supported callable target. |
| `GENE.INTERCEPT.KEYWORD_UNSUPPORTED` | Direct interceptor application used keyword options. |
| `GENE.INTERCEPT.MACRO_UNSUPPORTED` | A macro-style target or interception macro value was used where wrapping cannot preserve semantics. |
| `GENE.INTERCEPT.ASYNC_UNSUPPORTED` | An async function target hit the deferred async boundary. |

The `KEYWORD_UNSUPPORTED` boundary is precise: direct interceptor application is
positional-only. These calls are rejected because they try to pass keyword
options to the application itself:

```gene
(Trace bounded_add ^label "audit")
(AccountAudit Account "charge" ^label "audit")
```

That boundary does **not** mean returned wrappers reject keyword calls. Calls
through `traced_add` or an intercepted method can use keyword arguments and
keyword spread when the wrapped callable or method supports them.

## Removed legacy AOP API

The historical AOP spellings have been removed from the current runtime surface.
Use the replacements below:

| Removed spelling | Replacement |
| --- | --- |
| old `(aspect ...)` definition form | `(interceptor ...)` for classes or `(fn-interceptor ...)` for standalone callables |
| old `.apply` class application helper | direct class application: `(Name Class "method")` |
| old `.apply-fn` function application helper | direct function application: `(Name callable)` |
| old `.enable-interception` / `.disable-interception` helpers | `application/.enable` and `application/.disable` |
| old definition-wide toggle spelling, if present in old code | `Name/.enable` and `Name/.disable` |

Existing programs that still use the removed spellings must migrate before
running on this runtime.

## Unsupported and deferred boundaries

The Beta surface does not include every callable shape or AOP-era feature:

- direct interceptor application keyword options are rejected;
- async function targets are rejected;
- macro-style `fn!` targets are rejected by direct `fn-interceptor` application;
- native macro targets are rejected;
- broad pointcuts, constructor/destructor interception, exception interception,
  regex or selector method matching, priority controls, reset/unapply controls,
  and async advice isolation are deferred;
- stable-core promotion requires a later explicit decision and broader proof.

Interception can wrap selected runtime callables, but it does not change Gene's
macro evaluation model or promise transparent wrapping of every callable form.

## See also

- [Feature status](feature-status.md) for the public stability boundary.
- [AOP migration history](proposals/future/aop.md) for the earlier removal and
  migration record.
