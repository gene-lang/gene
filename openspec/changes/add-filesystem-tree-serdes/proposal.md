## Why

Gene already has source-level serialization through `gene/serdes`, but it does
not have a standard way to persist a value as a filesystem tree. That leaves
applications to invent their own layouts for large state, even though the
runtime already knows how to round-trip Gene values.

The desired capability is language-level, not application-specific, and the
first implementation needs a format revision before it becomes the long-term
shape:

- write a value to a single `.gene` file by default
- selectively explode only the subtrees that need separate persistence
- preserve ordered children without hard-coding array indices into semantics
- load the same value back from the filesystem into ordinary Gene values
- minimize reserved-name pressure and make empty directories decode as maps by
  default
- optimize tree serialization and deserialization aggressively for large state

## What Changes

- Add filesystem tree read/write APIs to `gene/serdes`.
- Make `write_tree` treat its path as a logical root path by default.
- Add `^separate [...]` selectors that turn specific logical nodes into
  directories while keeping other nodes inline.
- Revise exploded layouts for maps, arrays, and Gene values to use
  `_genetype.gene`, `_geneprops/`, `_genechildren/`, and `_genearray.gene`.
- Make exploded directory decoding default to `Map` whenever neither
  `_genetype.gene` nor `_genearray.gene` is present, including for empty
  directories.
- Document `_genetype` as the known remaining reserved-name limitation for
  exploded generic map roots.
- Optimize runtime read/write paths for large trees, including specialized
  tree-serdes fast paths and any low-level VM/runtime changes justified by
  profiling.
- Add focused tests for inline round-trips, selective subtree separation, and
  order preservation.

## Impact

- Affected specs:
  - `filesystem-tree-serdes` (new)
- Affected code:
  - `src/gene/serdes.nim`
  - `src/gene/types/`
  - `src/gene/vm/`
  - `src/gene/stdlib.nim`
  - serialization-focused tests
- Risk: medium
- Key risks:
  - ambiguous root resolution if file-vs-directory selection is not handled
    deterministically
  - reserved marker names still colliding with exploded generic map roots
  - selector semantics becoming unclear if logical paths are not defined
    precisely for maps, arrays, and Gene values
  - performance work introducing format drift unless the optimized path stays
    behaviorally identical
  - keeping the namespace available consistently across normal runtime init
