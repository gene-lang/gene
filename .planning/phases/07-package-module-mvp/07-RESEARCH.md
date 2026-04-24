# Phase 07 Research: Package/module MVP

## Current State

Phase 07 should stabilize the package/module MVP around existing code, not
replace it. The repository already contains several package-system pieces:

- `src/gene/vm/module.nim` detects package roots, binds `$pkg`, resolves
  package-qualified imports, reads `package.gene.lock`, and searches `.gene/deps`.
- `src/commands/deps.nim` parses `package.gene`, resolves local/path and Git
  dependencies, writes `package.gene.lock`, verifies hashes, and provides
  `install`, `update`, `verify`, `gc`, and `clean`.
- `src/commands/package_context.nim` wires CLI package context into `run`,
  `eval`, `pipe`, and `repl`.
- `tests/integration/test_cli_package_context.nim`,
  `tests/integration/test_cli_run.nim`, `tests/integration/test_deps_command.nim`,
  and `tests/integration/test_package.nim` cover parts of the current behavior.

The main gap is integration and public contract clarity. Manifest parsing is
duplicated and partial, package metadata is exposed mostly as `.name`, docs
still say there is no lockfile story, and tests do not yet prove the full MVP
flow from manifest to dependency lockfile to package-aware import resolution.

## Phase Requirements

Phase 07 covers:

- `PKG-01`: parse `package.gene` metadata into a package model.
- `PKG-02`: expose current package metadata through `$pkg` or replacement.
- `PKG-03`: support local/path dependency declarations and deterministic
  diagnostics.
- `PKG-04`: package-aware imports honor package root, source directory, local
  dependencies, direct paths, and lockfile data.
- `PKG-05`: generate and verify a local `package.gene.lock`.
- `PKG-06`: document the MVP boundary and out-of-scope registry/version solver.

## Implementation Findings

### Manifest Parsing

`src/commands/deps.nim` has a private `PackageManifest` and parser for
`^name`, `^version`, `^globals`, `^singleton`, `^native`, `^native-build`, and
`^dependencies`. `src/gene/vm/module.nim` separately reads only the manifest
name through `package_manifest_name`.

Best implementation path:

- Extract a shared parser into a VM-level module such as
  `src/gene/vm/package_manifest.nim`.
- Keep the parser dependency-light: parser + types + os/strutils/tables only.
- Support both flat pair form and single-map form, because existing manifests
  and lockfiles use both shapes.
- Add fields for `^main-module`, `^source-dir`, `^test-dir`, `^license`,
  `^homepage`, and extra props.
- Reuse the shared parser from `src/commands/deps.nim` and
  `src/gene/vm/module.nim` to avoid divergent manifest behavior.

### Package Model And `$pkg`

`Package` already has fields for `dir`, `name`, `version`, `license`,
`src_path`, `test_path`, `asset_path`, `build_path`, `load_paths`,
`init_modules`, and `props`. The current `build_package_value` fills default
paths and `name`, but not version/source/main/test metadata from the manifest.

Best implementation path:

- Populate `Package` from the shared manifest model in
  `package_value_for_module`.
- Preserve `$pkg/.name` behavior.
- Add focused `Package` methods for at least `.name`, `.version`, `.dir`,
  `.source_dir`, `.main_module`, and `.test_dir` in both stdlib registration
  paths that currently define `Package`.
- Keep unknown manifest fields in `Package.props` for future use, but only
  document the MVP fields.

### Local Dependencies And Lockfile

`gene deps` already materializes dependencies into `.gene/deps`, writes
`package.gene.lock`, verifies hash drift, rejects invalid source combinations,
and supports lockfile mode. `src/gene/vm/module.nim` already reads lockfile
root dependencies and importer node dependency maps.

Best implementation path:

- Keep `gene deps` as the canonical lockfile writer.
- Add tests for deterministic diagnostics that are not yet covered: invalid
  names, missing path sources, malformed lockfiles, subdir escape, and package
  mismatch.
- Prove transitive lockfile lookup with a test where a dependency imports its
  own dependency through its node-level `^dependencies` map.
- Keep registry and complete version solving out of scope.

### Package-aware Imports

Current import resolution already has deterministic tiers:

1. importer directory
2. package bases
3. workspace fallback

For package-qualified imports, the loader resolves root via `^path`, runtime
`$dep` registry, lockfile, `.gene/deps`, search paths, and sibling fallback.
The missing MVP pieces are using manifest `^source-dir` and `^main-module`
instead of only hard-coded `src` and `index`, plus tests that prove precedence.

Best implementation path:

- Make package module bases use manifest `^source-dir` while retaining `src`,
  `lib`, and `build` fallbacks where needed.
- Make package entrypoint resolution honor `^main-module` before defaulting to
  `index`.
- Add tests for source-dir override, main-module entrypoint, lockfile root
  dependency import, transitive dependency import, direct relative import, and
  boundary rejection.

## Validation Architecture

Phase 07 validation must prove the complete MVP flow:

1. `package.gene` metadata parses into a package model.
2. `$pkg` exposes that package model during `run`, `eval`, and module import.
3. `gene deps install` creates a lockfile for local/path dependencies.
4. `gene deps verify` validates the lockfile.
5. Package-qualified imports use the lockfile and package source directories.
6. Public docs state exactly what is MVP and what remains future work.

Required focused tests:

- `nim c -r tests/integration/test_package_manifest.nim`
- `nim c -r tests/integration/test_cli_package_context.nim`
- `nim c -r tests/integration/test_deps_command.nim`
- `nim c -r tests/integration/test_cli_run.nim`
- `nim c -r tests/integration/test_package.nim`

Run `nimble testintegration` if shared module/package resolution code changes.

## Out Of Scope

- Registry lookup or hosted package index.
- Full semver solving across remote package versions.
- Native package signing or trust policy.
- Remote dependency cache deduplication.
- Reworking the module system beyond package-aware deterministic lookup.
