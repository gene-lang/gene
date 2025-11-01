## Why
Gene's module/import system is incomplete, limiting code reuse, namespacing, and package structure. A first-class module system is needed for scalable programs and libraries.

## What Changes
- Define a deterministic module resolution algorithm (relative and workspace-based)
- Add `import` and `export` semantics with explicit symbol lists and aliases
- Support module initialization order and cyclic import detection
- Persist module metadata in GIR for faster cold starts
- Expose module loader hooks for testing and tooling

## Impact
- Affected specs: language-module-system
- Affected code: `src/gene/parser.nim`, `src/gene/compiler.nim`, `src/gene/vm.nim`, `src/gene/gir.nim`, `src/gene/types.nim`, `tests/test_module.nim`, `testsuite/`

