## 1. Implementation

- [x] 1.1 Add `gene/serdes/write_tree` and `gene/serdes/read_tree`.
- [x] 1.2 Implement logical root path handling with inline `.gene` storage as
      the default.
- [x] 1.3 Implement `^separate [...]` selector handling so only selected
      subtrees explode into directories.
- [x] 1.4 Implement exploded map, array, and Gene directory encodings,
      including ancestor directory materialization.
- [x] 1.5 Make the `gene/serdes` namespace available during normal stdlib
      initialization.
- [x] 1.6 Add tests for inline roots, selective subtree separation, array
      order, Gene nodes, and reserved-marker behavior.

## 2. Validation

- [x] 2.1 Run focused serialization tests.
- [x] 2.2 Validate the change with
      `openspec validate add-filesystem-tree-serdes --strict`.
