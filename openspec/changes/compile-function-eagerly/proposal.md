## Why

`gene compile` currently emits `IkFunction` instructions whose bodies are compiled lazily at runtime. Tooling like `gene gir show` therefore lacks visibility into nested function bytecode unless the program executes. We want an eager compilation mode for `gene compile` that still preserves the existing lazy semantics for `gene run`.

## What Changes
- Extend `gene compile` with an eager-function flag (default TBD). When enabled, the compiler precompiles each function body encountered and embeds the resulting `CompilationUnit` in the accompanying `IkData` instruction.
- Define a new payload structure stored in `IkData` that carries both the scope tracker and an optional compiled body. In lazy scenarios the compiled body remains nil.
- Update GIR serialization/deserialization to persist the embedded compiled bodies so cached modules keep the eager data.
- Leave `gene run` unchanged; it continues to lazily compile function bodies when executed.

## Impact
- Improves inspection workflows by making compiled output self-contained.
- Introduces modest compile-time and GIR-size growth when the eager flag is used.
- Requires GIR version bump/compatibility handling to read older files that lack the new payload.
