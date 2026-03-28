# Adapter Design

## Overview

An Adapter is a special wrapper that changes one object's visible behavior and shape without mutating the original. Adapters are the *mechanism* (how mapping works); Interfaces are the *face* (what consumers see). No adapter exists without an interface — the interface defines the visible surface, the adapter provides the plumbing.

Gene types can be considered a specific case of adapters (named, fixed-shape). Adapters generalize this concept.

## Key Insight: Interfaces Are the Face

- **Interface** = the face (defines visible shape, properties, methods)
- **Adapter** = the mechanism (maps inner object to interface shape)
- Adapters don't have their own faces — interfaces are their faces
- Calling an interface on an object creates an adapted view of that object

## Two Forms of Implementation

### Inline (Native) — No Adapter Created

```
(class C
  (implement InterfaceA …)
  …
)

(var c (new C))
(InterfaceA c)   # returns c itself — no wrapper, direct access, zero overhead
```

When `implement` is inside the class, the class *natively* satisfies the interface. The methods/properties are part of the object. `(InterfaceA c)` is essentially a type assertion — it returns the same object.

### External (Adapter) — Wrapper Created

```
(implement InterfaceA for ClassX
  …
)

(var x (new ClassX))
(InterfaceA x)   # creates an adapter wrapper around x
```

When `implement` is defined externally, calling the interface creates an adapter object. Needed because the class doesn't natively conform — the adapter bridges the gap.

### Behavior of `(InterfaceA obj)`

| Situation                        | Result                          |
|----------------------------------|---------------------------------|
| Class has inline `implement`     | Returns obj directly (no-op)    |
| External `implement` exists      | Creates adapter wrapper         |
| Neither exists                   | Error                           |

## Built-in Interfaces

Core data types are interfaces with optimized built-in implementations:

| Interface  | Built-in Implementation| Purpose                     |
|------------|------------------------|-----------------------------|
| `Map`      | Native hash map        | Key-value access            |
| `Array`    | Native array           | Indexed, ordered collection |
| `Gene`     | Native gene type       | Gene expression structure   |
| `Iterator` | Native iterator        | Sequential traversal        |

The runtime treats built-in types as fast-path implementations — optimized C/native code. But any custom class can implement these interfaces:

```
(class MyDB
  (implement Map
    (method get [key] …)
    (method set [key value] …)
    (method keys [] …)
  )
)
```

Now `MyDB` instances work anywhere a `Map` is expected — iteration, member access, destructuring — because it conforms to the `Map` interface.

This means:
- **Built-in types** = optimized native implementations of core interfaces
- **Custom types** = can implement the same interfaces, participate in the same protocols
- **Runtime dispatches** on the interface — fast path for built-ins, adapter/vtable for custom

## Core Properties

- **Wraps any value** — integers, maps, objects, other adapters
- **Stackable** — adapters can wrap adapted objects (multiple interfaces)
- **Lightweight** — minimal overhead; one branch on member access
- **Generally stateless** — but *can* carry its own data when needed (supplementary context for the adaptation, not standalone state)
- **Serialization preserves structure** — both the adapter layer and the inner value are serialized, enabling exact reconstruction on deserialization

## Access Model

The interface defines what's visible. The adapter maps inner properties/methods to the interface's shape.

### Property Mapping Types

| Mapping Value  | Behavior                            |
|----------------|-------------------------------------|
| Symbol/String  | Rename — redirects to inner prop    |
| Function       | Computed — calls function on access |
| `nil`/sentinel | Hidden — property doesn't exist     |

Only what the interface declares is visible. This is inherently whitelist — the interface *is* the whitelist.

### Lookup Order

When accessing a property on an adapted object:

1. **Adapter's own data** — adapter-level supplementary context
2. **Interface-mapped properties** — from the implements mapping
3. **No passthrough** — if the interface doesn't expose it, it doesn't exist

## Adapter's Own Data

Adapters generally should not store instance-specific data, but can when the adaptation requires context:

```
(interface Ageable
  (method age [] -> Int)
)

# _genevalue refers to the wrapped value
# _geneinternal stores supplementary context
(implement Ageable for Int
  (ctor [birth_year]
    (/_geneinternal/birth_year = birth_year)
  )

  (method age [] (/_genevalue - /_geneinternal/birth_year))
)

(var age (Ageable 2026 1990))
age/.age

```

Here `birth_year` is supplementary context needed by the computed `age` property. The wrapped value (2026) is the current year. The adapter provides the relationship between them.

## Stacking

Adapters compose by wrapping. An object can be adapted through multiple interfaces:

```
(var c (new C))
(var readable (Readable c))
(var serializable (Serializable readable))
```

The outermost adapter's surface is what consumers see. Serialization preserves the full chain.

## Relationship to Types

| Aspect      | Type                          | Adapter                        |
|-------------|-------------------------------|--------------------------------|
| Shape       | Named, fixed                  | Defined by interface           |
| Binding     | One per type                  | Any number, per-interface      |
| Data        | Defines instance structure    | Wraps existing value           |
| Purpose     | Define what something *is*    | Change how something *looks*   |
| Face        | Is its own face               | Interface is its face          |

## Iteration and Serialization

- **Access** sees the interface's surface (the face)
- **Serialization** sees the full structure (adapter + inner value)
- **Deserialization** restores both layers intact
- **Iteration** follows the interface's declared properties

This ensures no information loss while maintaining encapsulation during normal use.

## Implementation Considerations

- Member access checks one flag: "is this adapter-wrapped?" — single branch in the hot path
- Property/map/namespace member access should support the adapter hook uniformly
- Stacked adapters form a chain; consider flattening or caching resolved mappings for performance
- Adds complexity to the language — start minimal, extend based on real usage patterns

## Standalone Implementation (External Adapters)

Adapters can be defined outside the class — useful for third-party classes or separation of concerns:

```
(implement InterfaceA for ClassX
  …
)
```

This registers an adapter mapping from `ClassX` to `InterfaceA` without modifying the class definition. Both forms are equivalent:

- **Inline:** `(class C (implement InterfaceA …) …)` — adapter defined with the class
- **Standalone:** `(implement InterfaceA for ClassX …)` — adapter defined externally

## Partial Implementations

Adapters can partially implement an interface — not every method/property needs to be mapped:

```
(implement Serializable for MyClass
  # only implements .to_json, not .to_xml
  (method to_json [] …)
)
```

- **Calling an implemented method** — works normally
- **Calling an unimplemented method** — fails at runtime with a clear error
- Partial adapters are useful for incremental adoption or when only a subset of the interface is relevant

This is a deliberate design choice: fail late (at call site) rather than fail early (at adapter creation). It allows partial conformance without forcing stub implementations.

## Open Questions

- Exact conflict resolution when adapters are stacked (outermost wins?)
  A: outermost wins
- Whether method dispatch intercepts all calls or only mapped ones
  A: intercepts all calls
- Performance implications of deep adapter chains
  A: adapters should be highly optimized.
- Syntax for the `implement` body — how mappings are declared
- Should partial implementations be flagged (e.g., `partial implement`) or implicit?
  A: defer until we have a better sense of the real-world usage patterns
- Compile-time warnings for partial implementations?
  A: defer until we have a better sense of the real-world usage patterns
