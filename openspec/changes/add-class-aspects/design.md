## Context
The implementation started under the `add-class-aspects` change id, then M005 narrowed the surface to explicit runtime interception after legacy AOP compatibility removal. M009 promotes that narrowed surface to Beta, and D057 keeps the same change id so prior validation history remains connected while the active capability delta becomes the durable Beta explicit-interception contract.

Explicit interception uses one shared runtime interception engine for both class method wrappers and standalone callable wrappers. The public surface is concrete: users define an interceptor, apply it directly to explicit targets, call returned wrappers or intercepted methods with normal Gene call syntax, and control advice execution with slash toggle methods.

## Goals

- Make `(interceptor ...)` and direct class application the Beta class interception path.
- Make `(fn-interceptor ...)` and direct callable wrapper application the Beta function interception path.
- Specify returned wrapper support for positional arguments, keyword arguments, positional spread, and keyword spread.
- Specify advice keyword matcher binding through normal Gene function parameter syntax.
- Specify that `around` advice receives the wrapped callable last and forwards by calling that wrapped callable normally.
- Keep legacy broad AOP spellings removed from the public runtime surface.
- Specify the implemented advice forms, enablement levels, diagnostics, and class application atomicity.
- Name unsupported async, macro-style, broad pointcut, and other non-core boundaries as deferred outside the Beta contract.

## Non-Goals

- Promote interception to Stable Core.
- Add public pointcuts, constructor/destructor join points, regex selectors, priority controls, reset/unapply controls, exception join points, or async advice isolation.
- Promise async target wrapping, macro-transparent wrapping, or every possible callable shape.
- Preserve legacy `(aspect ...)`, `.apply`, `.apply-fn`, `.enable-interception`, or `.disable-interception` compatibility.

## Runtime Model

### Definitions

`(interceptor Name [targets] ...)` defines a class interceptor value whose target placeholders are mapped to concrete class method names at application time. `(fn-interceptor Name [target])` defines a standalone callable interceptor value for one callable target.

Both definition forms support the same advice vocabulary: `before_filter`, `before`, `invariant`, `around`, and `after`. Advice may be inline Gene code or a symbol that resolves to an existing callable at definition time. `after` may use `^^replace_result` to replace the result returned to the caller.

### Class application

Calling a class interceptor value directly with a class and one method mapping per target installs wrappers on the selected class methods and returns an array of wrapper applications. The helper validates target type, mapping arity, mapping names, method existence, unsupported keyword application options, and unsupported macro-style targets before mutating class methods. If any mapping is invalid, the application fails atomically and leaves previously listed methods unwrapped.

Once installed, intercepted class methods preserve the expanded call shape produced by normal Gene calls. Positional arguments, keyword arguments, positional spread, and keyword spread reach advice and the wrapped method as the expanded positional values and keyword pairs.

### Function application

Calling a function interceptor value directly with exactly one callable target returns one callable wrapper. The original function binding is not mutated; callers must invoke the returned wrapper when they want advice to run. Ordinary Gene callables, native callables, callables with keyword parameters, and existing interception wrappers are valid targets when the target can be called through the normal wrapper path. Unsupported targets and keyword options on the direct application itself are rejected or deferred with targeted diagnostics.

Returned function wrappers preserve the expanded call shape produced by normal Gene calls. Callers can invoke returned wrappers with positional arguments, keyword arguments, positional spread, and keyword spread when the wrapped callable supports those forms.

### Advice binding and around forwarding

Inline advice uses normal Gene parameter binding for the wrapped call shape, including positional parameters, keyword parameters, and supported keyword defaults. Callable advice references follow the same binding convention for their advice kind, with helper callables receiving the receiver slot first where applicable.

`around` receives the wrapped callable as its final argument. Inline and helper `around` advice delegates by calling that wrapped callable with ordinary Gene call syntax, including positional spread or keyword spread when the wrapped callable supports those arguments. Legacy apply helpers are not part of the forwarding contract.

### Enablement controls

Definition-level `Name/.disable` and `Name/.enable` toggle all applications of an interceptor definition. Application-level `wrapper/.disable` and `wrapper/.enable` toggle only that returned wrapper. Advice runs only when both levels are enabled. In wrapper chains, disabling one wrapper bypasses only that wrapper while preserving active outer or inner wrappers.

### Diagnostics

Invalid applications raise catchable diagnostics containing `GENE.INTERCEPT` markers. The current marker families cover class targets, mapping arity, mapping names, missing methods, function arity, function targets, unsupported keyword options on direct application, unsupported macro-style boundaries, and unsupported async boundaries. Human-readable messages may improve over time, but marker families are the visible contract.

## Legacy AOP Removal

Legacy `(aspect ...)`, `.apply`, `.apply-fn`, `.enable-interception`, and `.disable-interception` are no longer public compatibility surfaces. Existing programs using those spellings must migrate to explicit definitions, direct callable application, returned wrappers or intercepted methods, and slash enablement controls.

## Risks / Trade-offs

- Keeping the old change id can confuse readers unless the proposal clearly states that the active capability is Beta explicit interception; this document and the delta make that continuity explicit.
- Promoting the narrowed surface to Beta while retaining unsupported boundaries is useful for users, but it requires the docs and public-surface guard to keep direct application keyword options, async targets, macro targets, and broad AOP features out of the supported contract.
- Removing legacy compatibility breaks old AOP programs, but it leaves Gene with one public interception model and eliminates stale public syntax.
- Supporting keyword and spread wrapper calls expands the Beta contract beyond the earlier narrow boundary, but it matches the implemented focused fixtures without promising macro transparency or stable-core status.
