## 1. Parsing And Typing
- [x] 1.1 Normalize positional rest shorthand annotations `rest...: T` to the internal array form `rest...: (Array T)`.
- [x] 1.2 Apply the same element-type rule to any rest annotation expression, including `rest...: (Array T)` becoming internal `(Array (Array T))`.
- [x] 1.3 Ensure non-rest annotations keep their existing meaning and are not treated as shorthand.

## 2. Validation
- [x] 2.1 Add tests for shorthand typed rest parameters, nested-array rest element annotations, and unchanged non-rest behavior.
- [x] 2.2 Run `openspec validate add-rest-element-type-shorthand --strict`.
