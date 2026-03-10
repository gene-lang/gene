## Why

`gene/serdes` can already store large values as filesystem trees, but
`read_tree` currently materializes the whole tree eagerly. For large collections
such as session state, most reads only touch a small subset of the data, so the
runtime should be able to exploit existing filesystem boundaries and defer I/O
and decoding until the relevant node is actually accessed.

The user-facing requirement is seamless access: callers should keep using normal
Gene container access and selector syntax while opting into lazy tree loading
for specific logical nodes such as `^lazy [/sessions]`.

The broader goal is efficient filesystem-backed storage for hierarchical data.
The runtime should treat the filesystem tree as the primary storage boundary for
large state, avoid unnecessary parsing and child materialization, and make lazy
loading a practical performance tool rather than a purely semantic feature.

## What Changes

- Extend `gene/serdes/read_tree` with optional `^lazy [...]` selectors that
  identify logical nodes to keep tree-backed until accessed.
- Treat `^lazy` selectors as node selectors such as `/`, `/sessions`, and
  `/sessions/archive`, distinct from `^separate` child selectors that end in
  `/*`.
- Keep the on-disk tree format unchanged; lazy loading works against the
  existing `.gene` files, exploded directories, `_genetype.gene`,
  `_geneprops/`, `_genechildren/`, and `_genearray.gene` layout.
- Define transparent on-demand materialization and memoization so accesses like
  `state/sessions/session-123` load only the requested descendants when the tree
  shape exposes those boundaries.
- Require efficient metadata-only access patterns so common operations such as
  key listing, size checks, and direct child lookup avoid unrelated descendant
  loads.
- Specify eager fallback when a requested lazy node has no usable filesystem
  boundary, so reads stay correct even when laziness cannot help.
- Add focused tests for lazy map, array, and Gene subtree access, repeated
  access, eager fallback, and compatibility with iteration/serialization.
- Add focused validation that the lazy path avoids unnecessary filesystem reads
  and decode work for representative hierarchical access patterns.

## Impact

- Affected specs:
  - `filesystem-tree-serdes`
- Affected code:
  - `src/gene/serdes.nim`
  - tree/container access and selector runtime paths
  - lazy runtime state/value support as needed
  - serialization-focused tests
- Risk: medium-high
- Key risks:
  - making lazy tree-backed nodes behave transparently enough under existing
    container access syntax
  - loading more of the tree than intended if metadata and child boundaries are
    not defined precisely
  - cache/memoization bugs causing repeated filesystem reads or inconsistent
    in-memory values
  - widening runtime surface area if lazy handling leaks into unrelated hot
    paths
