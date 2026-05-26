# Dynamic Library Binding

## Motivation

Gene's native callables today are registered exclusively from Nim
(`src/gene/stdlib/*.nim`, `src/genex/*.nim`). To call into an arbitrary
C-ABI dynamic library — libc's `getenv`, libcurl, a vendored `.dylib`
shipped with an app — a developer must add Nim glue, recompile the runtime,
and re-link. There is no path from Gene source to a dlopen'd symbol.

The related `genex` extensions (`src/genex/llm.nim:1305`,
`src/genex/sqlite.nim:283`, etc.) are full-fledged Gene plug-ins implementing
the `gene_init`/`GeneHostAbi` protocol. That path stays supported: it is the
right model when a Nim or C extension wants to create a namespace, register
multiple Gene-compatible `NativeFn` values, classes, ports, or other host-aware
objects. Dynamic library binding is the lighter path for libraries that know
nothing about Gene.

This proposal adds a Gene-level surface for opening a dynamic library, finding
a foreign symbol, and using that symbol as the implementation pointer for a
normal Gene function, constructor, or method declaration.

## Target Libraries

The intended use case is wrapping stable, mature native libraries that expose a
documented C ABI: libcurl, SQLite, zlib, OpenSSL-style libraries, system APIs,
and vendored application libraries. The raw FFI layer should stay small and
explicit; idiomatic Gene APIs should be written as normal Gene modules and
classes on top of those raw bindings.

C++ libraries are in scope only when they expose, or can be given, an
`extern "C"` facade:

```cpp
extern "C" MyHandle* mylib_create();
extern "C" void mylib_destroy(MyHandle*);
extern "C" int mylib_do_work(MyHandle*, const char*);
```

Gene then binds the facade functions as ordinary C ABI symbols. Direct arbitrary
C++ ABI binding is not a goal for this proposal because C++ adds name mangling,
overloads, templates, constructors/destructors, exceptions, vtables, move
semantics, and compiler-specific ABI differences.

## Non-Goals (v1)

- No structs by value (only by pointer).
- No callback closures (Gene fn → C function pointer); listed as Future Work.
- No varargs (e.g. `printf`); a fixed-arity adapter only.
- No functions with more than 7 arguments, matching the existing native-call
  dispatch cap.
- No `Float`/`double` ABI support in v1. The v1 trampoline uses
  integer/pointer-sized call slots only; floating-point ABI classes require
  libffi or type-correct per-signature dispatch.
- No automatic header parsing. Signatures are declared by hand.
- No ownership management for caller-owned returned strings or pointers.
  Returned `String` values are treated as borrowed C strings and copied.
- No direct arbitrary C++ ABI binding. Bind a C facade instead.
- No safety guarantees beyond arity + per-arg ABI tag agreement. A wrong
  type declaration is a memory-safety bug, full stop.

## Declaration Surface

```gene
(import Curl-Handle from "myapp/types")

(var libcurl ($dyn/load "curl"))   # the actual file will be inferred

(fn curl-easy-init [] -> Pointer
  ^native ($dyn/find libcurl "curl_easy_init")
  ^abi "cdecl")

(fn curl-easy-setopt [h: Pointer opt: Int v: Pointer] -> Int
  ^native ($dyn/find libcurl "curl_easy_setopt")
  ^abi "cdecl")

(fn curl-easy-perform [h: Pointer] -> Int
  ^native ($dyn/find libcurl "curl_easy_perform")
  ^abi "cdecl")

(fn curl-easy-cleanup [h: Pointer] -> Void
  ^native ($dyn/find libcurl "curl_easy_cleanup")
  ^abi "cdecl")

(class Curl-Handle
  (ctor [] -> Pointer
    ^native ($dyn/find libcurl "curl_easy_init")
    ^abi "cdecl")

  (method setopt [opt: Int v: Pointer] -> Int
    ^native ($dyn/find libcurl "curl_easy_setopt")
    ^abi "cdecl"))
```

- `($dyn/load path)` evaluates `dlopen`-equivalent resolution using the v1
  candidate rules below and returns a refcounted handle Value.
- `($dyn/find lib "symbol")` calls `symAddr` and returns an opaque native
  symbol pointer. It is not Gene-callable by itself.
- `fn`, `ctor`, and `method` declarations provide the Gene-facing name and
  signature. `^native` supplies the implementation pointer and `^abi` tells the
  compiler/runtime how to call it. `^abi` defaults to `"cdecl"` in v1.
- The signature grammar remains the normal Gene declaration grammar. There is
  no separate dynamic-binding signature syntax.

### Published Path Binding

Because the binding is a normal declaration, named functions, constructors, and
methods are published wherever that declaration would normally publish them.
No separate namespace creation step is required.

```gene
(var libcurl ($dyn/load "curl"))

(ns myapp/curl
  (fn easy-init [] -> Pointer
    ^native ($dyn/find libcurl "curl_easy_init")
    ^abi "cdecl")

  (fn easy-perform [h: Pointer] -> Int
    ^native ($dyn/find libcurl "curl_easy_perform")
    ^abi "cdecl")
)
```

