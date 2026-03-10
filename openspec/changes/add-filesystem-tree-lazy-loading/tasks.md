## 1. Implementation

- [ ] 1.1 Extend `gene/serdes/read_tree` to accept `^lazy [...]` selector
      literals and resolve them against logical node paths.
- [ ] 1.2 Add runtime support for tree-backed lazy nodes covering map, array,
      and Gene directory/file boundaries.
- [ ] 1.3 Materialize requested descendants on ordinary access and memoize
      loaded values within a `read_tree` result.
- [ ] 1.4 Preserve eager fallback when a requested lazy node has no usable
      filesystem boundary.
- [ ] 1.5 Ensure metadata-only operations and direct child access avoid
      unnecessary unrelated subtree reads where the tree layout permits it.
- [ ] 1.6 Keep iteration, serialization, selectors, mutation, and
      `write_tree` behavior compatible with eager values.
- [ ] 1.7 Add focused tests for lazy session-style maps, arrays, Gene nodes,
      repeated access, and eager fallback.
- [ ] 1.8 Add focused validation or instrumentation checks for representative
      hierarchical reads so the lazy path demonstrates reduced file reads and
      decode work versus eager loading.

## 2. Validation

- [ ] 2.1 Run focused tree-serdes tests.
- [ ] 2.2 Validate the change with
      `openspec validate add-filesystem-tree-lazy-loading --strict`.
