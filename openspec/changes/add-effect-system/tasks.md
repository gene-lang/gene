## 1. Spec & Design
- [x] 1.1 Draft effect-system spec delta
- [x] 1.2 Finalize design notes for effect representation and checking
- [x] 1.3 Validate change with `openspec validate add-effect-system --strict`

## 2. Implementation
- [x] 2.1 Extend `TypeExpr` (TkFn) to carry effects and update `type_to_string`
- [x] 2.2 Parse effect annotations in function definitions and `Fn` type expressions
- [x] 2.3 Track allowed effects in `TypeChecker` and enforce at call sites
- [x] 2.4 Propagate effect metadata through compiler/AST props
- [x] 2.5 Add tests for effect annotations and enforcement
- [x] 2.6 Run `nimble build` and `./testsuite/run_tests.sh`
