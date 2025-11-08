## 1. Compiler Updates
- [x] 1.1 Add an eager compilation option to `gene compile` CLI parsing.
- [x] 1.2 Emit a new `VkFunctionDef` payload in the `IkData` following each `IkFunction`, carrying scope tracker + optional compiled body.
- [x] 1.3 When eager mode is active, compile function bodies up front and store them in the payload; otherwise leave the compiled body nil.

## 2. Runtime & Serialization
- [x] 2.1 Update VM `IkFunction` handling to consume the new payload and attach precompiled bodies when present.
- [x] 2.2 Extend GIR save/load to serialize the embedded compiled bodies and remain backward compatible with older GIRs.

## 3. Validation & Docs
- [x] 3.1 Add tests covering eager vs lazy compilation outputs (instruction listings and GIR round-trip).
- [x] 3.2 Document the new CLI option in help text and developer docs.
