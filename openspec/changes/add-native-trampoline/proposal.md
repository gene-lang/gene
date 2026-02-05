## Why
Native-compiled functions are currently limited to self-recursive calls. Any helper call makes the function ineligible for native code, which blocks meaningful native compilation for real programs.

## What Changes
- Add a trampoline that lets native-compiled code call back into the VM for arbitrary callables (Gene functions, native functions, bound methods).
- Introduce call descriptors and a hidden native context parameter to carry VM state and trampoline metadata.
- Emit `HokCallVM` for non-self calls when the callee is statically resolvable and fully typed.
- Expand `isNativeEligible` to allow non-self calls that satisfy the above constraints.
- Update x86-64 and ARM64 codegen to pass the hidden context and invoke the trampoline.

## Impact
- Affected specs: native-trampoline (new)
- Affected code: native compiler pipeline (HIR, bytecode_to_hir), native codegen (x86-64/ARM64), runtime call path (`try_native_call`)
- Behavior: more functions become native-eligible; untyped/dynamic calls remain VM-only
