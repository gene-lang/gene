## 1. Design Decisions
- [x] 1.1 Confirm canonical function type syntax: `(Fn [^a A ^b B C D] R)`.
- [x] 1.2 Decide class field typing strategy (`^fields` declarations vs inference from ctor).
- [x] 1.3 Decide default type-check mode (strict by default vs opt-in flag).

## 2. Parser & AST
- [x] 2.1 Define type AST representation and parsing for type expressions (primitives, generics, unions, functions).
- [x] 2.2 Parse type annotations on vars, params, returns, and class members.
- [x] 2.3 Thread type metadata through AST/IR for the checker.
- [x] 2.4 Parse labeled parameter types (`^name Type`) in function type signatures.

## 3. Type Checker
- [x] 3.1 Implement type environment + unification/inference for literals, vars, and calls.
- [x] 3.2 Type-check function bodies and return types.
- [x] 3.3 Type-check class fields and method calls (including `super`).
- [x] 3.4 Add clear error diagnostics for mismatches and unknown types.
- [x] 3.5 Validate keyword argument maps against labeled parameter types.
- [x] 3.6 Enforce arity: reject extra positional or unknown keyword arguments.

## 4. CLI + Tests
- [x] 4.1 Wire type-checking into CLI (`gene check` and/or `gene run --typecheck`).
- [x] 4.2 Add Nim tests for parser + checker.
- [x] 4.3 Add Gene testsuite cases for typed code and errors.
- [ ] 4.4 Update docs/examples to match the new syntax rules.
