## MODIFIED Requirements
### Requirement: Compile command output fidelity
The `gene compile` command MUST support eager compilation of function bodies by embedding precompiled bytecode in the `IkData` paired with each `IkFunction`, while `gene run` maintains lazy compilation semantics.

#### Scenario: Eager compilation flag enabled
- **WHEN** a user runs `gene compile --eager examples/foo.gene`
- **THEN** every `IkFunction` emitted is immediately followed by an `IkData` whose payload contains both the scope tracker and the precompiled `CompilationUnit`
- **AND** inspecting the GIR reveals function bodies without executing the program

#### Scenario: Lazy execution unchanged
- **WHEN** a user invokes `gene run examples/foo.gene`
- **THEN** the `IkData` payload contains a nil compiled body and the VM lazily compiles functions at runtime, preserving current behaviour
