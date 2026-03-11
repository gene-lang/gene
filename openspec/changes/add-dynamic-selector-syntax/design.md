## Context

Gene currently supports:

- Static slash-path access through complex symbols such as `a/x/y`
- Dynamic lookup through `(target ./ expr [default])`
- Dynamic method dispatch through `(obj . expr args...)`
- Selector literals through `(@ ...)` and selector method shorthand through `.@...`

The parser tokenizes a slash-path as a symbol or complex symbol and splits it on `/` before compilation. That means `<>` can be added without reader changes only if the content inside the angle brackets is limited to slash-path fragments that can be reconstructed from those split segments.

## Goals / Non-Goals

- Goals:
  - Add inline dynamic path sugar for common lookup cases.
  - Add inline zero-argument dynamic method sugar.
  - Preserve existing explicit forms for arbitrary expressions.
  - Make dynamic method dispatch behave like static method dispatch across receiver types.
- Non-Goals:
  - Arbitrary expressions inside `<>`
  - New infix operator forms such as `(a @ b)` or multi-argument `./`
  - Selector transform/update APIs
  - CSS/XPath-style selection features beyond the new sugar

## Decisions

- Decision: `<>` only contains slash-path fragments.
  - `a/<b>` and `a/<b/c>` are valid.
  - Forms such as `a/<(pick key)>` remain outside the sugar surface and must use explicit operators.

- Decision: The canonical explicit forms remain the existing ones.
  - Dynamic lookup: `(target ./ expr [default])`
  - Dynamic method call with arguments: `(obj . expr arg1 arg2 ...)`
  - The change does not define `(a @ b)` as a selector-application operator and does not overload `./` into a method-call operator.

- Decision: `a/.<path>` is zero-argument sugar only.
  - The sugar compiles as if the inner path were evaluated first to produce a method name, then dispatched with zero explicit arguments.
  - Calls that need arguments continue to use `(obj . expr args...)`.

- Decision: Dynamic method dispatch must reuse the same receiver coverage as static method dispatch.
  - Value types that already support static method calls through `call_value_method` must also support dynamic method names.
  - Instance and custom-object dispatch semantics stay unchanged aside from the method name being resolved at runtime.

- Decision: Dynamic selector values are validated at runtime.
  - Accepted result kinds: string, symbol, int
  - Rejected result kinds: nil, void, and any other unsupported type
  - This change does not add a separate empty-string rule beyond the underlying lookup semantics.

## Risks / Trade-offs

- Reassembling `<>` spans inside slash-path tokens adds compiler complexity around complex-symbol lowering.
- This change overlaps with `implement-complex-symbol-access`, so the lowering rules need to avoid duplicated parsing logic.
- Dynamic method parity may require refactoring `IkDynamicMethodCall` so it shares more of the static dispatch path, which can affect hot-path VM code.

## Migration Plan

- Existing slash-path syntax remains unchanged.
- Existing explicit dynamic forms remain supported and documented.
- New sugar is additive; code using `(target ./ expr)` or `(obj . expr args...)` does not need migration.

## Open Questions

- Should the compiler lower `<>` spans directly during complex-symbol compilation, or first build a normalized intermediate representation for mixed static/dynamic path segments?
  A: when compiling complex-symbol, not before that
- Should a follow-up change add stricter empty-string validation for angle-bracket sugar, or should it permanently inherit raw string-key lookup semantics?
  A: do the simple thing for now - just lookup by string/integer and throw when it's not a string or integer
