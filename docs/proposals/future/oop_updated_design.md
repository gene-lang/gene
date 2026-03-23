# OOP Unified Design — Gene Data Model Integration

*Based on discussion 2026-03-16 (#team-cao3)*

## Core Principle

Gene values are the canonical representation of all runtime objects. Classes and instances are not separate Nim constructs with a Gene "view" — they ARE Gene values at the language level. The runtime may use optimized internal representations (Nim objects, NaN-boxed tags), but this is an implementation detail invisible to Gene code. From the language's perspective:

* A class IS a Gene value of type Class
* An instance IS a Gene value whose type slot is its class
* Any Gene value can be inspected, serialized, and reconstructed using the same primitives

## Class Representation

Each class is an instance of `Class`, represented as a Gene value:

```gene
(class Point < Object
  (ctor [x y] (/x = x) (/y = y))
  (method distance [] (sqrt ((/x * /x) + (/y * /y))))
  (method to_s [] ("Point(" .append (str /x) ", " (str /y) ")"))
)

# Is equivalent to

(Class
  ^name Point
  ^parent Object
  ^ctor (fn [x y] (/x = x) (/y = y))
  ^methods {
    ^distance (fn [] (sqrt ((/x * /x) + (/y * /y))))
    ^to_s (fn [] ("Point(" .append (str /x) ", " (str /y) ")"))
  })
```

### Class properties

| Property | Description |
|----------|-------------|
| `^name` | Class name (symbol) |
| `^parent` | Parent class (default: `Object`) |
| `^ctor` | Constructor function |
| `^methods` | Map of method name → function |

### Deferred / future

- Namespace members — belong in the module system, not on the class

## Instance Representation

An instance of a class is a Gene value whose type slot is the class:

```gene
(var point (new Point 3 4))

# point as Gene value:
(Point ^x 3 ^y 4)
```

- **Type slot** → the class (`Point`)
- **Properties** → instance state (`^x 3 ^y 4`)
- **Children** → optional payload, accessible via `^children`

This means every instance is a regular Gene value that can be quoted, inspected, pattern-matched, and serialized.

## Type Hierarchy

### Bootstrap types

```
Object    — root of the class hierarchy (no parent)
Class     — the class of all classes (instance of itself, inherits from Object)
Nil       — singleton class, nil is its only instance
```

### Hierarchy relationships

```
Object                (Object is the root)
Class  < Object       (Class inherits from Object)
Int    < Object
String < Object
Bool   < Object
Nil    < Object
Array  < Object
Map    < Object
... all types inherit from Object
```

### Instance-of relationships

```
Class  is Class        (circular — bootstrap special case)
Object is Class
Int    is Class
Point  is Class        (user-defined class)
point  is Point        (user-defined instance)
```

### The `is` operator

`(x is Y)` returns true if:
1. `x` is a direct instance of `Y`, OR
2. `x`'s class is a descendant of `Y`

```gene
(var point (new Point 3 4))

(point  is Point)    # true — direct instance
(point  is Object)   # true — instance of Point, which descends from Object
(Point  is Class)    # true — direct instance
(Point  is Object)   # true — instance of Class, which descends from Object
(Class  is Class)    # true — bootstrap special case
(Class  is Object)   # true — instance of Class, which descends from Object
(Object is Class)    # true — direct instance
(Object is Object)   # true — instance of Class, which descends from Object
```

### Primitives are Objects

All primitives participate in the class hierarchy:

```gene
(42   is Int)        # true
(42   is Object)     # true
("hi" is String)     # true
(true is Bool)       # true
(nil  is Nil)        # true
(nil  is Object)     # true
```

At runtime, NaN-boxing keeps primitives fast — the class hierarchy is a logical model, not a memory layout. `(42 is Int)` is just a tag check.

## Nil — The Null Object

`nil` is the sole instance of `Nil < Object`.

### Nil has real methods

```gene
nil/.serialize       # => "nil"
nil/.to_s            # => ""
nil/.to_bool         # => false
```

### Nil has `on_method_missing` → returns nil

```gene
nil/.anything        # => nil (via on_method_missing)
nil/.foo/.bar/.baz   # => nil (nil propagates through the chain)
```

This makes **all method calls nil-safe by default**. No need for a separate `?.` or `?method` syntax — Nil's `on_method_missing` handles it at the object model level.

### Nil-assertion with `/!`

When you want strictness, use `/!` to assert non-nil:

```gene
x/.foo               # nil-safe — returns nil if x is nil
x/!/.foo             # strict — throws if x is nil
x/a/!/b              # nil-safe on a, strict on b
```

This inverts the common pattern: most languages are strict by default and opt-in to nil-safety (`?.`). Gene is **nil-safe by default** and opt-in to strictness (`/!`).

### Property access remains nil-safe

```gene
(var obj nil)
obj/x                # => nil
obj/x/y/z            # => nil (chain collapses)
```

## Summary of Navigation

| Syntax | Behavior |
|--------|----------|
| `obj/prop` | Property access — nil-safe (returns nil if obj is nil) |
| `obj/.method` | Method call — nil-safe (Nil's `on_method_missing` returns nil) |
| `obj/!/.method` | Method call — strict (throws if obj is nil) |
| `obj/!/prop` | Property access — strict (throws if obj is nil) |

## Dynamic Class Construction

Because classes are Gene values, metaprogramming is just data construction:

```gene
# Create a class dynamically
(var my_class
  (Class ^name `Dynamic
    ^methods {
      ^greet (fn [] "hello from dynamic class")
    }))
