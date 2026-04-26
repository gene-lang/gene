## Context
The implementation started under the `add-class-aspects` change id, but M005 narrowed the supported Experimental surface to explicit runtime interception. Per D027, the change id is retained so prior validation history remains connected, while the capability delta and public wording now describe the supported class and function interception APIs after legacy AOP compatibility removal.

Explicit interception uses one shared runtime interception engine for both class method wrappers and standalone callable wrappers. The public surface is concrete: users define an interceptor, apply it directly to explicit targets, and control advice execution with slash toggle methods.

## Goals

- Make `(interceptor ...)` and direct class application the current class interception path.
- Make `(fn-interceptor ...)` and direct callable wrapper application the current function interception path.
- Remove legacy broad AOP spellings from the public runtime surface.
- Specify the implemented advice forms, enablement levels, diagnostics, and class application atomicity.
- Name unsupported keyword, async, macro-style, and broad pointcut boundaries as deferred.

## Non-Goals

- Promote interception to Stable Core or Beta.
- Add public pointcuts, constructor/destructor join points, regex selectors, priority controls, reset/unapply controls, or exception join points.
- Promise keyword argument wrapping, async target wrapping, or macro-transparent wrapping.
- Preserve legacy `(aspect ...)`, `.apply`, `.apply-fn`, `.enable-interception`, or `.disable-interception` compatibility.

## Runtime Model

### Definitions

`(interceptor Name [targets] ...)` defines a class interceptor value whose target placeholders are mapped to concrete class method names at application time. `(fn-interceptor Name [target])` defines a standalone callable interceptor value for one callable target.

Both definition forms support the same advice vocabulary: `before_filter`, `before`, `invariant`, `around`, and `after`. Advice may be inline Gene code or a symbol that resolves to an existing callable at definition time. `around` receives a wrapped callable as its final argument and delegates by calling that wrapper. `after` may use `^^replace_result` to replace the result returned to the caller.

### Class application

Calling a class interceptor value directly with a class and one method mapping per target installs wrappers on the selected class methods and returns an array of wrapper applications. The helper validates target type, mapping arity, mapping names, method existence, unsupported keyword application, and macro-style targets before mutating class methods. If any mapping is invalid, the application fails atomically and leaves previously listed methods unwrapped.

### Function application

Calling a function interceptor value directly with exactly one callable target returns one callable wrapper. The original function binding is not mutated; callers must invoke the returned wrapper when they want advice to run. Ordinary Gene callables, native callables, and existing interception wrappers are valid targets. Classes, scalar values, native macros, `fn!` macro-style callables, keyword-parameter functions, async functions, and keyword application are rejected or deferred with targeted diagnostics.

### Enablement controls

Definition-level `Name/.disable` and `Name/.enable` toggle all applications of an interceptor definition. Application-level `wrapper/.disable` and `wrapper/.enable` toggle only that returned wrapper. Advice runs only when both levels are enabled. In wrapper chains, disabling one wrapper bypasses only that wrapper while preserving active outer or inner wrappers.

### Diagnostics

Invalid applications raise catchable diagnostics containing `GENE.INTERCEPT` markers. The current marker families cover class targets, mapping arity, mapping names, missing methods, function arity, function targets, unsupported keyword boundaries, unsupported macro-style boundaries, and unsupported async boundaries. Human-readable messages may improve over time, but marker families are the visible contract.

## Legacy AOP Removal

Legacy `(aspect ...)`, `.apply`, `.apply-fn`, `.enable-interception`, and `.disable-interception` are no longer public compatibility surfaces. Existing programs using those spellings must migrate to explicit definitions, direct callable application, and slash enablement controls.

## Risks / Trade-offs

- Keeping the old change id can confuse readers unless the proposal clearly states that the active capability is explicit interception; this document and the delta make that continuity explicit.
- Removing legacy compatibility breaks old AOP programs, but it leaves Gene with one public interception model and eliminates stale public syntax.
- Naming unsupported keyword, async, and macro-style boundaries narrows the current contract, but it prevents users from treating broad AOP behavior as supported.
