## ADDED Requirements

### Requirement: CString Interop for Native Extensions

The native extension ABI SHALL distinguish managed Gene `String` values from C
string interop and SHALL provide length-aware UTF-8 string conversion helpers.

#### Scenario: Create a Gene string from a length-delimited UTF-8 buffer

- **GIVEN** a native extension receives the UTF-8 bytes for `"你"` and an
  explicit byte length of `3`
- **WHEN** it converts that buffer through the host string-conversion API
- **THEN** the resulting Gene value SHALL be a `String`
- **AND** its value SHALL be `"你"`.

#### Scenario: Native code can read borrowed UTF-8 bytes and byte length

- **GIVEN** a native extension receives the Gene string `"你好"`
- **WHEN** it requests a borrowed C string view and byte length through the host
  ABI
- **THEN** the pointer SHALL reference UTF-8 text suitable for C interop
- **AND** the reported byte length SHALL be `6`.

### Requirement: CString Safety Rules

The runtime SHALL document and enforce ownership, lifetime, and embedded-NUL
rules for `CString` interop.

#### Scenario: Embedded NUL is rejected for CString marshalling

- **GIVEN** a native call expects `CString`
- **WHEN** Gene attempts to marshal a `String` containing an embedded NUL byte
- **THEN** the runtime SHALL fail deterministically
- **AND** the error SHALL instruct the caller to use a byte-oriented path
  instead.
