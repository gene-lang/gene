## ADDED Requirements
### Requirement: Parser Provides Source Trace
The parser MUST build a hierarchical source-trace structure that mirrors the AST and records filename, line, and column for each node.

#### Scenario: Query location for parsed node
- **GIVEN** a Gene source file `foo.gene` containing `(println "hi")`
- **WHEN** the parser returns the root `Gene` node
- **THEN** accessing the node's source trace yields `foo.gene`, line `1`, column `1`.

### Requirement: Bytecode Preserves Source Locations
The compiler and GIR serializer MUST preserve the source-trace hierarchy so downstream tooling can retrieve source positions for emitted instructions.

#### Scenario: Compiler error includes source
- **GIVEN** a program that references an undefined symbol
- **WHEN** compilation fails
- **THEN** the error message includes the filename, line, and column reported by the active source trace.

#### Scenario: Runtime exception reports source
- **GIVEN** bytecode generated from a file that triggers a runtime exception
- **WHEN** the VM raises the exception during execution
- **THEN** the reported error message includes the originating filename, line, and column drawn from the preserved source trace.
