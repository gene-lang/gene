## 1. Runtime Type Representation
- [ ] 1.1 Extend runtime_types to parse/handle union, function, and applied type expressions.
- [ ] 1.2 Capture full type expressions from annotations (not just simple symbols).
- [ ] 1.3 Add runtime compatibility checks for union and function types.

## 2. Compiler + Checker Integration
- [ ] 2.1 Record inferred binding types from the type checker into runtime metadata.
- [ ] 2.2 Enforce binding types on var/assignment at runtime.
- [ ] 2.3 Ensure type metadata survives GIR serialization.

## 3. Tests
- [ ] 3.1 Add union type alias and runtime validation tests.
- [ ] 3.2 Add function type value compatibility tests.
- [ ] 3.3 Add inferred binding enforcement tests.
