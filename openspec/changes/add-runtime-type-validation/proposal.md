## Why
The static type checker infers types but runtime validation only understands simple type names, leaving unions, function types, and inferred bindings unenforced.

## What Changes
- Add runtime-compatible type expression handling (unions, function types, applied types).
- Propagate inferred binding types from the type checker into runtime validation.
- Extend runtime checks to enforce inferred/annotated types at assignment and call sites.

## Impact
- Affected specs: type-system
- Affected code: src/gene/type_checker.nim, src/gene/types/runtime_types.nim, src/gene/types/type_defs.nim, src/gene/compiler.nim, src/gene/vm.nim, src/gene/vm/args.nim
