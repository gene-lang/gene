## Context
The current rest-binding change keeps typed rest parameters explicit: `nums...: (Array Int)` means the bound variable `nums` has type `(Array Int)`, and the checker validates each consumed middle argument against `Int`. That is semantically clear, but the syntax is noisy for the common case where the author wants to say “the rest elements are `Int`”.

The requested form is:

```gene
(fn f [a: String b...: Int] ...)
```

This needs a design because the implementation must avoid changing the actual runtime type of the bound variable and should not add any runtime overhead.

## Goals / Non-Goals
- Goals:
  - Support `rest...: T` as the only typed positional-rest source syntax.
  - Preserve the actual bound variable type as `(Array T)`.
  - Keep runtime argument binding unchanged and allocation behavior identical.
- Non-Goals:
  - Change the meaning of non-rest parameter annotations.
  - Change keyword splat annotation semantics.
  - Introduce anonymous positional rest syntax.
  - Add element-type shorthand outside rest-parameter contexts.

## Decisions
- Decision: `rest...: T` is the canonical typed positional-rest syntax.
  - The rule applies only to positional rest parameters.
  - During parameter annotation parsing, `T` is normalized to `(Array T)` internally.
  - This keeps the internal type model aligned with the actual runtime value bound to the parameter.

- Decision: the annotated type expression always describes the element type.
  - `rest...: Int` means the bound variable has internal type `(Array Int)`.
  - `rest...: (Array Int)` means the bound variable has internal type `(Array (Array Int))`.
  - This is not a separate compatibility rule for explicit arrays; it falls out of the same normalization rule.

- Decision: runtime and descriptor semantics stay unchanged.
  - The runtime binder still binds the rest parameter to a Gene array.
  - Type descriptors, runtime compatibility checks, and local variable type validation continue to see the rest parameter as an array type.
  - The change is purely a front-end normalization step, so it does not add runtime branches or new metadata forms.

- Decision: call-site checking continues to validate collected arguments against the element type.
  - After normalization, existing rest-element validation logic can continue to read the element type from `(Array T)`.
  - This avoids duplicate typing rules while keeping the source syntax concise.

## Risks / Trade-offs
- This introduces a small context-sensitive rule: `x: Int` and `rest...: Int` no longer mean the same shape of bound value.
- The rule is still local and easy to explain because it only applies to positional rest parameters and always lowers to the explicit array form.
- Source-level pretty printers for function types must render rest parameters using the element-type form, otherwise internal `(Array T)` storage would print back as a misleading source representation.

## Migration Plan
- Accept `rest...: T` and normalize it internally to the same representation.
- Treat `rest...: (Array T)` as “rest elements are arrays of `T`”, yielding an internal bound type of `(Array (Array T))`.
- Update tests to use the shorthand form for the common case and confirm nested-array element annotations and non-rest behavior remain unchanged.
