## Why
Gene is currently dynamically typed, which blocks AI-oriented tooling, contracts, and reliable static reasoning. A static type system is the foundation for the AI-first roadmap and enables predictable compilation and OOP validation.

## What Changes
- Add Gene-valid type expression syntax (e.g., `(Array T)`, `(Result T E)`, `(Fn [A B] R)` and unions).
- Add type annotations for variables, function params/returns, and class fields/methods.
- Introduce a type-checking phase that validates expressions, function calls, and class/member access.
- Define a nominal class typing model and typed member access.

## Impact
- Affected specs: new `type-system` capability
- Affected code: parser, compiler AST, new type-checker module, error reporting, testsuite
- **BREAKING**: type mismatches will become compile-time errors in type-check mode
