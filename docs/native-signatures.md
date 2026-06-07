# Native Signatures

Status: Beta current reference. Design-era context lives in
[`docs/proposals/implemented/type-annotations.md`](proposals/implemented/type-annotations.md).

Native signatures attach Gene type metadata to host `NativeFn` values so native
functions, constructors, and methods participate in the same typed boundary
model as Gene callables. The implementation uses `NativeSignature` records with
`CallableParamDesc`, `TypeId`, return metadata, ABI tags, and `receives_self`
metadata.

## Current Surfaces

- Nim registration can pass `native_sig("[n: Int] -> Int")` or a constructed
  `NativeSignature` to native method and constructor registration helpers.
- Gene declarations can bind an existing native value at the declaration site:
  `(fn f [n: Int] -> Int ^native nativeImpl)`, `(ctor ... ^native ...)`, and
  `(method ... ^native ...)`.
- Retrofit forms attach signatures to already-registered callables:
  `$assign-type`, `$assign-method-type`, and `$assign-ctor-type`. Bang forms
  (`$assign-type!`, `$assign-method-type!`, `$assign-ctor-type!`) explicitly
  override an existing non-matching signature.
- `--strict-native-types` rejects calls to native callables that do not have a
  non-`Any` signature. An all-`Any` signature still counts as untyped for this
  gate.
- Reflection exposes user and native callables through the same `.signature`,
  `.params`, and `.return_type` shape.

## Boundary Behavior

When VM type checking is enabled, native signatures validate arguments before
the host call and validate the return value after it. Diagnostics identify the
phase (`argument` or `return`) and the blame side (`caller` or `native`).

The static checker also consumes native signatures for standalone native
functions, constructors, binding-site `^native` declarations, and methods. This
static path is gradual and advisory; runtime validation remains authoritative at
the native boundary.

For methods, the receiver is implicit in Gene source and explicit in native ABI
metadata. The stored signature has `receives_self = true` and prefixes the ABI
argument list with the receiver value, while reflection hides that receiver from
the user-facing parameter list.

## Supported Types And Limits

Native signatures use the normal Gene declaration grammar. Built-in and named
Gene types can be recorded as `TypeId` metadata, but generic native signatures
with type variables are rejected until native generic semantics are designed.

The dynamic C ABI subset is narrower than general native signature metadata. For
cdecl dynamic bindings, v1 supports `Int`, `Bool`, `String`, and `Pointer`
parameters; `Int`, `Bool`, `String`, `Pointer`, and `Void` returns; and at most
seven C arguments. `Float`, composites, varargs, callbacks, structs, and broad
ownership annotations remain future work.

## Verification

The current surface is covered by `tests/test_native_signatures.nim`,
`tests/test_native_trampoline.nim`, and
`tests/integration/test_strict_nil_cli.nim`.