(var obj (new my_class))
(obj .greet)          # => "hello from dynamic class"
obj/.greet            # equivalent to (obj .greet)
```

No reflection API needed — you're just building Gene values.

## Method Resolution

All behavior lookup follows one model — walk the `^parent` chain:

1. Look up method in instance's class `^methods`
2. Walk `^parent` chain until found
3. If not found, look for `on_method_missing` on the class (walks `^parent` chain too)
4. If no handler found anywhere in the chain, throw `MethodNotFound`

For `Nil`: step 3 finds Nil's `on_method_missing` and returns `nil`.

### Everything is inherited via `^parent`

Methods, `on_method_missing`, AND constructors all follow the same inheritance model — walk the `^parent` chain, use the first one found:

- `^methods` — inherited, overridable per-method
- `^on_method_missing` — inherited, overridable
- `^ctor` — inherited, overridable

```gene
(class Animal
  (ctor [name]
    (/name = name))
  (method speak [] "..."))

(class Dog < Animal
  (method speak [] "Woof!"))

# Dog inherits Animal's ctor
(var d (new Dog "Rex"))
(println d/name)              # => "Rex"
```

If a subclass needs different initialization, it overrides `^ctor`. No special rules — same as overriding any method.

### `on_method_missing` is inheritable

`on_method_missing` follows the same inheritance rules as regular methods. If a parent class defines it, all descendants inherit it unless they override:

```gene
(class Proxy
  (on_method_missing [name args...]
    (println "intercepted:" name)
    nil))

(class LoggingProxy < Proxy)
# LoggingProxy inherits Proxy's on_method_missing

(var lp (new LoggingProxy))
(lp .anything)       # => prints "intercepted: anything"
```

This means `Nil < Object` could define `on_method_missing` at the Nil level without affecting Object's descendants — only nil gets the "return nil" behavior.

## Design Decisions

### Included
- Classes as Gene values with two-way translation
- Instances as Gene values (type slot = class)
- Single inheritance via `^parent`
- Everything is an Object (including primitives)
- `Class is Class` (bootstrap special case)
- `on_method_missing` (justified by Nil's use case)
- `/!` nil-assertion operator

### Excluded
- Metaclasses / subclassing Class — use macros instead
- Namespace members on classes — belong in module system
- AOP on the class model — use functions/macros/decorators
- Pseudo-macros in OOP (`ctor!`, `method!`) — the `!` suffix and `$caller_eval` are powerful for standalone functions, but combining them with inheritance, `super`, dynamic dispatch, and `on_method_missing` creates too much complexity. If macro-like behavior is needed at the class level, wrap it in a standalone `fn!` that constructs or manipulates objects.

### Deferred
- `on_method_missing` naming (`fallback`?) — revisit after more usage
- Interfaces / protocols
- Mixin / trait composition
