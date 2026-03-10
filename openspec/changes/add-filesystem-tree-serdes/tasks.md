## 1. Implementation

- [x] 1.1 Revise tree-serdes markers and directories to use
      `_genetype.gene`, `_geneprops/`, `_genechildren/`, and
      `_genearray.gene`.
- [x] 1.2 Update directory decoding so no marker means `Map`, including empty
      directories.
- [x] 1.3 Keep logical root path handling with inline `.gene` storage as
      the default.
- [x] 1.4 Preserve `^separate [...]` selector handling so only selected
      subtrees explode into directories.
- [x] 1.5 Update exploded map, array, and Gene directory encodings,
      including ancestor directory materialization.
- [x] 1.6 Optimize tree serialization and deserialization hot paths in the
      native runtime and add lower-level runtime support if profiling justifies
      it.
- [x] 1.7 Keep the `gene/serdes` namespace available during normal stdlib
      initialization.
- [x] 1.8 Update Nim tests and Gene tests for renamed markers, map-default
      decoding, and optimized behavior.

## 2. Validation

- [x] 2.1 Run focused serialization tests.
- [x] 2.2 Run the stdlib Gene tests that exercise tree serdes.
- [x] 2.3 Validate the change with
      `openspec validate add-filesystem-tree-serdes --strict`.
