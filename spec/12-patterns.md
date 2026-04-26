# 12. Pattern Matching & Destructuring

Pattern matching is a Beta language surface for a deliberately small, tested subset. The current public contract covers direct argument binding, `var` destructuring, simple `case/when`, and enum ADT `case` patterns. The standalone `(match ...)` expression is removed, and richer pattern-language forms are Future work unless this page explicitly includes them in the Beta contract.

## Public Beta contract

### Argument binding baseline

Function argument binding uses the existing argument matcher directly against call arguments. It must not construct an aggregate argument object solely to bind parameters. This is the argument-binding baseline, not a claim that arbitrary function-parameter pattern syntax is a general pattern language.

### Array destructuring in `var`

```gene
(var [a b] [1 2])
# a => 1, b => 2
```

### Default values in destructuring patterns

```gene
(var [a = 1 b] [2])
# a => 1, b => 2
```

An explicit `nil` default is distinct from "no default":

```gene
(var [value = nil] [])
# value => nil
```

### Named positional rest

Exactly one named positional rest binding is supported. A rest binding can capture a variable-width prefix before a trailing binding:

```gene
(var [items... tail] [1 2 3 4])
# items => [1, 2, 3], tail => 4
```

The spaced form is also accepted:

```gene
(var [items ... tail] [1 2 3 4])
# items => [1, 2, 3], tail => 4
```

A positional rest marker must attach to a named binding, and a pattern may not contain more than one named positional rest binding.

### Gene property, child, and property rest destructuring

Gene values can destructure properties and children. Remaining Gene properties can be captured into a map:

```gene
(var payload `(payload ^a 10 ^x 99 20 30 40))
(var [^a b c... ^rest...] payload)
# a => 10
# b => 20
# c => [30, 40]
# rest => {^x 99}
```

### Simple value `case/when`

```gene
(case 1 when 1 "one" when 2 "two" else "other")
# => "one"
```

`case/when` is an expression; each selected branch returns its last value. A no-match `case` without `else` returns `nil`.

## Enum ADT case patterns in the Beta contract

Enum ADTs match through the canonical `enum` model. A `when` pattern can name a qualified variant (`Shape/Circle`) or a bare variant (`Circle`) when the bare name resolves unambiguously for the scrutinee. Use qualified names when variants share names across enums or when a custom enum uses built-in names such as `Ok`, `Err`, `Some`, or `None`.

```gene
(enum Shape
  (Circle radius: Int)
  (Rect width: Int height: Int)
  Point)

(fn classify [shape: Shape] -> Int
  (case shape
    when (Shape/Circle r)
      (r + 1)
    when (Shape/Rect w h)
      (w + h)
    when Shape/Point
      0))
```

Payload binders are positional and follow the field declaration order. A binder must be a symbol. The special binder `_` consumes that payload position without creating a binding.

```gene
(var rect (Shape/Rect 10 20))
(case rect
  when (Shape/Rect _ h)
    h
  else
    -1)
# => 20
```

Unit variants match as symbols, either qualified (`Shape/Point`) or bare (`Point`) when resolution is unambiguous. Payload variants must provide exactly one binder per declared payload field; missing or extra binders produce an arity diagnostic. Unknown enum or variant names produce diagnostics, and ambiguous bare variant names require qualification.

Built-in `Result` and `Option` variants are enum variants too. Bare `Ok`, `Err`, `Some`, and `None` patterns match the built-in enum identities; qualify user-defined same-named variants to match custom enums.

```gene
(fn accept_result [r: (Result Int String)] -> Int
  (case r
    when (Ok value)
      value
    when (Err error)
      0))
(accept_result (Ok 5))
# => 5
```

A `case` over a statically known enum value is checked for exhaustiveness when it has no explicit `else` and no wildcard `_` branch. The exhaustiveness rule is strict about the enum declaration: every declared variant must be covered, and missing variants are reported in declaration order. At runtime, a `case` expression with no matching `when` and no `else` returns `nil`.

Legacy Gene-expression ADT matching is not a supported public model. Quoted or stale legacy Result/Option-shaped Gene values should be migrated to enum-backed values and matched with enum variant patterns.

## Removed: standalone `(match ...)`

The standalone `(match ...)` expression is not part of the Beta subset. The compiler rejects it with a removed-surface diagnostic that directs users to `(var pattern value)` for binding or `(case ...)` for branching.

Do not write new code using the removed form:

```gene
(match 1 when 1 2)
```

## Future pattern-language features

The following forms are not part of the Beta contract unless a later spec revision promotes them with implementation and focused tests:

- Nested patterns beyond the covered destructuring cases.
- Guard clauses such as `when pattern if condition`.
- Map destructuring syntax such as `(var {^x a ^y b} value)`.
- Broad function-parameter patterns beyond the existing argument matcher surface.
- Literal quote patterns.
- Or-patterns.
- As-patterns.
- Any reintroduced standalone match expression.

Some non-enum destructuring failures still come from the matcher/runtime path. Invalid Beta-subset destructuring should produce targeted diagnostics where tests cover those failures; broader diagnostic polish remains Future work.
