## 1. Syntax and Compilation
- [x] 1.1 Detect and reassemble `<>` spans inside slash-delimited path tokens during compilation.
- [x] 1.2 Lower `a/<path>` to dynamic member or index lookup using the resolved inner path fragment.
- [x] 1.3 Lower `a/.<path>` to zero-argument dynamic method dispatch and keep `(obj . expr args...)` as the explicit form for argumentful calls.

## 2. Runtime Dispatch
- [x] 2.1 Validate resolved dynamic selector values and raise clear errors for unsupported result kinds.
- [x] 2.2 Route dynamic method calls through the same receiver coverage as static method calls, including strings, arrays, maps, and instances.

## 3. Verification and Docs
- [x] 3.1 Add tests for simple, nested, and mixed static/dynamic selector paths.
- [x] 3.2 Add tests for `a/.<path>` on both value types and instances.
- [x] 3.3 Update selector documentation to describe the `<>` grammar limit and the explicit operator escape hatches.
