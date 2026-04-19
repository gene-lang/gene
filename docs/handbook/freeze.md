# Freeze

Phase 1 uses two related terms that mean different things in Gene:

| Concept | Surface | Meaning |
| --- | --- | --- |
| `sealed` | `#[]`, `#{}`, `#()` | Shallow immutability on the container itself |
| `frozen` | `(freeze v)` | Deep immutability across the whole reachable graph |

The runtime still stores the shallow flag in an on-disk field named
`frozen`. Phase 1 does not rename that field. User-facing docs and errors use
`sealed` for the shallow literal form and `frozen` for deep `(freeze ...)`
results.

## Sealed values

`#[]`, `#{}`, and `#()` produce sealed containers:

```gene
(def xs #[1 2 3])
(def cfg #{^mode "dev"})
(def form #(Widget ^name "demo"))
```

Sealed means:

- The container itself cannot be mutated.
- Existing aliases to child values may still mutate those child values.
- Sealed values are still treated as shallow values by the actor work.

This is why sealed and frozen are different concepts. A sealed value protects
the outer shape only; it does not promise that nested arrays, maps, genes, or
bytes are safe to share by pointer across actors.

## Frozen values

`(freeze v)` walks a value recursively and tags every reachable Phase 1 MVP
container as frozen:

```gene
(def payload {:items [1 2 3] :meta {:kind "demo"}})
(def shared (freeze payload))
```

Frozen means:

- The whole reachable graph is treated as immutable.
- The runtime marks the graph `deep_frozen` and `shared`.
- Re-freezing the same value is a no-op.
- Frozen values are the values the actor design can share by pointer.

## Phase 1 MVP freeze scope

Phase 1 only deep-freezes these container kinds:

- arrays
- maps
- hash maps
- genes
- bytes

Strings are already immutable after Phase 0, so they do not need a
`(freeze ...)` call to be pointer-shareable.

Everything else is outside the Phase 1 deep-freeze MVP. In particular:

- instances are not yet freezable
- classes are not yet freezable
- bound methods are not yet freezable
- native resources are not freezable
- closures are deferred to Phase 1.5

If `(freeze v)` reaches one of those non-MVP kinds, it raises a
`FreezeScopeError` instead of partially freezing the graph.

## Sealed versus frozen by example

Sealed:

```gene
(def child [1 2])
(def outer #[child])
```

- `outer` cannot be mutated directly.
- `child` can still change through another alias.

Frozen:

```gene
(def child [1 2])
(def outer (freeze [child]))
```

- Neither the outer array nor the nested array can be mutated.
- The runtime treats the whole graph as frozen.

## Error wording

Phase 1 user-visible errors follow this split:

- sealed write errors talk about `sealed array`, `sealed map`, `sealed gene`,
  or `sealed hash map`
- deep write errors talk about `frozen <kind>`
- `(freeze ...)` scope failures explain that non-MVP kinds stay shallow in
  Phase 1

That terminology matters because sealed values are shallow and frozen values
are deep.

## Forward reference

Phase 1.5 is the next required step for closures. Closures need a separate
captured-environment analysis before they can participate in the frozen
surface safely. Phase 2 actor APIs depend on that follow-up work, but Phase 1
does not include it.
