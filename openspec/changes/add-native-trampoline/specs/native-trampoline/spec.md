## ADDED Requirements

### Requirement: Trampoline-enabled native calls
When native code generation is enabled, the system SHALL allow a natively compiled function to call a statically resolvable callable (Gene function, native function, or bound method) via a VM trampoline, provided both caller and callee have complete type annotations for arguments and return value.

#### Scenario: Typed helper call runs under native code
- **GIVEN** a function `square` with typed parameters and return type
- **AND** a function `sum_of_squares` with typed parameters and return type that calls `square`
- **WHEN** running with `--native-code`
- **THEN** execution succeeds and returns the correct result

### Requirement: Untyped or dynamic call targets are not native-eligible
The system SHALL reject native compilation for any function that calls a callee without type annotations or whose call target is not resolvable at compile time.

#### Scenario: Untyped callee disables native compilation
- **GIVEN** a function `helper` without type annotations
- **AND** a typed function `f` that calls `helper`
- **WHEN** running with `--native-code`
- **THEN** `f` runs via the VM (native compilation is not used)
