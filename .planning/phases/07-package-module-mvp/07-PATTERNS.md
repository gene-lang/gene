# Phase 07 Pattern Map

## Existing Patterns To Reuse

| Existing file | Pattern | Phase 07 use |
|---------------|---------|--------------|
| `src/gene/vm/module.nim` | Package root discovery, package-qualified import lookup, lockfile parser, module resolution tiers, structured import errors with `GENE.PACKAGE.*` codes. | Extend in place for manifest-driven package metadata, source-dir/main-module lookup, and lockfile-backed dependency tests. |
| `src/commands/deps.nim` | Dependency manifest parsing, local/path materialization, lockfile writer, `deps install/update/verify/gc/clean` command shape. | Extract shared manifest parsing and keep deps as the canonical lockfile writer. |
| `src/commands/package_context.nim` | CLI package discovery and `$pkg`/`$app.pkg` binding for run/eval/repl. | Add manifest source/main metadata support while preserving cwd behavior. |
| `src/commands/run.nim`, `src/commands/eval.nim`, `src/commands/pipe.nim`, `src/commands/repl.nim` | Command-level package context initialization and virtual module names. | Keep all CLI package context behavior consistent and test the command paths that expose `$pkg`. |
| `src/gene/stdlib/core.nim` and `src/gene/stdlib/gene_meta.nim` | Duplicate current `Application.pkg` and `Package.name` registration paths. | Add Package metadata methods in both places unless one path is deleted in the same change with tests proving no regression. |
| `tests/integration/test_cli_package_context.nim` | Temp package roots, command handlers, `$pkg` and `$app.pkg` assertions. | Extend for package metadata fields and manifest source/main behavior. |
| `tests/integration/test_deps_command.nim` | Temp manifest/dependency directories and direct command handler assertions. | Extend for deterministic dependency diagnostics, lockfile content, verify failures, and local dependency MVP. |
| `tests/integration/test_cli_run.nim` | CLI package import resolution, lockfile graph, boundary rejection, workspace precedence. | Extend for source-dir/main-module and transitive lockfile resolution. |
| `docs/package_support.md` | Public package/module implementation guide. | Rewrite from stale "marker only" language to the actual Phase 07 MVP boundary. |
| `docs/proposals/future/packaging.md` | Proposed lockfile and dependency semantics. | Promote only the implemented local/path lockfile subset into current docs; leave registry/solver/native trust as future. |

## Target File Additions

- `src/gene/vm/package_manifest.nim` - shared parser/model for `package.gene`.
- `tests/integration/test_package_manifest.nim` - focused parser/model tests.

## Documentation Patterns

- Keep `docs/package_support.md` as the current implementation contract.
- Update `spec/08-modules.md` for package-aware import behavior that is part of
  the language-facing module contract.
- Update `docs/feature-status.md` only after implementation and tests prove the
  Phase 07 subset; do not mark registry or full version solving stable.

## Anti-Patterns To Avoid

- Do not keep separate manifest parsers in `deps.nim` and `module.nim`.
- Do not make package-qualified imports fall back to floating search paths
  before lockfile resolution when a lockfile maps the dependency.
- Do not implement registry/network resolution in this phase.
- Do not treat single-segment package names as stable package names. They can
  remain as compatibility aliases only where existing `$dep ... ^path` tests
  require it.
- Do not broaden `Package` public methods beyond manifest fields that are
  parsed and tested in this phase.
