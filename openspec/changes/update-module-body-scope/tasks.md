## 1. Implementation
- [x] 1.1 Update module compilation to use a lexical scope distinct from the module namespace
- [x] 1.2 Ensure `/`-prefixed symbols in module bodies write to the module namespace
- [x] 1.3 Wire module init `self` binding (explicit or implicit) without exporting locals
- [x] 1.4 Update type checker for module-local bindings and explicit `self`
- [x] 1.5 Add/adjust tests for local vs exported module bindings
- [x] 1.6 Update docs to describe explicit module exports via `/`
