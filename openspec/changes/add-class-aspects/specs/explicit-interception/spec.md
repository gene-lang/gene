## ADDED Requirements

### Requirement: Define class interceptors
The system SHALL allow defining a class interceptor with `(interceptor <Name> [<target>...])` and one or more advice entries for the named target placeholders.

#### Scenario: Define a class interceptor with advice
- **WHEN** a user evaluates `(interceptor Audit [run] (before run [x] (println x)) (after run [x result] result))`
- **THEN** `Audit` is bound to an enabled class interceptor value in the current namespace
- **AND** the `run` placeholder can be mapped to a concrete class method at application time.

### Requirement: Apply class interceptors explicitly
The system SHALL apply a class interceptor by directly calling the interceptor value with a class followed by one method name for each declared target placeholder.

#### Scenario: Direct class application returns wrappers
- **WHEN** a class interceptor with two target placeholders is called as `(Audit Service "run" "stop")`
- **THEN** the selected class methods are wrapped for interception
- **AND** the call returns an array containing one callable wrapper application for each mapped method
- **AND** unlisted class methods remain unchanged.

#### Scenario: Class application validates mapping arity
- **WHEN** a class interceptor application supplies fewer or more method names than the interceptor target count
- **THEN** the application fails before installing wrappers
- **AND** the diagnostic message includes the `GENE.INTERCEPT.MAPPING_ARITY` marker.

#### Scenario: Class application rejects keyword options
- **WHEN** a class interceptor is called with keyword options during direct application
- **THEN** the application fails
- **AND** the diagnostic message includes the `GENE.INTERCEPT.KEYWORD_UNSUPPORTED` marker.

### Requirement: Define function interceptors
The system SHALL allow defining a standalone callable interceptor with `(fn-interceptor <Name> [<target>])` and advice entries for the target placeholder.

#### Scenario: Define a function interceptor with advice
- **WHEN** a user evaluates `(fn-interceptor Trace [f] (before f [x] (println x)) (after f [x result] result))`
- **THEN** `Trace` is bound to an enabled function interceptor value in the current namespace
- **AND** the `f` placeholder can be applied to a concrete callable target.

### Requirement: Apply function interceptors explicitly
The system SHALL apply a function interceptor by directly calling the interceptor value with exactly one callable target, returning a callable wrapper without mutating the original callable binding.

#### Scenario: Direct function application returns a callable wrapper
- **WHEN** `(Trace inc)` is evaluated and `inc` is an ordinary callable
- **THEN** the call returns an interception wrapper that can be invoked like a function
- **AND** invoking the wrapper runs enabled advice around `inc`.

#### Scenario: Original function remains unchanged
- **WHEN** a function interceptor wraps `inc` and stores the returned wrapper in `wrapped_inc`
- **THEN** calls to `wrapped_inc` run through the wrapper
- **AND** direct calls to `inc` continue to call the original function without advice.

#### Scenario: Function application accepts existing wrappers
- **WHEN** a function interceptor is applied to an existing interception wrapper
- **THEN** the system returns a new callable wrapper around that target
- **AND** each wrapper in the chain keeps its own enablement state.

#### Scenario: Function application rejects invalid arity
- **WHEN** a function interceptor is called with zero targets or more than one target
- **THEN** the application fails
- **AND** the diagnostic message includes the `GENE.INTERCEPT.FN_ARITY` marker.

### Requirement: Execute supported advice forms
The system SHALL support `before_filter`, `before`, `invariant`, `around`, and `after` advice for explicit class and function interceptors, with inline bodies or callable advice references resolved at definition time.

#### Scenario: Before filter aborts invocation
- **WHEN** a `before_filter` advice returns a falsey value
- **THEN** the wrapped callable is not invoked
- **AND** later `before`, `invariant`, and `after` advice for that call is skipped.

#### Scenario: Before and after advice run in declaration order
- **WHEN** multiple `before` or `after` advice entries are declared for the same target
- **THEN** enabled wrapper calls execute those entries in declaration order around the wrapped callable.

#### Scenario: Invariant advice surrounds non-escaped calls
- **WHEN** invariant advice is declared and the wrapped callable completes normally
- **THEN** invariant advice runs before the around/original call and again after that call, before any `after` advice.

#### Scenario: Around advice receives a wrapped callable
- **WHEN** an `around` advice is configured for a target
- **THEN** it receives the wrapped callable as its final argument
- **AND** calling that wrapped callable delegates to the next wrapper or original callable.

#### Scenario: After advice may replace the result
- **WHEN** an `after` advice is marked with `^^replace_result`
- **THEN** the advice return value replaces the wrapped callable result returned to the caller.

#### Scenario: Callable advice references are invoked
- **WHEN** advice is declared by referencing an existing Gene or native callable
- **THEN** enabled wrapper calls invoke that advice callable with the same argument convention as inline advice for that advice kind.

