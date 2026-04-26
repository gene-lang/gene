# AOP implementation audit

This document is a current-state audit of Gene's aspect-oriented programming
(AOP) implementation. It is written for a maintainer who needs to classify AOP
behavior before the S02 proof pass and the S03 keep/remove/defer
recommendation.

The job of this page is not to promote AOP or preserve old proposal text. It
separates behavior into five buckets:

- **Implemented:** present in the Nim VM or stdlib registration path.
- **Verified:** implemented and backed by tracked executable fixtures.
- **Unverified:** visible in code but not yet covered by the S01 fixture map.
- **Unsupported:** not registered as current public behavior.
- **Stale:** design-era wording that contradicts the current runtime.

## Status and source of truth

**Status:** AOP is an implemented, narrow runtime surface that remains under
audit. It is not being promoted to the stable language boundary by this
document. The strategic recommendation is still pending: keep/remove/defer is
an S03 decision after S02 proof work.

**Source of truth:** runtime code and tracked fixtures outrank this historical
proposal text. Use these sources when resolving conflicts:

| Evidence source | What it establishes |
| --- | --- |
| `src/gene/stdlib/aspects.nim` | Live public registration for `(aspect ...)`, `Aspect.apply`, `Aspect.apply-fn`, `Aspect.enable-interception`, and `Aspect.disable-interception`. This module is the registration authority even though older helper code still exists elsewhere in stdlib. |
| `src/gene/types/type_defs.nim` | `Aspect`, `Interception`, `AopAfterAdvice`, `AopContext`, `VkAspect`, `VkInterception`, and the VM `aop_contexts` stack. |
| `src/gene/types/reference_types.nim` | Reference union arms that store `aspect` for `VkAspect` and `interception` for `VkInterception`. |
| `src/gene/compiler/operators.nim` | `(aspect ...)` is excluded from the regular fast-call path so it can remain macro-dispatched. |
| `src/gene/vm/dispatch.nim` and `src/gene/vm/exec.nim` | Invocation and dispatch behavior for `VkInterception`, including method calls, function calls, around advice, chaining, and inactive interceptions. |
| Tracked testsuite fixtures | Executable proof for the behaviors named in the verification table below. |
| `docs/feature-status.md` | AOP is outside the documented stable language boundary and should not be framed as a release guarantee. |

## Current public surface

### Aspect definition

AOP definitions use the native macro form:

```gene
(aspect Audit [method_name]
  (before method_name [x]
    (println "before" x)
  )
  (around method_name [x wrapped]
    (wrapped x)
  )
  (after method_name [x result]
    (println "after" result)
  )
)
```

The second argument is an array of aspect parameter names. Advice targets must
name one of those parameters. Application maps each parameter to a concrete
method or function name.

Supported advice forms are:

| Advice form | Current behavior |
| --- | --- |
| `before` | Runs before the wrapped callable. Multiple entries for the same parameter are stored in declaration order. |
| `before_filter` | Runs before normal `before` advice. A falsey result skips the wrapped callable and returns `nil`. |
| `invariant` | Runs before and after the wrapped callable when the call reaches the normal execution path. |
| `around` | Wraps the original callable. Only one `around` advice is allowed per aspect parameter. The wrapped callable is passed as the final argument. |
| `after` | Runs after a non-escaped call. If `^^replace_result` is present, the advice return value replaces the wrapped call result. |

Advice bodies can be inline function bodies, or they can be symbols that resolve
to `VkFunction` or `VkNativeFn` callables in the caller/runtime namespaces.

### Class method application: `.apply`

`(A .apply C "m1" "m2")` applies an aspect to class methods. The receiver must
be a `VkAspect`, the second argument must be a `VkClass`, and the remaining
string or symbol arguments must match the aspect parameter count.

Current semantics:

- class method application mutates `class.methods[method].callable` in place;
- each mapped method is replaced with a `VkInterception` wrapper;
- the method's previous callable is stored as the interception's `original`, so
  applying another aspect creates nested wrappers rather than a single global
  aspect list;
- the return value is an array of the created `VkInterception` values, which can
  later be passed to the per-interception toggle APIs.

### Function application: `.apply-fn`

`(A .apply-fn inc "f")` returns a `VkInterception` wrapper around a standalone
function, native function, or existing interception. The receiver must be a
`VkAspect`; the function argument must be `VkFunction`, `VkNativeFn`, or
`VkInterception`; and the parameter name must be one of the aspect's declared
parameters.

This means function-level AOP is implemented through explicit wrapper values:

```gene
(fn inc [x] (x + 1))
(var wrapped (A .apply-fn inc "f"))
(wrapped 4)
```

The original function binding is not changed by `.apply-fn`; callers must use
the returned wrapper if they want interception.

### Per-interception toggles

