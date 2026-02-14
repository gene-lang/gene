## Why
Native methods in Gene currently expose only a raw `NativeFn` pointer, so the static type checker cannot validate native method arguments or infer native method return types. This weakens AI guidance and gradual typing around core stdlib calls.

## What Changes
- Add native method type metadata fields to `Method` (`native_param_types`, `native_return_type`).
- Add a typed `def_native_method` overload to register native method parameter and return type metadata.
- Update the type checker to consult native method metadata for known runtime classes when validating method calls.
- Annotate key stdlib native methods (String, Array, Map, Int, Float) with initial metadata.
- Add type tests covering native return-type awareness and method argument checking behavior.

## Impact
- Affected code:
  - `src/gene/types/type_defs.nim`
  - `src/gene/types/classes.nim`
  - `src/gene/type_checker.nim`
  - `src/gene/stdlib/strings.nim`
  - `src/gene/stdlib/collections.nim`
  - `src/gene/stdlib/classes.nim`
  - `testsuite/types/9_native_types.gene`
- Behavior change:
  - Type checker gains awareness of annotated native method signatures for known classes.
  - No breaking runtime behavior intended.
