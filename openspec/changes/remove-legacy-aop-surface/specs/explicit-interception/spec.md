## ADDED Requirements

### Requirement: Remove legacy AOP public syntax
The system SHALL reject legacy AOP public definition and application forms and SHALL keep explicit interception as the only current interception API.

#### Scenario: Legacy aspect definition is rejected
- **WHEN** a Gene program evaluates `(aspect Legacy [target] (before target [] nil))`
- **THEN** the program fails instead of binding a legacy aspect definition
- **AND** the failure does not install any interception wrapper.

#### Scenario: Legacy class application method is unavailable
- **WHEN** a Gene program tries to apply interception with `.apply` on an interception definition
- **THEN** the program fails instead of using a legacy class application compatibility path
- **AND** the class method table remains unchanged.

#### Scenario: Legacy function application method is unavailable
- **WHEN** a Gene program tries to apply interception with `.apply-fn`
- **THEN** the program fails instead of returning a legacy function wrapper
- **AND** the original callable binding remains unchanged.

### Requirement: Remove legacy AOP toggle methods
The system SHALL remove `.enable-interception` and `.disable-interception` from the public runtime surface and SHALL require `/.enable` and `/.disable` for explicit interception controls.

#### Scenario: Legacy toggle method is unavailable
- **WHEN** a Gene program calls `.disable-interception` or `.enable-interception` on an interception definition or wrapper
- **THEN** the call fails instead of mutating interception enablement state.

#### Scenario: Explicit slash toggles remain supported
- **WHEN** a Gene program uses `Definition/.disable`, `Definition/.enable`, `wrapper/.disable`, or `wrapper/.enable`
- **THEN** the definition-level or application-level enablement state changes according to the explicit interception contract.

### Requirement: Preserve explicit interception behavior after AOP removal
The system SHALL preserve explicit class and function interception behavior while removing legacy AOP compatibility.

#### Scenario: Explicit class interception still works
- **WHEN** a class interceptor is defined with `(interceptor Audit [run])` and directly applied as `(Audit Service "run")`
- **THEN** the selected class method is wrapped
- **AND** enabled advice runs when the wrapped method is called.

#### Scenario: Explicit function interception still works
- **WHEN** a function interceptor is defined with `(fn-interceptor Trace [f])` and directly applied as `(Trace inc)`
- **THEN** the call returns a callable wrapper
- **AND** the original `inc` binding remains unmodified.

#### Scenario: Targeted diagnostics remain available
- **WHEN** an invalid explicit interception application occurs
- **THEN** the failure remains catchable
- **AND** the diagnostic includes the relevant `GENE.INTERCEPT` marker family.

### Requirement: Rename current tests and practical internals away from AOP
The system SHALL remove AOP terminology from current tests, docs, examples, OpenSpec deltas, diagnostics, and practical runtime-facing internals, except for explicitly historical or GSD audit artifacts.

#### Scenario: Testsuite no longer advertises AOP as current behavior
- **WHEN** the testsuite file list and testsuite docs are scanned after the change
- **THEN** current interception behavior is covered by interception-named fixtures
- **AND** no current fixture name presents `aop` as a supported feature category.

#### Scenario: Public docs no longer teach AOP syntax
- **WHEN** public docs, examples, feature-status, and OpenSpec files are scanned after the change
- **THEN** they do not present `(aspect ...)`, `.apply`, `.apply-fn`, `.enable-interception`, or `.disable-interception` as supported current APIs
- **AND** any remaining AOP wording is confined to explicit historical migration context.

#### Scenario: Practical internals use interception terminology
- **WHEN** maintainers inspect runtime-facing source names and assertions after the change
- **THEN** practical helpers, assertion names, and comments use interceptor/interception terminology where feasible
- **AND** any retained internal alias is local, documented, and invisible to Gene programs.
