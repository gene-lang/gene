@user:
we want to support efficient pattern matching

the value will be values stored in the vm stack as UncheckedArray<Value>
when pattern matching, we know the length of the array and whether there is a properties map.

The reason we use UncheckedArray is to avoid allocation.

Stack: [f 1 2]
The values to match will be [1 2] on the stack

Stack: [f ^p 1 2 3]
The value to match will be [{^p 1} 2 3], with properties flag set to true

Stack: [f ^p 1]
The value to match will be [{^p 1}], with properties flag set to true

The pattern matching should be useful for destructuring values inside a function body.
(match [a b] arr) # arr = [1 2]
in this case, arr is a single value on the stack. how can we unify the design?

We need to make sure the values are garbage collected correctly and the staci pointer is correctly updated.

@Codex:
## Current plan

- Keep the pointer-based idea (`ptr UncheckedArray[Value]` into `process_args_direct`) as a future optimization; it needs new matcher infrastructure, an `IkMatch` instruction, and safety around pointer lifetime.
- Ship a working compile-time expansion first (destructuring lowered to bytecode), then profile before investing in the pointer path.

## Known gaps (code as of 2025-11-21)

- `compile_match` lowers array patterns via `IkGetMember` with integer payloads; the VM only supports named members there, so `(match [a b] arr)` crashes. Use `IkGetChild`/`IkGetChildDynamic` or a dedicated destructuring helper instead.
- No arity/shape validation: short/long inputs bind out-of-bounds indices; decide the contract (error vs. NIL padding) and match function-arg behavior.
- Scope handling is unsafe: array patterns assume an active scope; add the guard/ScopeStart/ScopeEnd pairing seen in the symbol path.

## Immediate actions

1) Fix `compile_match` to use child access with explicit scope setup and length checks.  
2) Add map/nested/rest pattern coverage for the compile-time path.  
3) Create tests for mismatched arity, top-level `match`, and map patterns.  
4) Revisit the pointer-based matcher only after profiling shows a bottleneck and after adding the required VM/compiler support.
