# Enum ADT Reference

Gene uses `enum` as its public sum-type model. Simple symbolic enums, unit variants, and payload-bearing algebraic data types all use the same declaration form, constructor rules, matching rules, nominal identity, and persistence behavior.

This document is for Gene users and maintainers who need to define, construct, type-check, match, serialize/import, and migrate enum ADTs correctly. For the normative language contract, read the type specification (`../spec/02-types.md`) and pattern specification (`../spec/12-patterns.md`) alongside this reference.

## Public model

The canonical public declaration form is `enum`:

```gene
(enum Result:T:E
  (Ok value: T)
  (Err error: E)
  Empty)
```

The declaration head contains the enum name plus optional colon-prefixed generic parameters. The canonical enum name is the portion before the first generic parameter, so `Result:T:E` declares the enum `Result`. Concrete type positions supply generic arguments with ordinary type-expression syntax:

```gene
(fn accept_result [r: (Result Int String)] -> String
  "accepted")
```

Legacy Gene-expression ADT declarations such as `(type (Result T E) ...)` are migration errors, not a second supported model. New code, docs, and examples should describe sum types with `enum`.

### Non-goals

The public model does not expose private checker bridge machinery or any separate ADT registry. Display strings such as `Result/Ok` and `(Result/Ok 42)` are presentation, not identity. Runtime and type identity are nominal: an enum value belongs to the enum declaration that created its variant.

## Declarations

### Unit variants

```gene
(enum Color red green blue)

(var c Color/red)
```

A unit variant has no payload fields. It can be used directly as a value, and it belongs to its parent enum. The older `^values` spelling is accepted as simple-enum sugar and canonicalizes to the same ordered unit-variant model:

```gene
(enum Status ^values [ready done])

(var s Status/ready)
```

### Payload variants

```gene
(enum Shape
  (Circle Float)                    # positional tuple-like payload
  (Rect width: Int height: Int)      # named record-like payload
  Point)
```

A payload variant is a list whose first element is the variant name and whose remaining elements choose one payload shape:

- **Positional payloads** use type expressions only, such as `(Circle Float)` or `(Pair Int Int)`. Slots are ordered and accessed by zero-based ordinal.
- **Named payloads** use field declarations, such as `(Rect width: Int height: Int)` or `(Bag item)`. Field order defines positional constructor order, positional pattern binding order, and display order. Field names define keyword constructor names and named field accessors.

An enum may contain both shapes, but a single variant must not mix them. `(Bad Int name: String)` is rejected; choose either all positional type slots or all named fields.

Field annotations on named variants are optional. Positional slots are type descriptors by construction; use `Any` when a positional slot should remain gradual.

## Construction

Qualified enum members construct values:

```gene
(var circle (Shape/Circle 5.0))
(var rect (Shape/Rect ^height 20 ^width 10))
(var point Shape/Point)
```

Named payload variants support positional construction and keyword construction. A single constructor call must use one style; mixed positional and keyword arguments are rejected.

```gene
(var by_position (Shape/Rect 10 20))
(var by_keyword (Shape/Rect ^width 10 ^height 20))
(assert (by_position == by_keyword))
```

Positional payload variants support positional construction only because they have no public field names:

```gene
(enum E
  (X Int Int)
  (Y r: Int))

(var x (E/X 1 2))
(var y (E/Y ^r 3))
```

Constructors validate arity, missing keyword fields, unknown keyword fields, duplicate keyword fields, invalid keyword use for positional variants, mixed call shapes, and annotated payload types.

```gene
(enum Metric
  (Counter value: Int))

(var counter (Metric/Counter 7))

(try
  (Metric/Counter "bad")
catch *
  (println "typed payload rejected"))
```

Unit variants can be used directly or called with no arguments. Calling a unit variant with payload arguments is an error.

## Field access, equality, display, and `typeof`

Enum payload data is read with slash selectors. Named payload fields are accessed by declaration name:

```gene
(assert (circle/radius == 5.0))
(assert (rect/width == 10))
(assert (rect/height == 20))
```

Positional payload fields are accessed by zero-based ordinal:

```gene
(assert (x/0 == 1))
(assert (x/1 == 2))
```

The general rule is `value/field` for named payload data and `value/0` for positional payload data. Dot dispatch remains behavior dispatch; payload fields are not methods.

