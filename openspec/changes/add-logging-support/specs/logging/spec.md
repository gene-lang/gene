## ADDED Requirements

### Requirement: Logging Configuration File
The system SHALL load logging configuration from `config/logging.gene` rooted at the current working directory when the file exists.

#### Scenario: Missing config uses defaults
- **WHEN** `config/logging.gene` is absent
- **THEN** logging uses the default root level `INFO` and console output is enabled

### Requirement: Hierarchical Logger Levels
The system SHALL resolve logger levels using longest-prefix matching on logger names of the form `dir/file/ns/class`.

#### Scenario: Specific logger overrides directory level
- **WHEN** the config sets `examples` to `WARN` and `examples/app.gene:Http/Todo` to `ERROR`
- **AND** a log is emitted with logger name `examples/app.gene:Http/Todo`
- **THEN** the effective level is `ERROR`

### Requirement: Console Output Format
The system SHALL emit console logs in the fixed format:
`T00 LEVEL yy-mm-dd Wed HH:mm:ss.xxx dir/file/ns/class message`.

#### Scenario: Format includes level and logger name
- **WHEN** a log at level `INFO` is emitted with logger name `examples/app.gene`
- **THEN** the output contains the `INFO` level and `examples/app.gene` logger name in the fixed format

### Requirement: Gene Logging API
The system SHALL provide a `genex/logging/Logger` class with level methods and constructors that accept a class or namespace reference (not instances).

#### Scenario: Logger constructed from class
- **WHEN** a class initializes `/logger = (new Logger self)` in its body
- **THEN** `(logger .info "hello")` emits an INFO log using the class logger name
