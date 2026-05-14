## 0. Approval Gate

- [ ] 0.1 Review and approve this OpenSpec change before any S02 runtime implementation begins.
- [ ] 0.2 Keep S01 contract/documentation work separate from runtime, test fixture, and GeneClaw implementation edits.

## 1. S02 — File Ref Reader Foundation

- [ ] 1.1 Add `gene/serdes/read_file` for reading one serialized file and `gene/serdes/read` as its alias.
- [ ] 1.2 Teach deserialization to recognize serializer-owned `(gene/serdes/read_file ...)` ref forms with containing-file context.
- [ ] 1.3 Reject unsafe paths, missing files, invalid serialized text, malformed `read_file` options, and `read_file` cycles with path/context diagnostics.
- [ ] 1.4 Add focused happy-path and negative tests for explicit file refs, alias behavior, path safety, missing/invalid files, malformed options, and cycles.

## 2. S03 — Directory Refs, Shape Options, and Lazy Loading

- [ ] 2.1 Add `gene/serdes/read_dir` for directory-backed collections.
- [ ] 2.2 Support explicit `(gene/serdes/read_dir ...)` serialized ref forms with containing-file context.
- [ ] 2.3 Implement `read_dir` shape and ordering options for ordered arrays and keyed maps.
- [ ] 2.4 Implement eager-by-default behavior and `^lazy true` transparent lazy refs for file and directory refs.
- [ ] 2.5 Add focused positive and negative tests for invalid directory targets, malformed options, eager failures, lazy materialization/caching, and path cycles.

## 3. S04 — Writer Externalization

- [ ] 3.1 Add `gene/serdes/write` as the canonical filesystem writer.
- [ ] 3.2 Implement selector-driven `^externalize` so selected sub-values are written to deterministic child files/directories.
- [ ] 3.3 Replace externalized sub-values in parent payloads with explicit `read_file` / `read_dir` forms.
- [ ] 3.4 Reject malformed selectors, unsafe generated child IDs, name collisions, path escapes, unsupported target values, and externalization cycles.
- [ ] 3.5 Add focused round-trip, deterministic naming, negative selector/path, and public-format tests.

## 4. S05 — Remove Old Tree Serdes Surface

- [ ] 4.1 Remove `gene/serdes/read_tree` and `gene/serdes/write_tree` from the supported public namespace.
- [ ] 4.2 Remove or retire old tree-serdes implementation paths that are no longer needed by `write`, `read_file`, or `read_dir`.
- [ ] 4.3 Preserve existing canonical text serdes behavior for primitives, arrays, maps, Gene values, typed refs, enum/tuple values, named instances, and custom hooks.
- [ ] 4.4 Add old API removal assertions and regression tests for existing runtime serdes identity behavior.

## 5. S06 — Public Cleanup and Full Gate

- [ ] 5.1 Migrate GeneClaw storage helpers to `write`, `read`, `read_file`, and `read_dir`.
- [ ] 5.2 Update public specs, docs, tests, and examples so they teach only the unified filesystem serializer.
- [ ] 5.3 Run focused filesystem-serdes tests, old API removal assertions, GeneClaw storage helper smoke tests, `openspec validate replace-tree-serdes-with-file-refs --strict`, `nimble build`, and the full `./testsuite/run_tests.sh` gate.
- [ ] 5.4 Document any remaining limitations as non-public implementation notes or future proposals, not as supported tree-serdes compatibility behavior.
