## Why

Gene already has source-level serialization through `gene/serdes`, but it does
not have a standard way to persist a value as a filesystem tree. That leaves
applications to invent their own layouts for large state, even though the
runtime already knows how to round-trip Gene values.

The desired capability is language-level, not application-specific:

- write a value to a single `.gene` file by default
- selectively explode only the subtrees that need separate persistence
- preserve ordered children without hard-coding array indices into filenames
- load the same value back from the filesystem into ordinary Gene values

## What Changes

- Add filesystem tree read/write APIs to `gene/serdes`.
- Make `write_tree` treat its path as a logical root path by default.
- Add `^separate [...]` selectors that turn specific logical nodes into
  directories while keeping other nodes inline.
- Define exploded layouts for maps, arrays, and Gene values, including
  `__order__.gene` and `genetype.gene`.
- Document reserved metadata names and v1 limitations for autodetected generic
  map roots.
- Add focused tests for inline round-trips, selective subtree separation, and
  order preservation.

## Impact

- Affected specs:
  - `filesystem-tree-serdes` (new)
- Affected code:
  - `src/gene/serdes.nim`
  - `src/gene/stdlib.nim`
  - serialization-focused tests
- Risk: medium
- Key risks:
  - ambiguous root resolution if file-vs-directory selection is not handled
    deterministically
  - reserved marker names colliding with generic exploded map roots
  - selector semantics becoming unclear if logical paths are not defined
    precisely for maps, arrays, and Gene values
  - keeping the namespace available consistently across normal runtime init
