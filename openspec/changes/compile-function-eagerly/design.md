## Overview

We want `gene compile` to optionally emit function bodies eagerly so inspection tools (pretty listings, GIR dumps) can see the full bytecode without executing the program, while keeping `gene run` lazy. Rather than introducing new containers for compiled bodies, we embed the eagerly compiled `CompilationUnit` directly in the `IkData` that already follows every `IkFunction`.

## Key Decisions

1. **Two-instruction contract**
   - Every function definition already emits `IkFunction` followed by `IkData` carrying the scope tracker. We codify this and extend the payload to also hold an optional compiled body.

2. **Embedding strategy**
   - Define a new reference type (e.g. `FunctionDefInfo`) stored in the `IkData`. It contains:
     - `scope_tracker`: existing snapshot for closures
     - `compiled_body`: optional `CompilationUnit` (nil when lazy)
   - `gene compile --eager` fills both fields; default compile/run populates only the scope tracker.

3. **Compilation flow**
   - Add compiler flag for eager mode.
   - When emitting `IkFunction`, eagerly compile the body using the function’s matcher/scope tracker (same as existing `compile*(f: Function)` helper) and tuck the resulting CU into the payload.
   - The top-level compiler remains unaware of runtime scope objects; eager compilation never needs the actual parent scope.

4. **Runtime wiring**
   - VM’s `IkFunction` branch reads the `IkData` payload, restores the scope tracker, and, if a compiled body is present, assigns it to `f.body_compiled`. Lazy cases still trigger runtime compilation as before.

5. **Serialization**
   - Extend GIR save/load to serialize the new payload record, including nested `CompilationUnit`s. This preserves eager bodies across cache files.

6. **CLI surface**
   - `gene compile` gains a flag (e.g. `--eager`) or defaults to eager behaviour; `gene run` remains unchanged.

## Alternatives Considered

- **Function table on CompilationUnit**: rejected to avoid global indexing and keep data localized to the instruction pair.
- **New module-level object**: unnecessary for this change; embedding in `IkData` keeps modifications minimal.

## Risks & Mitigations

- **Binary size growth**: eager mode may inflate GIR files; document the trade-off and keep lazy mode available.
- **Deserialization complexity**: ensure GIR versioning handles the new payload; guard old files by defaulting missing bodies to nil.
