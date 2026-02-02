## Why
Module bodies currently write directly into the module namespace, which makes explicit `self` parameters unsafe and forces all top-level bindings to be exported. We want module bodies to behave like function bodies so locals remain local and exports are explicit.

## What Changes
- **BREAKING**: Module body bindings are local by default; only `/`-prefixed symbols write to the module namespace.
- Module init may use an explicit `self` parameter without changing module scope semantics.
- Update tests and docs to reflect explicit module exports via `/`.

## Impact
- Affected specs: module-body-scope (new)
- Affected code: src/gene/compiler.nim, src/gene/vm.nim, src/gene/types.nim, src/gene/type_checker.nim, testsuite/, tests/
