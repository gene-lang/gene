## Why
The current class member forms `ctor` and `method` look like method calls, which is confusing and inconsistent with other keyword-based declarations. We want clear, explicit keywords for constructors and methods.

## What Changes
- Replace `ctor`/`ctor!` with `ctor`/`ctor!` keywords in class bodies (**BREAKING**).
- Replace `method` with the `method` keyword in class bodies; macro-like methods are declared via a trailing `!` in the method name (**BREAKING**).
- Keep `super` constructor calls in dotted form (`ctor`/`ctor!`) and reject bare `ctor` in `super` (**BREAKING**).
- Reject legacy dotted forms with clear compiler errors.
- Update docs, examples, and tests to the new syntax.

## Impact
- Affected specs: define-class-members
- Affected code: `src/gene/compiler.nim`, `src/gene/parser.nim`, `src/gene/vm.nim`, testsuite, `examples/`, `docs/`, `README.md`, `CLAUDE.md`
