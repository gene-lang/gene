## Why
Gene needs class-level AOP to attach before/after/before_filter/around behavior to methods at runtime while preserving method call semantics and enabling cross-cutting concerns.

## What Changes
- Introduce a class-aspect capability with `(aspect ...)` definition and `(Aspect.apply ...)` runtime application.
- Intercept method calls to run before/after/before_filter/around/invariant advices with implicit `self` and method args.
- Apply aspects in place to class methods using the mapping supplied to `apply`.

## Impact
- Affected specs: class-aspects (new capability)
- Affected code: parser/compiler for `aspect`, stdlib macro, VM dispatch/interception, types for aspect/interception values