`(A .disable-interception interception)` and
`(A .enable-interception interception)` toggle the `active` flag on a specific
`VkInterception`. The interception must belong to the aspect receiver. When an
interception is inactive, dispatch calls the stored original callable directly.

These APIs are per wrapper. They are not a global aspect-level toggle.

## Runtime data model

AOP is represented with two public runtime value kinds and several supporting
objects.

| Runtime object | Role |
| --- | --- |
| `Aspect` | Stores the aspect name, parameter names, advice tables, single `around` advice table, `before_filter` table, and internal enabled flag. |
| `AopAfterAdvice` | Stores an after-advice callable plus `replace_result` and `user_arg_count`, which decide whether the current result is appended and whether the advice result replaces it. |
| `Interception` | Stores `original`, `aspect`, `param_name`, and `active`. This is the wrapper that dispatch recognizes. |
| `AopContext` | Captures wrapped callable state during intercepted execution: wrapped value, instance, positional args, keyword pairs, around-call state, caller frame, handler depth, and escape state. |
| `VkAspect` | The `ValueKind` used for aspect definitions. `Reference` stores the `aspect` payload for this arm. |
| `VkInterception` | The `ValueKind` used for applied wrappers. `Reference` stores the `interception` payload for this arm. |

The compiler deliberately keeps `(aspect ...)` out of the regular symbol-call
fast path. That lets the runtime treat it as a native macro that receives the
unevaluated advice definitions and registers the resulting `VkAspect` in the
caller namespace.

At call time, VM call paths recognize `VkInterception` as callable. Dispatch
then:

1. calls the stored original directly when `active` is false;
2. reads the referenced `Aspect` and the mapped `param_name`;
3. pushes an `AopContext` for around/caller-state handling;
4. runs enabled filters and advice around the original callable; and
5. pops the context before returning.

A nested aspect chain is just nested `VkInterception` values: an interception's
`original` may itself be another interception.

## Verification map

The following fixtures are the current tracked proof set for behavior that can
be marked verified after the focused testsuite command passes:

| Fixture | Behavior covered |
| --- | --- |
| `testsuite/07-oop/oop/2_aop_aspects.gene` | Class method application, multiple `before` advice entries, `after` result handling, `before_filter` skip, `around` wrapped method call, and self binding. |
| `testsuite/07-oop/oop/4_aop_invariants.gene` | Invariant ordering, before-filter short circuit, around advice, after advice, and escaped-call behavior for a throwing method. |
| `testsuite/07-oop/oop/6_aop_chaining.gene` | Nested class-method wrappers and per-interception disable behavior. |
| `testsuite/05-functions/functions/6_aop_functions.gene` | `.apply-fn` wrapper behavior for standalone functions with before/around/after advice. |
| `testsuite/07-oop/oop/5_aop_callable_advices.gene` | Advice entries that resolve to existing Gene or native callables. |

This page should only label behavior as verified when one of those fixtures, or
a later tracked fixture, proves it.

## Unsupported and stale design-era surfaces

The following items are not current supported public AOP behavior. They are kept
here only so maintainers can recognize stale proposal language and avoid copying
it into examples.

- `fn_aspect` is stale; current definitions use `(aspect ...)`.
- `.apply_in_place` is stale; class `.apply` mutates method callables in place,
  while `.apply-fn` returns an explicit wrapper for standalone functions.
- Constructor/destructor/exception join-point wording from the old proposal is
  unsupported; the registered advice forms are `before`, `before_filter`,
  `invariant`, `around`, and `after`.
- Global aspect `(A .disable)` and `(A .enable)` examples are stale; current
  public toggles are per-interception APIs.
- Regex/selector method matching is unsupported by the registered `.apply`
  implementation, which expects concrete method names as strings or symbols.
- Async advice isolation, unapply/reset, priority controls, and broad ordering
  policy beyond the current tables and wrapper nesting remain unproven.
- The old note saying "No function-level AOP" or "only instance methods" is
  stale; `.apply-fn` implements explicit standalone function wrappers.
- Any stable-core status claim is unsupported until a later decision explicitly
  changes the feature-status boundary.

## S02 proof candidates

S02 should decide whether the following code-present or suspected behaviors are
verified, unsupported, or in need of a narrow patch:

- `.enable-interception` positive and negative paths;
- malformed `.apply` and `.apply-fn` inputs, including wrong receiver, missing
  class/function, unknown parameter, and mismatched method count;
- keyword-argument boundaries for intercepted methods and standalone functions;
- chaining `.apply-fn` around an existing `VkInterception`;
- macro-like around advice caller-context behavior;
- advice-thrown error behavior and whether post-call advice is skipped; and
- callable advice lexical capture.

Until that proof exists, keep/remove/defer remains open.