Enum value equality is nominal by variant and structural by payload. Two payload values compare equal when they come from the same enum variant and all payload values compare equal. Unit variants from the same enum member compare equal.

`typeof` returns the parent enum name for enum members and enum values:

```gene
(assert ((typeof circle) == "Shape"))
(assert ((typeof Shape/Point) == "Shape"))
```

Display forms are for humans and diagnostics. They are not the canonical identity and must not be used as a substitute for nominal enum identity.

## Built-in `Result`, `Option`, and `?`

`Result` and `Option` are enum-backed built-ins. Their variants are ordinary enum variants with built-in nominal identities:

- `Result/Ok` / `Ok`
- `Result/Err` / `Err`
- `Option/Some` / `Some`
- `Option/None` / `None`

```gene
(var ok (Ok 42))
(var err (Err "boom"))
(var some (Some "value"))
(var none None)
```

The `?` operator unwraps built-in `Ok` and `Some`. It returns early with built-in `Err` and `None`. Same-named variants from user-defined enums are ordinary enum values and do not receive the built-in shortcut behavior.

Prefer qualified forms in docs and examples when custom enums might also use names such as `Ok`, `Err`, `Some`, or `None`.

## `case` patterns

Enum ADTs match through `case` and `when` patterns. A pattern can use a qualified variant name or an unambiguous bare variant name.

```gene
(fn describe [shape: Shape] -> String
  (case shape
    when (Shape/Circle radius)
      "circle"
    when (Shape/Rect width height)
      "rect"
    when Shape/Point
      "point"))
```

Payload binders follow the matched variant's payload shape. Positional variants bind by ordinal. Named variants keep declaration-order binders and additionally support field aliases of the form `field:local`.

```gene
(var total
  (case (E/X 1 2)
    when (E/X a b)
      (+ a b)
    else
      0))

(var renamed
  (case (E/Y ^r 3)
    when (E/Y r:rx)
      rx
    else
      0))
```

`_` consumes a payload position without creating a binding.

```gene
(var height
  (case (Shape/Rect 10 20)
    when (Shape/Rect _ h)
      h
    else
      0))
```

Unit variants match as symbols. Payload variants must provide exactly one binder per declared field. Missing or extra binders produce arity diagnostics. Unknown enum or variant names produce diagnostics. Ambiguous bare variant names require qualification.

A `case` over a statically known enum value is checked for exhaustiveness when it has no explicit `else` and no wildcard `_` branch. Missing variants are reported in declaration order. At runtime, a no-match `case` without `else` returns `nil`.

## Nominal identity across boundaries

Enum identity is nominal and belongs to the enum declaration, not to the printed name. That rule applies across ordinary runtime use, imports, GIR cache artifacts, runtime serialization, and tree serialization.

A value created by `Shape/Circle` satisfies `Shape` boundaries because it carries the `Shape` identity. A different enum with the same printed variant name is not the same type. Built-in `Result` and `Option` shortcuts use the built-in enum identities; user-defined variants named `Ok`, `Err`, `Some`, or `None` do not become the built-ins by name alone.

This identity rule matters when code is split across modules or cached/serialized and loaded later: consumers should rely on enum/type semantics, not on display-string comparison.

## Migration from legacy ADT syntax

Legacy Gene-expression ADT syntax is no longer the public ADT model:

```gene
(type (Result T E)
  (Ok T)
  (Err E))
```

Migrate it to `enum`:

```gene
(enum Result:T:E
  (Ok value: T)
  (Err error: E))
```

Migration guidance:

- Replace legacy `type` ADT declarations with `enum` declarations.
- Use colon-prefixed generic parameters in the enum head.
- Give payload fields names; those names become constructor keywords, slash field selectors, and pattern documentation.
- Construct values with enum variants such as `(Result/Ok value)` or `(Ok value)` for built-ins.
- Read named payload data with slash selectors such as `result/value` and positional payload data with slash selectors such as `value/0`.
- Match values with enum variant patterns.
- Do not treat quoted legacy Result/Option-shaped Gene values as enum ADT values; they do not satisfy enum ADT type boundaries.

## Deferred non-core work

Enum ADTs are implemented and useful, but they remain Beta rather than stable core. Deferred non-core work includes enum-specific methods, optimizer specialization, richer constructor ergonomics, additional pattern-form design, broader non-enum pattern diagnostics, and any stable-core promotion decision. None of those deferred areas is a release promise.
