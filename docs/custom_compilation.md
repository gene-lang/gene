Custom Compilation Pipeline
===========================

Note: The implementation described here has been removed from the codebase. This document is kept for historical context in case we want to revive or redesign the feature later.

Goal
- Support user-defined “compile functions” that transform Gene AST into bytecode at runtime, splice the result into the caller, and then execute the generated instructions immediately (and reuse them on later calls).

Key pieces
- `compile` form (compiler.nim)
  - `(compile name matcher body...)` is recognized in `compile_compile`, which emits `IkCompileFn` followed by `IkData` carrying the captured `ScopeTracker`.
  - At runtime, `IkCompileFn` builds a `VkCompileFn` value (`to_compile_fn`), capturing:
    - `ns`: namespace at definition time.
    - `parent_scope`: current scope (ref-counted).
    - `scope_tracker`: clone of the compile-time tracker for locals/params.
    - `matcher`: argument matcher parsed from the form (second child).
    - `body`: the remaining children (often instruction literals like `$vm/PUSH`).
- `CompileFn` compilation
  - First call triggers `CompileFn.compile` (compiler.nim) to compile its body into a `CompilationUnit` with `kind = CkCompileFn` and `matcher` recorded. Subsequent calls reuse `body_compiled`.
  - Matcher behaves like regular functions: arguments are matched, defaults and splats respected, and the captured `scope_tracker` maps parameter names to slots.
- Execution and patching (vm.nim)
  - Calling a `CompileFn` builds a frame (`FkCompileFn`) with the resolved scope (reuse parent scope if matcher empty; otherwise `new_scope` + matcher slots). `frame.args` holds the call arguments.
  - When the `CompileFn` body returns, the VM sees `cu.kind == CkCompileFn` and expects the return value to be an array of instructions (VkInstruction values, optionally nested arrays).
  - The VM replaces the caller’s instruction slice `[start_pos, end_pos]` with the returned instructions:
    - `start_pos` comes from `caller_instr.arg0` (the instruction that initiated the call).
    - `end_pos` is the caller’s `pc` at return.
    - After replacement, `pc` is rewound to `start_pos` so the newly spliced bytecode runs immediately. Future executions reuse the patched code—no recompile.
- Building instructions in Gene
- The `vm` namespace (stdlib.nim) exposes helpers like `vm/PUSH`, `vm/ADD`, and `vm/compile` to construct `Instruction` values (`new_instr` wrappers).
- Typical pattern in tests: `(compile c _ [ ($vm/PUSH 1) ($vm/PUSH 2) ($vm/ADD) ])` returns a `CompileFn` that, when first called, emits those instructions to the caller and then runs them, producing `3`.

Caching & scope behavior
- A `CompileFn` compiles its body once (first call) and caches `body_compiled`.
- The generated instructions replace the caller slice, so later invocations in that caller run the already-spliced bytecode (no extra calls).
- Captured `parent_scope` and `scope_tracker` let the compile function reference surrounding bindings at definition time; matcher arguments are applied when the compile function itself is called.

Related instructions
- `IkCompileFn`: build `VkCompileFn` and capture scope/ns.
- `IkData`: follows `IkCompileFn` to carry `ScopeTracker`.
- `CkCompileFn`: marks compiled units so the VM knows to splice return instructions.
- `IkCompileInit`: helper to compile arbitrary AST at runtime (used by `vm/compile`).

Notes and limits
- Benefit: enables lightweight, user-defined “macro compiler” steps without touching Nim. For simple templates (e.g., drop a few `$vm/PUSH`/`ADD` ops) it can save overhead versus interpreting a Gene function, and the bytecode splice is cached in the caller.
- Complexity trade-off: as soon as the compile function needs richer logic (loops, conditionals, emits based on types), you’re effectively authoring a compiler in Gene. It will work—returned instruction arrays are spliced—but ergonomics suffer, and mistakes are easy (e.g., mismatched stack discipline, missing `IkData` when emitting `IkFunction`, no jump fix-ups).
- Tooling gaps: no peephole/flow validation on returned instructions, so advanced use (jump patching, scopes, captures) remains manual and error-prone. For anything beyond straight-line instruction lists or simple templates, a Nim-side extension or a dedicated mini-IR emitter would be safer.
