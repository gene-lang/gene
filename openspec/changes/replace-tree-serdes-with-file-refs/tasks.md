## 0. Approval Gate

- [x] 0.1 Review and approve this OpenSpec change before any S02 runtime implementation begins.
- [x] 0.2 Keep S01 contract/documentation work separate from runtime, test fixture, and GeneClaw implementation edits.

## 1. S02 — File Ref Reader Foundation

- [x] 1.1 Add `gene/serdes/read_file` for reading one serialized file and `gene/serdes/read` as its alias.
- [x] 1.2 Teach deserialization to recognize serializer-owned `(gene/serdes/read_file ...)` ref forms with containing-file context.
- [x] 1.3 Reject unsafe paths, missing files, invalid serialized text, malformed `read_file` options, and `read_file` cycles with path/context diagnostics.
- [x] 1.4 Add focused happy-path and negative tests for explicit file refs, alias behavior, path safety, missing/invalid files, malformed options, and cycles.

## 2. S03 — Directory Refs, Shape Options, and File Lazy Loading

- [x] 2.1 Add `gene/serdes/read_dir` for eager directory-backed collections.
- [x] 2.2 Support explicit `(gene/serdes/read_dir ...)` serialized ref forms with containing-file context.
- [x] 2.3 Implement `read_dir` shape options for ordered arrays and keyed maps with deterministic `^order name` ordering.
- [x] 2.4 Implement eager-by-default behavior, `^lazy true` transparent lazy refs for `read_file` / `read`, and fail-closed rejection for `read_dir ^lazy true` until directory lazy loading is separately specified and tested.
- [x] 2.5 Add focused positive and negative tests for invalid directory targets, malformed options, eager failures, file lazy materialization/caching, unsupported directory-lazy requests, and path cycles.

## 3. S04 — Writer Externalization

- [x] 3.1 Add `gene/serdes/write` as the canonical filesystem writer.
- [x] 3.2 Implement selector-driven `^externalize` so selected sub-values are written to deterministic child files/directories.
- [x] 3.3 Replace externalized sub-values in parent payloads with explicit `read_file` / `read_dir` forms.
- [x] 3.4 Reject malformed selectors, unsafe generated child IDs, name collisions, path escapes, unsupported target values, and externalization cycles.
- [x] 3.5 Add focused round-trip, deterministic naming, negative selector/path, and public-format tests.

## 4. S05 — Remove Old Tree Serdes Surface

- [x] 4.1 Remove `gene/serdes/read_tree` and `gene/serdes/write_tree` from the supported public namespace.
- [x] 4.2 Remove or retire old tree-serdes implementation paths that are no longer needed by `write`, `read_file`, or `read_dir`.
- [x] 4.3 Preserve existing canonical text serdes behavior for primitives, arrays, maps, Gene values, typed refs, enum/tuple values, named instances, and custom hooks.
- [x] 4.4 Add old API removal assertions and regression tests for existing runtime serdes identity behavior.

## 5. S06 — Public Cleanup and Full Gate

- [x] 5.1 Migrate GeneClaw storage helpers to `write`, `read`, `read_file`, and `read_dir`.
- [x] 5.2 Update public specs, docs, tests, and examples so they teach only the unified filesystem serializer.
- [x] 5.3 Run focused filesystem-serdes tests, old API removal assertions, GeneClaw storage helper smoke tests, `openspec validate replace-tree-serdes-with-file-refs --strict`, `nimble build`, and the full `./testsuite/run_tests.sh` gate.
- [x] 5.4 Document any remaining limitations as non-public implementation notes or future proposals, not as supported tree-serdes compatibility behavior.

## Verification Evidence

- 2026-05-15 final M012/S06 gate passed with exit code 0 in 18,955 ms: `bash scripts/verify_m012_s06_public_cleanup.sh && nim c -r tests/integration/test_filesystem_serdes_read_refs.nim && nim c -r tests/integration/test_filesystem_serdes_lazy_refs.nim && nim c -r tests/integration/test_filesystem_serdes_write_refs.nim && nim c -r tests/integration/test_filesystem_serdes_identity.nim && nim c -r tests/integration/test_filesystem_serdes_api_removal.nim && nim c -r tests/integration/test_geneclaw_home_storage.nim && openspec validate replace-tree-serdes-with-file-refs --strict && nimble build && ./testsuite/run_tests.sh`.
- Evidence artifacts: `.gsd/exec/dae3308d-13d4-43be-9aaf-883f36800f53.stdout` and `.gsd/exec/dae3308d-13d4-43be-9aaf-883f36800f53.stderr`.
- The final gate includes the public cleanup scan, focused read/lazy/write/identity/API-removal serializer tests, GeneClaw home storage smoke integration, OpenSpec strict validation, `nimble build`, and the full testsuite (`162` tests passed, `0` failed).
- Per D085, `read_dir ^lazy true` and creation-time ordering remain deferred/fail-closed future behavior. Public docs/specs/tests/examples teach only the supported eager `read_dir` model with `^shape array|map` and deterministic `^order name` ordering.
