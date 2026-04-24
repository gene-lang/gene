# Phase 07 Validation Strategy

status: planned
phase: 07-package-module-mvp
requirements: [PKG-01, PKG-02, PKG-03, PKG-04, PKG-05, PKG-06]

## Validation Approach

Phase 07 is a package workflow stabilization phase. Validation must prove that
manifest metadata, `$pkg`, dependency declarations, lockfiles, and package-aware
imports work together as one deterministic local MVP.

## Acceptance Checks

Run these checks after execution:

```bash
rg -n "PackageManifest|parse_package_manifest|main-module|source-dir|test-dir" src/gene/vm src/commands tests/integration
rg -n 'def_native_method\("(version|dir|source_dir|main_module|test_dir)"' src/gene/stdlib/core.nim src/gene/stdlib/gene_meta.nim
rg -n "package.gene.lock|root_dependencies|deps verify|Dependency cycle|subdir escapes|Package name" tests/integration/test_deps_command.nim tests/integration/test_cli_run.nim
nim c -r tests/integration/test_package_manifest.nim
nim c -r tests/integration/test_cli_package_context.nim
nim c -r tests/integration/test_deps_command.nim
nim c -r tests/integration/test_cli_run.nim
nim c -r tests/integration/test_package.nim
git diff --check
```

Because this phase changes module/package resolution code, also run:

```bash
nimble testintegration
```

## Requirement Coverage

| Requirement | Validation |
|-------------|------------|
| PKG-01 | Shared manifest parser tests cover `^name`, `^version`, `^source-dir`, `^main-module`, `^test-dir`, and `^dependencies`. |
| PKG-02 | CLI/package context tests assert `$pkg/.name`, `$pkg/.version`, `$pkg/.source_dir`, `$pkg/.main_module`, `$pkg/.test_dir`, and `$app/.pkg` metadata. |
| PKG-03 | Deps command tests cover valid local/path declarations and deterministic errors for malformed declarations. |
| PKG-04 | CLI run/import tests cover package root, manifest source directory, local dependency, direct relative import, lockfile resolution, transitive dependency lookup, and package boundary rejection. |
| PKG-05 | Deps command tests prove `package.gene.lock` generation and `deps verify` success/failure behavior. |
| PKG-06 | `docs/package_support.md`, `spec/08-modules.md`, and `docs/feature-status.md` state the MVP boundary and future registry/version-solver exclusions. |

## Verification Gate

Phase 07 is not complete until focused tests and `nimble testintegration` pass,
or any integration failure is documented as unrelated with concrete evidence.
