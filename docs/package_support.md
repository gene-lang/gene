# Package + Module Support in the Gene VM (current implementation)

This document describes what the current Nim VM actually implements for “packages” and `import`, and what is still only specified/aspirational.

## What “package” means today

In the current VM, a **package is primarily a filesystem convention**:

- The **package root** is the nearest ancestor directory that contains a `package.gene` file.
- The runtime does **not** currently parse `package.gene` for metadata; the file’s presence is used mainly as a **marker** for root detection and intra-package resolution.

Core implementation lives in `src/gene/vm/module.nim`.

## Import syntax supported by the parser/loader

The compiler turns `(import ...)` into a `VkGene` value containing:
- `type = import`
- `props` (e.g. `^pkg`, `^path`, `^native`)
- `children` representing the import clause

See `src/gene/compiler.nim` (`compile_import`) and `src/gene/vm/module.nim` (`parse_import_statement`, `handle_import`).

### Basic form

```gene
(import name from "mod")      # import `name` from a module path
(import from "mod" name)      # same meaning
```

### Aliases

```gene
(import name:alias from "mod")
```

### Nested imports

These forms resolve `n/f` paths inside a module namespace:

```gene
(import n/f from "mod")
(import n/[a b] from "mod")   # expands to imports n/a and n/b
```

### Namespace imports: `gene/*`, `genex/*`, `global/*`

Imports whose first path segment is one of `gene`, `genex`, or `global` are resolved directly against those namespaces (not via filesystem modules).

```gene
(import gene/json/parse)        # resolves under gene namespace
(import genex/http/*)           # wildcard imports all non-NIL members
```

**Dynamic genex extension loading**:

- Accessing `genex/<name>` may auto-load a dynamic library at `build/lib<name>.<ext>` (`.dylib`/`.so`/`.dll`) (`src/gene/vm/module.nim`, `src/gene/vm.nim`).

## Package-qualified imports

To import a module from another package, the loader supports:

- `of "<pkg-name>"` in the import children (spec form), and/or
- `^pkg "<pkg-name>"` as an import property (used in example projects).

Example:

```gene
(import upcase from "index" ^pkg "x/my_lib")
```

### Package name validation

Package names must:

- have **at least two segments** separated by `/`
- match the character rules described by:
  `validate_package_name` in `src/gene/vm/module.nim`
- not use reserved top-level namespaces: `gene`, `genex`, or any `gene*` prefix
- allow `x`, `y`, `z` as open top-level namespaces

Example valid names:

- `x/my_lib`
- `org/pkg-a`

Invalid:

- `my_lib` (only one segment)
- `gene/foo` (reserved)

## Package root discovery + search paths

### Root detection

`find_package_root(start_path)` walks up directories until it finds `package.gene` (`src/gene/vm/module.nim`).

### Search paths for `(import ... of "<pkg>")` / `^pkg`

`locate_package_root(package_name, importer_dir, override_path)` attempts:

1. **Override** via `^path` (relative to the importer’s package root if present, otherwise relative to importer_dir). The override target must contain `package.gene`.
2. Search bases constructed from:
   - `importer_dir`
   - `importer_dir/packages`
   - entries in `GENE_PACKAGE_PATH` (split by `PathSep`)
   - ancestors of `importer_dir` (walking upwards)
3. Fallback to a sibling of the current package root using the final segment of the package name.

This is intentionally an MVP; it is not a versioned dependency resolver.

## Entrypoint resolution

When importing `"index"` from a package, the loader chooses the entrypoint in priority order:

1. `<root>/index.gene`
2. `<root>/src/index.gene`
3. `<root>/lib/index.gene`
4. `<root>/build/index.gir`

See `resolve_package_entrypoint` in `src/gene/vm/module.nim`.

## Module resolution rules (filesystem)

For non-namespace imports (not `gene/*`, `genex/*`, `global/*`), the resolver searches:

- the importer directory
- the package root (if found)
- `<pkg>/src`, `<pkg>/lib`, `<pkg>/build`

It supports:
- explicit `.gene` and `.gir` paths
- implicit `.gene` extension
- build fallback: `<pkg>/build/<basename>.gir`
- native fallback: `<pkg>/build/<basename>.<ext>` (treated as native module)

See `resolve_module_path` and `resolve_native_module` in `src/gene/vm/module.nim`.

## Execution + caching model

- `ModuleCache` is a global `Table[string, Namespace]` keyed by resolved path (`src/gene/vm/module.nim`).
- On first import of a non-native module:
  - the VM compiles the module (`compile_module`)
  - executes it in a fresh frame with `ns = module_ns`
  - stores `module_ns` in `ModuleCache`
  - binds imported symbols into the importer namespace (`src/gene/vm.nim`, `src/gene/vm/module.nim`)
- Subsequent imports of the same path reuse the cached namespace.

**Note**: `ModuleCache` is currently not synchronized for multi-threaded imports.

## Native modules

Two ways to load native code:

1. Explicitly mark an import as native:

```gene
(import upcase from "my_lib/libindex.dylib" ^native true)
```

2. Let the loader auto-detect a corresponding compiled native library under `build/` for a resolved `.gene` module.

Native modules are loaded via `load_extension` when extensions are enabled (`src/gene/vm.nim`, `src/gene/vm/extension.nim`).

## `package.gene` manifest: what exists vs what is implemented

Example manifests in `example-projects/*/package.gene` contain fields like:

- `^name`, `^version`, `^license`
- `^main-module`, `^source-dir`, `^test-dir`
- `^dependencies` (with `($dep ...)`)
- `^globals`, `^auto_load`

However:

- The VM currently **does not read/interpret** these keys for resolution.
- `$dep` does not appear to have a runtime implementation in the VM codebase.
- `$pkg` (expected by `tests/test_package.nim`) is not currently wired up; the `Package` type exists in Nim (`src/gene/types/type_defs.nim`) but there is no loader that constructs it from `package.gene`.

So: **package manifests are presently “marker + metadata for future tooling”**, not an active dependency system.

## Spec alignment

There is an OpenSpec describing the MVP package loader requirements:

- `openspec/changes/add-package-system/specs/package-system/spec.md`

The implemented behavior around:
- nearest-ancestor `package.gene` root detection
- entrypoint resolution order
- import `of "<pkg>"` syntax
- package naming rules

matches that spec.

## Example projects (working patterns)

- `example-projects/my_app/src/index.gene` imports from a package:

```gene
(import upcase from "index" ^pkg "x/my_lib")
```

- `example-projects/my_lib/src/index.gene` loads a native library (explicit):

```gene
(import upcase from "my_lib/libindex.dylib" ^native true)
```

## Known mismatches / papercuts

- Some example project tests import `genex/tests/...`, but the current extension namespace is `genex/test` (singular). This is why running those tests directly can fail with “Symbol 'genex/tests/…' not found”.
- There is no version selection / lockfile / package installation story in the VM yet; only root detection + path search (`GENE_PACKAGE_PATH`) and direct imports.