Those declarations can then be referred to by ordinary slash paths such as
`myapp/curl/easy-init`.

Anonymous callable values are not a v1 goal. If a user wants a stable path, they
declare a function, method, or constructor in the appropriate module or class.

### Wrapper Pattern

Raw FFI declarations should usually live in a low-level namespace, with
application-facing Gene wrappers layered on top:

```gene
(var libcurl ($dyn/load "curl"))

(ns myapp/curl/raw
  (fn easy-init [] -> Pointer
    ^native ($dyn/find libcurl "curl_easy_init")
    ^abi "cdecl")

  (fn easy-cleanup [h: Pointer] -> Void
    ^native ($dyn/find libcurl "curl_easy_cleanup")
    ^abi "cdecl"))

(ns myapp/http
  (class Client
    (ctor []
      (/handle = (myapp/curl/raw/easy-init)))

    (method close [] -> Void
      (myapp/curl/raw/easy-cleanup /handle)
      (/handle = nil))))
```

This keeps ownership, error handling, and domain-specific ergonomics in Gene
code instead of baking every C convention into the raw FFI layer.

### Addressing Model

There are two levels of identity:

1. **Callable value** — a `VkNativeFn` value that can be called directly.
2. **Published path** — a slash-separated namespace path that points at a
   callable value.

A foreign C symbol is not Gene-compatible by itself. A declaration with
`^native ($dyn/find ...)` wraps it in a Gene-compatible `NativeFn` trampoline.
A Nim extension or C extension using `gene_init` can publish Gene-compatible
`NativeFn` values directly into a namespace. Once published, the language of
origin is intentionally invisible:

| Origin | Example path |
|---|---|
| Gene dynamic binding | `myapp/curl/easy_init` |
| Nim extension using `gene_init` | `genex/http/get` |
| C extension using `gene_init` | `genex/llm/infer` |
| User module function | `myapp/utils/slugify` |

Path strings are the canonical way to refer to published native functions by
name. Raw symbols returned by `$dyn/find` are intentionally not path-addressable
or callable until a declaration uses them as `^native`.

### `gene_init` Extensions Stay Supported

Dynamic binding does not replace the existing extension ABI.

Use `gene_init` when the native library is Gene-aware and wants to publish a
namespace:

```text
shared library exports gene_init(host)
gene_init creates or returns Namespace
host mounts that Namespace under genex/<extension-name>
```

Use `$dyn/load` + `$dyn/find` + `^native` declarations when the native library
is not Gene-aware and only exports ordinary C ABI symbols.

This keeps both extension models:

- **Plugin extension:** creates a namespace, may register many members, classes,
  ports, and host-aware resources through `gene_init`.
- **Foreign symbol binding:** opens a library and uses individual symbols as
  `^native` implementations for normal Gene declarations.

A new built-in type `Pointer` is added (slot 11 in
`src/gene/types/descriptors.nim:7-20`, paired with the existing `VkPointer`
value kind at `type_defs.nim:193`). Adding this slot also bumps
`BUILTIN_TYPE_COUNT` from 11 to 12.

## ABI Mapping (v1)

| Gene `TypeId` | C ABI | Marshalling |
|---|---|---|
| `Int` | `int64_t` | direct (Gene Ints are tagged 64-bit) |
| `Bool` | `bool` (zero-extended `int32`) | `0` / `1` |
| `String` | `const char*` | NUL-terminated copy; freed after call |
| `Pointer` | `void*` | raw `VkPointer` payload |
| `Void` (return only) | `void` | discard return register |
| `Any` | `void*` | rejected — must be made concrete in v1 |

Composite types (`Array`, `Map`, applied generics, user classes) are
rejected at declaration time. A struct-by-pointer wrapper class is the
documented workaround.

`Float` is intentionally excluded from v1. A real C `double` uses
architecture-specific floating-point argument and return registers; the v1
integer-slot trampoline cannot call such functions correctly. `Nil` remains a
Gene value-level absence marker, while `Void` maps to a C `void` return.

## Call Trampoline

The existing JIT marshalling path (`src/gene/vm/native.nim:148-200`) is
*not* directly reusable: it dispatches through `NativeFn0..NativeFn7` whose
first arg is a `NativeContext*`. Foreign cdecl procs have no such
parameter.

Add a parallel hand-rolled dispatch:

```nim
type
  CdeclFn0* = proc(): int64 {.cdecl, gcsafe.}
  CdeclFn1* = proc(a0: int64): int64 {.cdecl, gcsafe.}
  # ... CdeclFn2 .. CdeclFn7

proc make_dyn_native_fn*(lib: LibHandle, sym: pointer,
                         sig: NativeSignature): NativeFn
```

`NativeSignature` is introduced by the sibling `type-annotations.md` proposal.
If the implementation keeps the current `NativeFnSig` name instead
(`src/gene/native/trampoline.nim:15`), this proposal should use that concrete
type or provide a bridge.

When the compiler sees a declaration with `^native ($dyn/find ...)`, it records
the declaration signature and the `^native` expression. At declaration
execution time, the runtime evaluates `$dyn/load` / `$dyn/find`, builds or
retrieves the trampoline for the resolved symbol pointer, and stores the
generated trampoline as the callable body. The returned `NativeFn` is a regular
`VkNativeFn` body that:

