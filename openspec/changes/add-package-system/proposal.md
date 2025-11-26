## Why
Package behaviour is currently undocumented and ad hoc (notes in `tmp/packages.md`). We need a minimal, clear spec for how Gene packages are named and resolved so imports can be deterministic and safe.

## What Changes
- Define MVP package resolution: finding the package root via `package.gene`, selecting the package entrypoint (`index.gene` or `src/index.gene` or built GIR), and resolving intra-package modules.
- Specify package name rules and reserved namespaces to prevent collisions.
- Clarify the import form for consuming another package’s entrypoint vs modules within the same package.
- Capture open questions for repository/alias/substitution behaviour beyond the MVP.

## Impact
- Affected specs: package-system
- Affected code: module/package resolver, import compiler/vm path handling, validation for package names; future repository/alias plumbing once clarified
