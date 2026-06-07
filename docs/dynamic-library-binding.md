# Dynamic Library Binding

Status: Beta current reference. Design-era context lives in
[`docs/proposals/implemented/dynamic-library-binding.md`](proposals/implemented/dynamic-library-binding.md).

Dynamic library binding lets Gene code open a trusted C ABI dynamic library,
resolve a symbol, and use that symbol as the implementation of a normal Gene
function, constructor, or method.

## Surface

```gene
(var lib ($dyn/load "curl"))

(fn curl-easy-perform [h: Pointer] -> Int
  ^native ($dyn/find lib "curl_easy_perform")
  ^abi "cdecl")
```

- `($dyn/load path)` opens a dynamic library and returns an opaque handle value.
  Full filenames are accepted. Bare names infer platform candidates such as
  `.dylib`, `.so`, or `.dll`.
- `($dyn/find lib "symbol")` resolves a symbol from a `$dyn/load` handle and
  returns an opaque dynamic symbol value. The symbol is not callable by itself.
- `^native ($dyn/find ...)` turns the symbol into a Gene-compatible native
  callable for the surrounding `fn`, `ctor`, or `method` declaration.
- `^abi` defaults to `"cdecl"`; v1 rejects other ABI names and rejects `^abi`
  without a matching `^native` declaration.
- WASM builds reject dynamic loading with the documented unsupported-feature
  error rather than attempting host library access.

## ABI V1

The v1 cdecl trampoline supports a deliberately small manual FFI subset:

| Gene type | C ABI role |
|-----------|------------|
| `Int` | integer-sized argument or return |
| `Bool` | `0`/`1` argument, low-byte zero/non-zero return |
| `String` | temporary NUL-terminated `const char*` argument, borrowed NUL-terminated `const char*` return copied into Gene |
| `Pointer` | opaque `void*` argument or return |
| `Void` | return only |

The runtime rejects unsupported declarations at binding time. Unsupported v1
features include `Float`/`double`, `Any`, composites, generic dynamic
signatures, keyword/rest parameters, varargs, callbacks, structs by value, and
functions with more than seven C arguments.

`Pointer` is opaque in Gene. Code can pass it between dynamic bindings and
compare pointer values, but cannot dereference, offset, or mutate pointed memory
directly. A dynamic constructor that returns `Pointer` is wrapped as a
class-backed opaque value so dynamic methods can receive it as their C `void*`
receiver.

Dynamic methods always pass the receiver as the first C `void*` argument. In v1,
that means dynamic methods are for Pointer-backed wrapper values, usually values
created by a dynamic constructor returning `Pointer`; ordinary Gene instances are
not marshalable as dynamic method receivers.

Returned `String` values are copied from borrowed NUL-terminated C strings. Gene
does not take ownership of the original pointer and does not call a free
function for it.

## Lifetime And Safety

Dynamic native callables retain the originating `$dyn/load` handle, so the
library stays loaded while the callable exists. There is no public unload API in
v1.

Gene validates the declared argument and return types it knows about, but a
wrong C signature is still a native memory-safety bug. Use dynamic bindings only
for trusted local libraries with stable documented C ABIs. Prefer `gene_init`
extensions when a library is Gene-aware and wants to publish a full namespace,
classes, ports, or host-managed resources.

## Verification

The current surface is covered by `tests/test_dynamic_binding.nim` and the C
fixture in `tests/dyn_binding.c`.
