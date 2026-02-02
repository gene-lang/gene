## 1. Implementation
- [ ] 1.1 Update module compilation to use a lexical scope distinct from the module namespace
- [ ] 1.2 Ensure `/`-prefixed symbols in module bodies write to the module namespace
- [ ] 1.3 Wire module init `self` binding (explicit or implicit) without exporting locals
- [ ] 1.4 Update type checker for module-local bindings and explicit `self`
- [ ] 1.5 Add/adjust tests for local vs exported module bindings
- [ ] 1.6 Update docs to describe explicit module exports via `/`
