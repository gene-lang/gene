## ADDED Requirements

### Requirement: WASM Build Profile and Artifact Contract
The project SHALL provide a WASM build profile that compiles Gene runtime code to browser-loadable WASM artifacts.

#### Scenario: Build wasm artifacts with Emscripten
- **WHEN** the user runs `nimble wasm` with `emcc` available
- **THEN** the build SHALL produce `web/gene_wasm.js` and `web/gene_wasm.wasm`
- **AND** the build SHALL use a wasm profile define (`gene_wasm`)

#### Scenario: Missing emcc reports actionable error
- **WHEN** the user runs `nimble wasm` without `emcc` on `PATH`
- **THEN** the task SHALL fail early with installation/activation guidance

### Requirement: WASM Evaluation Entry ABI
The WASM build SHALL expose a stable C ABI function for evaluating Gene source text.

#### Scenario: Evaluate source through exported ABI
- **WHEN** host code calls `gene_eval(code)` with valid Gene source
- **THEN** the runtime SHALL parse, compile, and execute that source
- **AND** return output/result text as a `cstring`

#### Scenario: Evaluation failure is returned as error text
- **WHEN** host code calls `gene_eval(code)` with source that fails compile/runtime checks
- **THEN** `gene_eval` SHALL return a textual error result
- **AND** SHALL NOT crash the WASM runtime

### Requirement: WASM Host ABI for Effectful Operations
In `gene_wasm` mode, runtime effects that require host integration SHALL route through host ABI wrappers.

#### Scenario: Clock and randomness use host ABI
- **WHEN** wasm runtime evaluates code that needs current time or random values
- **THEN** the values SHALL come from host ABI functions

#### Scenario: File operations use host ABI wrappers
- **WHEN** wasm runtime evaluates file existence/read/write operations
- **THEN** runtime calls SHALL be routed through host ABI wrappers instead of direct OS filesystem calls

### Requirement: Deterministic Unsupported-Feature Behavior in WASM
Features that are not supported in wasm mode SHALL fail deterministically with a stable error code.

#### Scenario: Unsupported thread operation in wasm
- **WHEN** code executes thread APIs in `gene_wasm` mode
- **THEN** runtime SHALL fail with `GENE.WASM.UNSUPPORTED`
- **AND** include the unsupported feature name in the error message

#### Scenario: Unsupported native extension loading in wasm
- **WHEN** code executes native extension loading in `gene_wasm` mode
- **THEN** runtime SHALL fail with `GENE.WASM.UNSUPPORTED`
- **AND** include the unsupported feature name in the error message

#### Scenario: Unsupported process or socket server operation in wasm
- **WHEN** code executes process/shell or server-socket APIs in `gene_wasm` mode
- **THEN** runtime SHALL fail with `GENE.WASM.UNSUPPORTED`
- **AND** include the unsupported feature name in the error message

### Requirement: Native Build Non-Regression
Adding wasm support SHALL NOT change native runtime behavior by default.

#### Scenario: Native build remains default
- **WHEN** users build Gene without selecting a wasm profile
- **THEN** native build behavior SHALL remain unchanged
- **AND** existing native runtime capabilities SHALL stay enabled
