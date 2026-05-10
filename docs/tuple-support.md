# Tuple Support

Tuples are nominal product-data types. Use them when a value has a fixed shape, a declared name, and no attached behavior. Classes bundle data and methods; tuples carry data only.

The product-data access rule is simple:

- Use slash selectors to read tuple fields and slots, such as `value/field` and `value/0`.
- Use dot dispatch for behavior that already exists on values, such as display conversion helpers.
- Do not treat tuple fields as methods.

Tuples are currently a Beta surface. The implemented contract covers named tuples, positional tuples, unit tuples, direct construction, slash reads, equality/display, `case` patterns, and persistence continuity.

## Declaration forms

Declare a tuple with `tuple`, a nominal type name, and zero or more fields.

```gene
(tuple Point x: Int y: Int)  # named fields
(tuple Box Int)              # positional slots
(tuple Unit)                 # no payload
```

A named tuple gives every payload position a field name. A positional tuple gives payload positions only zero-based slots. A unit tuple has no payload values.

Named and positional payload styles are separate declaration shapes. Do not mix named fields and positional slots in one tuple declaration.

## Construction

Construct tuple values by calling the tuple name directly.

```gene
(tuple Point x: Int y: Int)
(tuple Box Int)
(tuple Unit)

(var point (Point 10 20))
(var same_point (Point ^y 20 ^x 10))
(var box (Box 9))
(var unit (Unit))
```

Named tuples support positional construction in declaration order and keyword construction by field name. A single call must use one style. Positional tuples support positional construction only. Unit tuples are constructed with no arguments.

Tuple construction validates arity, missing keyword fields, unknown keyword fields, duplicate keyword fields, mixed positional/keyword calls, keyword use on positional tuples, and annotated field types.

## Reading product data

Read tuple payload data with slash selectors.

```gene
(assert (point/x == 10))
(assert (point/y == 20))
(assert (point/0 == 10))
(assert (point/1 == 20))
(assert (box/0 == 9))
(assert (unit/0 == void))
```

Named fields can be read by field name or by zero-based slot. Positional tuple slots can be read only by zero-based slot. Missing fields and out-of-range slots return `void`; selector defaults can replace that `void` result.

```gene
(assert ((./ point "missing" 99) == 99))
(assert ((./ box 1 77) == 77))
```

Slash selectors are the public product-data read surface. Dot dispatch remains behavior dispatch and is not a tuple field-access syntax.

## Equality and display

Tuple identity is nominal. Two tuple values compare equal only when they come from the same tuple declaration and all payload values compare equal.

```gene
(tuple Point x: Int y: Int)
(tuple Other x: Int y: Int)

(var point (Point 10 20))
(var same (Point ^y 20 ^x 10))
(var different (Point 10 21))
(var other (Other 10 20))

(assert (point == same))
(assert (point != different))
(assert (point != other))
```

Display uses the tuple name followed by payload values in declaration order.

```gene
(println point)
# => (Point 10 20)
```

Display is for humans and diagnostics. It is not a substitute for nominal tuple identity.

## Tuple `case` patterns

Use `case` to branch on tuple shape and bind payload values.

```gene
(tuple Point x: Int y: Int)
(tuple Box Int)
(tuple Unit)

(var point (Point 10 20))
(var box (Box 9))
(var unit (Unit))

(var point_total
  (case point
    when (Point x y:yy)
      (+ x yy)
    else
      -1))

(var box_value
  (case box
    when (Box value)
      value
    else
      -1))

(var unit_value
  (case unit
    when (Unit)
      30
    else
      -1))
```

Tuple `case` binders follow declaration order. Named tuple patterns can use field aliases such as `y:yy` to bind a field to a different local name. Positional tuple patterns bind by slot order. Unit tuple patterns use the tuple name with no binders.

Use `_` to consume a payload position without creating a binding.

```gene
(case point
  when (Point _ y)
    y
  else
    0)
```

Tuple values do not use array-style tuple destructuring. Use slash reads for direct access and tuple `case` patterns for branching and binding.

## Persistence and module boundaries

Tuple declarations and values preserve their nominal identity, shape, arity, field names, and field type descriptors across supported serialization, deserialization, imports, and GIR cached execution. A deserialized or cached tuple value should continue to compare, display, read through slash selectors, and match in `case` according to the original tuple declaration.

Malformed tuple metadata is rejected at load or reconstruction boundaries rather than silently becoming an untyped product value.

## Non-goals and unsupported surfaces

The current tuple contract does not include:

- anonymous or structural tuple literals;
- `new`-based tuple construction;
- mixed named-and-positional tuple declarations;
- tuple-specific methods, adapters, or field-method dispatch;
- mutation or copy-update helpers;
- array-style tuple destructuring;
- stable-core promotion.

These exclusions keep tuples focused on nominal product data: declare a type, construct it by name, read data with slash selectors, and branch with tuple `case` patterns.
