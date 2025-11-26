## 1. Requirements & Alignment
- [ ] 1.1 Reconcile package MVP with existing module system change (`add-module-system`), noting any conflicts.
- [ ] 1.2 Confirm open questions with stakeholders (repository locations, package-of-packages, dependency substitution, alias mapping semantics).

## 2. Implementation (MVP)
- [ ] 2.1 Implement package root detection using nearest `package.gene` in current/ancestor directories; add tests.
- [ ] 2.2 Implement package entrypoint resolution order: `index.gene`, `lib/index.gene`, then prebuilt `build/index.gir`; add tests.
- [ ] 2.3 Enforce package name validation (regex + min segments) and reserved top-level namespaces; add tests.
- [ ] 2.4 Support imports of other packages’ entrypoints via `(import <sym> from \"index\" of <pkg>)` and intra-package module imports `(import <sym> from \"mod-x\")`; add tests.

## 3. Documentation & Validation
- [ ] 3.1 Document package usage (naming, load order, import forms) in language docs/examples.
- [ ] 3.2 Run relevant test suites (module/package resolution) and `openspec validate add-package-system --strict`.
