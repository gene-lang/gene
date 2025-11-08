## 1. Parser
- [ ] 1.1 Add a hierarchical `SourceTrace` structure to the parser that mirrors AST shape and tracks filename, line, and column.
- [ ] 1.2 Teach `add_line_col` (and related helpers) to attach `SourceTrace` nodes to each produced `Gene` and maintain the enter/exit stack.

## 2. Compiler & GIR
- [ ] 2.1 Thread `SourceTrace` pointers through the compiler so emitted instructions capture the active trace node.
- [ ] 2.2 Persist and reload the source trace hierarchy inside GIR alongside the instruction stream.

## 3. Runtime
- [ ] 3.1 Update VM error reporting to consult the source trace when surfacing runtime exceptions.

## 4. Validation
- [ ] 4.1 Add parser/compiler tests that assert errors report filename, line, and column.
- [ ] 4.2 Add a runtime test (e.g., throwing from bytecode) that verifies location info appears in the raised exception.
