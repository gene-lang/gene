## MODIFIED Requirements

### Requirement: Selector Missing Values
Selector lookups SHALL return `void` when a key/index/member is not present.

#### Scenario: Missing map key
- **GIVEN** a map `{^a 1}`
- **WHEN** code evaluates `m/b`
- **THEN** the result is `void`

#### Scenario: Present nil value
- **GIVEN** a map `{^a nil}`
- **WHEN** code evaluates `m/a`
- **THEN** the result is `nil`

### Requirement: `/!` Strictness
The selector operator `/!` SHALL throw an exception when the current selector value is `void`.

#### Scenario: End-of-path assert
- **GIVEN** a map `{}` bound to `m`
- **WHEN** code evaluates `m/a/!`
- **THEN** an exception is thrown

#### Scenario: Mid-path assert
- **GIVEN** a map `{}` bound to `m`
- **WHEN** code evaluates `m/a/!/b`
- **THEN** an exception is thrown

## ADDED Requirements

### Requirement: Selector Match Locations
The system SHALL provide a way to represent selector matches as updatable locations, not just values.

#### Scenario: Selecting locations in a Gene tree
- **GIVEN** a Gene value representing a tree
- **WHEN** code selects matches using a selector
- **THEN** the result includes parent container + key/index needed to update

### Requirement: Selector-Based Updates
The system SHALL provide APIs to update all matched locations via selector-based rules.

#### Scenario: Update matched values
- **GIVEN** a target value and selector matching one or more values
- **WHEN** an update function is applied
- **THEN** each matched location is mutated consistently