1. Runs the argument validation helper defined by `type-annotations.md`
   (`validate_native_args` or the implemented equivalent).
2. Unboxes each `Value` into an `int64` slot per the v1 ABI mapping above.
3. Switches on `sig.params.len` and on return-ABI tag to call the right
   `CdeclFnN` cast. Mirrors the dispatch shape at `native.nim:187-200` but
   without the `NativeContext` first arg.
4. Reboxes the return register into a `Value` per `sig.return_type_id`.

For `String` parameters: stack-allocate a NUL-terminated copy (or
`alloca` for short strings, heap-fall-back over a threshold) and free
after the call returns. Returned `cstring`s are copied into a Gene `String`.
v1 treats the returned pointer as borrowed/static or owned by the callee. APIs
that return caller-owned strings must expose a native helper that frees the
original, or wait for future ownership annotations.

## Lifetime and Safety

- `$dyn/load` handles are refcounted Values. A `^native` callable retains its
  originating handle for the lifetime of the bound callable, so unloading
  is automatic when no Gene name still references either.
- `$dyn/find` failure (`symAddr` returns `nil`) raises a Gene exception
  with the symbol name and library path. No silent `nil` bindings.
- Signature mismatch is a runtime memory-safety problem. v1 accepts that
  and documents it; Future Work covers libffi-based defensive trampolines.
- Crossing the boundary disables JIT inlining for the call site
  (`NativeSignature.abi` is set, but `lookup_native_sig` only returns true
  for entries registered through `register_native_sig`; cdecl-bound fns
  stay out of that table).

## Open Questions

- None for v1. The decisions below are fixed for the initial implementation.

## V1 Decisions

- **Lib search rules:** `$dyn/load "curl"` infers platform-specific candidate
  names such as `libcurl.dylib`, `libcurl.so`, and `curl.dll`. The generic
  candidate-generation algorithm is new work, though it can reuse the
  candidate-style behavior already used by the existing loaders. Full filenames
  remain accepted.
- **Publishing policy:** no new publishing primitive is added in v1. Normal
  `fn`, `ctor`, and `method` declarations publish through the normal module or
  class machinery.
- **Pointer policy:** `Pointer` is opaque in v1. Gene code can pass pointer
  values between dynamic bindings, but it cannot add offsets, dereference
  memory, or read/write through the pointer directly.

Libraries that need pointer arithmetic or struct field access should expose
typed C or Nim helper functions and bind those helpers into Gene. This keeps the
unsafe memory logic behind a native boundary with a narrower Gene API.

## Direction After V1

v1 is a deliberately small manual binding layer. The path to Python-like FFI
power is not exposing libffi directly to Gene code; it is adding a Gene-level
type and ownership model, then using libffi underneath as the call engine.

The mature direction is:

1. Manual bindings for stable C ABI functions using `$dyn/load`, `$dyn/find`,
   and `^native`.
2. A libffi backend for broad C ABI coverage: floats, structs, callbacks,
   platform ABI differences, and eventually varargs.
3. A C type vocabulary: fixed-width integers, `size_t`, `CString`,
   `Pointer[T]`, arrays, structs, unions, packing, and alignment.
4. Ownership annotations: borrowed, owned, caller-frees, callee-frees,
   finalizers, destructor hooks, and explicit free functions.
5. Header-derived binding generation as a build-time tool that emits low-level
   Gene FFI declarations, plus optional wrapper skeletons.
6. Package support for shipping `.so`, `.dylib`, and `.dll` artifacts with
   platform-specific binding metadata.

For C++ libraries, the preferred generator target is still a C facade. A
binding tool may generate that facade from selected C++ APIs, but Gene should
bind the generated C ABI rather than promising direct C++ ABI calls.

## Future Work

- libffi backend that accepts broad C signatures, including `Float`/`double`,
  structs, callbacks, and varargs, and validates ABI agreement against the
  dylib's debug info where available.
- Callback closures: marshal a Gene `Fn` into a libffi closure so C code
  can call back into Gene (needed for `qsort`-style APIs and signal
  handlers).
- Header-derived signature generation (`(dyn/import "curl.h" libcurl)`),
  most likely via a build-time tool that emits raw Gene FFI declarations and
  optional wrapper skeletons.
- C++ facade generation for selected libraries: parse a constrained C++ API and
  emit an `extern "C"` wrapper layer plus Gene bindings.
- Native package metadata for locating and shipping platform-specific dynamic
  libraries alongside Gene packages.
- Permission gating: an `App`-level allowlist of libraries/symbols that
  `$dyn/load` and `$dyn/find` will resolve, to constrain capabilities in
  untrusted scripts.
- Anonymous callable binding if real use cases need passing foreign functions
  around without naming them through `fn`, `ctor`, or `method`.
- Ownership annotations for returned strings and pointers, including explicit
  free hooks for APIs that return caller-owned memory.
- Unsafe pointer mode for advanced native interop: pointer arithmetic,
  dereference/read/write helpers, and explicit memory ownership operations behind
  a separate capability gate.