### Requirement: Control interception enablement explicitly
The system SHALL expose `/.enable` and `/.disable` controls on interceptor definitions and returned wrapper applications, and advice SHALL run only when both the definition and application levels are enabled.

#### Scenario: Definition-level disable bypasses all applications
- **WHEN** `Trace/.disable` is evaluated for an interceptor definition
- **THEN** every wrapper created from `Trace` bypasses that definition's advice
- **AND** `Trace/.enable` restores advice execution for enabled applications.

#### Scenario: Application-level disable bypasses one wrapper
- **WHEN** `wrapped/.disable` is evaluated for one returned wrapper
- **THEN** calls through that wrapper bypass only that wrapper's advice
- **AND** `wrapped/.enable` restores advice execution when the definition is also enabled.

#### Scenario: Wrapper chains remain local
- **WHEN** one wrapper in a chain is disabled
- **THEN** only that wrapper is bypassed
- **AND** active outer or inner wrappers keep their own advice behavior.

### Requirement: Report targeted diagnostics and preserve class application atomicity
The system SHALL reject invalid explicit interception applications with catchable diagnostics whose messages include `GENE.INTERCEPT` marker families, and class interceptor application SHALL validate all requested mappings before mutating any class method.

#### Scenario: Non-class class target is rejected
- **WHEN** a class interceptor is applied to a scalar or other non-class target
- **THEN** the application fails
- **AND** the diagnostic message includes the `GENE.INTERCEPT.CLASS_TARGET` marker.

#### Scenario: Missing class method is rejected atomically
- **WHEN** a class interceptor maps one valid method and one missing method in the same application
- **THEN** the application fails with the `GENE.INTERCEPT.MISSING_METHOD` marker
- **AND** the valid method remains unwrapped after the failure.

#### Scenario: Invalid class mapping name is rejected
- **WHEN** a class interceptor mapping is not a string or symbol method name
- **THEN** the application fails
- **AND** the diagnostic message includes the `GENE.INTERCEPT.MAPPING_NAME` marker.

#### Scenario: Invalid function target is rejected
- **WHEN** a function interceptor is applied to a class, scalar value, or other non-callable target
- **THEN** the application fails
- **AND** the diagnostic message includes the `GENE.INTERCEPT.FN_TARGET` marker.

#### Scenario: Unsupported macro-style targets are rejected
- **WHEN** direct explicit application receives a native macro or `fn!` macro-style target that cannot preserve wrapping semantics
- **THEN** the application fails
- **AND** the diagnostic message includes the `GENE.INTERCEPT.MACRO_UNSUPPORTED` marker.

#### Scenario: Unsupported async targets are rejected
- **WHEN** direct function interception receives an async function target
- **THEN** the application fails
- **AND** the diagnostic message includes the `GENE.INTERCEPT.ASYNC_UNSUPPORTED` marker.

### Requirement: Remove legacy AOP public compatibility
The system SHALL reject legacy AOP public definition and application forms and SHALL keep explicit interception as the only current interception API.

#### Scenario: Legacy aspect definition is rejected
- **WHEN** a Gene program evaluates the historical AOP definition form
- **THEN** the program fails instead of binding a legacy aspect definition
- **AND** the failure does not install any interception wrapper.

#### Scenario: Legacy class application method is unavailable
- **WHEN** a Gene program tries to apply interception with a historical dot class application helper
- **THEN** the program fails instead of using a compatibility path
- **AND** the class method table remains unchanged.

#### Scenario: Legacy function application method is unavailable
- **WHEN** a Gene program tries to apply interception with a historical dot function application helper
- **THEN** the program fails instead of returning a compatibility wrapper
- **AND** the original callable binding remains unchanged.

#### Scenario: Legacy toggle methods are unavailable
- **WHEN** a Gene program calls historical interception toggle method names on an interceptor definition or wrapper
- **THEN** the call fails instead of mutating interception enablement state.

### Requirement: Defer unsupported interception boundaries
The system SHALL document keyword, async, macro-style, broad pointcut, constructor/destructor, exception join point, regex selector, priority, reset/unapply, and async advice isolation boundaries as unsupported or deferred for the current Experimental surface.

#### Scenario: Keyword function boundaries are not supported
- **WHEN** a function interceptor is applied with keyword arguments or to a keyword-parameter function target
- **THEN** the system rejects the application boundary
- **AND** the diagnostic message includes the `GENE.INTERCEPT.KEYWORD_UNSUPPORTED` marker.

#### Scenario: Legacy macro-style wrapping is not macro-transparent
- **WHEN** legacy compatibility wrapping is used around a macro-style callable
- **THEN** the behavior is treated as migration compatibility only
- **AND** the current explicit interception contract does not promise macro-transparent wrapping.

#### Scenario: Broad pointcut features are not current behavior
- **WHEN** users need pointcuts, constructor/destructor interception, exception join points, regex selector matching, priority controls, or reset/unapply controls
- **THEN** those capabilities require future design and validation
- **AND** they are not part of the current explicit interception capability.
