# Complex Symbol Access Design

This document explains how the VM compiler rewrites complex symbol
expressions when they are used as definition targets (class names,
variables, and assignments). The goal is to allow slash-delimited
paths such as `geometry/shapes/Circle` or `/status` while still
compiling down to a single identifier plus an explicit container
expression.

## Rewriting Rules

The compiler normalises complex symbols **before** emitting bytecode:

- `(class A/B ...)` &rarr; `(class B ^container A ...)`
- `(class geometry/shapes/Circle ...)` &rarr;
  `(class Circle ^container geometry/shapes ...)`
- `(var /a value)` &rarr; `(var a ^container self value)`
- `(/a = value)` &rarr; `(a = value ^container self)`

General rule:

1. Split the complex symbol into segments.
2. The final segment becomes the actual identifier.
3. Every prefix segment becomes the `^container` expression.
   - A leading `/` becomes `self`.
   - Multi-segment prefixes (e.g. `a/b/c`) become a complex symbol again.

Users can still write `^container` manually; the rewriter only injects
one when the original name contained a slash.

## Runtime Semantics

`^container` always represents the receiver for the definition:

- **Classes**: the container must evaluate to a namespace or class
  object. The class is stored inside that namespace instead of the
  current one.
- **Variables / Assignments**: the container can be any object that
  supports `IkSetMember` (namespaces, classes, instances, maps, etc.).
  The identifier is stored on that container instead of the current
  scope or namespace.

The container expression is evaluated immediately before the
definition/assignment runs, so it can reference dynamic values such as
`self`.

## Examples

```gene
(class geometry/shapes/Circle
  (.fn area _
    (* /radius /radius 3.14)
  )
)

(class Record
  (var /table "todos")
  (var /columns ["id" "description" "status"])
)

(.fn set_status [value]
  (/status = value)
)
```

All three cases rely on the same rewriting rule internally, allowing
the rest of the compiler to consume a simple identifier plus a
`^container` property.
