## Overview
Class aspects are defined in Gene using `(aspect ...)` and applied in place via `(Aspect.apply <Class> <method...>)`. The VM intercepts method calls by replacing target methods with an interception wrapper that executes advice lists and then invokes the original method.

## Key Types
- `Aspect`: holds name, parameter placeholders, advice tables, enabled flag.
- `Interception`: holds original callable, aspect instance, and placeholder name used to lookup advice lists.

## Execution Model
1. `(aspect ...)` expands to a native macro that builds an `Aspect` value and stores it in the caller namespace.
2. `(Aspect.apply C "m1" "m2")` maps placeholders to concrete method names and replaces each method callable with a `VkInterception` wrapper.
3. VM method dispatch detects `VkInterception` and:
   - Executes `before_filter` advices in order; any falsy return aborts invocation and returns NIL.
   - Executes `before` advices in order (FIFO).
   - Executes `invariant` advices in order (FIFO) immediately before the around/original call.
   - Executes the original method (Gene or native) with implicit `self` and args.
   - Executes `invariant` advices in order (FIFO) immediately after the around/original call.
   - Executes `after` advices in order (FIFO), passing the same args plus the return value as the final argument; `after` can be marked with `^^replace_result` to replace the return value with the advice result.
   - If an `around` advice is configured, it receives `self`, args, and a wrapped bound method; invoking `(wrapped ...)` executes the original method.

## Argument Conventions
- Advices are methods with implicit `self` as the first argument, matching method semantics.
- The advice argument matcher is built from the `[args...]` list in the aspect definition.

## VM Integration
- Interceptions are checked in unified method call paths (0/1/2/varargs/keyword/selector) to ensure consistency.
- Return value propagation is handled so `after` advice runs for both native and Gene methods.
- Invariant advices are skipped entirely when `before_filter` aborts; post-invariants do not run if the around/original call raises.

## Non-Goals (v1)
- Function aspects.
- Dynamic enable/disable per instance.
- Asynchronous advice execution.
