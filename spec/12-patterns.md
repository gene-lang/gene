# 12. Pattern Matching & Destructuring

Gene currently has a tested destructuring subset plus several experimental
pattern-matching ideas. Treat the stable subset below as the contract; anything
outside it remains subject to redesign.

## Tested stable subset

### Array destructuring in `var`

```gene
(var [x y] [10 20])
# x => 10, y => 20
```

### Default values in destructuring patterns

```gene
(var [x = nil y = 2] [])
# x => nil, y => 2
```

An explicit `nil` default is distinct from "no default".

### Named positional rest

Exactly one named positional rest binding is supported:

```gene
(var [first rest...] [1 2 3 4])
# first => 1, rest => [2, 3, 4]
```

The postfix form is also accepted:

```gene
(var [items ... tail] [1 2 3 4])
# items => [1, 2, 3], tail => 4
```

### Gene property and child destructuring

Gene values can destructure properties and children:

```gene
(var payload `(payload ^a 10 ^x 99 20 30 40))
(var [^a first rest...] payload)
# a => 10
# first => 20
# rest => [30, 40]
```

### Gene property rest binding

Remaining Gene properties can be captured into a map:

```gene
(var payload `(payload ^a 10 ^x 99 20))
(var [^a first ^extra...] payload)
# a => 10
# first => 20
# extra => {^x 99}
```

### Simple value `case/when`

```gene
(case day
  when 1 "Monday"
  when 2 "Tuesday"
  else   "Other")
```

`case/when` is an expression; each selected branch returns its last value.
no-match `case` without `else` returns `nil`.

## Experimental subset

ADT/Option matching and `?` remain experimental. Current experiments include
matching values such as `(Ok v)`, `(Err e)`, `(Some x)`, `None`, and early-return
unwrapping with `?`, but their syntax and type-checker integration are not yet
part of the stable-core contract.

## Known gaps

- Nested patterns beyond currently covered destructuring are not stable.
- Guard clauses such as `when (Ok v) if (v > 0)` are not supported.
- Exhaustiveness checking is not implemented.
- Map destructuring syntax such as `(var {^x a ^y b} value)` is not stable.
- Function-parameter patterns beyond the existing argument matcher surface are
  not specified as a general pattern system.
- `match`, or-patterns, and as-patterns are not implemented.
- Broad arity diagnostics are incomplete; some destructuring failures still
  report low-level matcher errors.
