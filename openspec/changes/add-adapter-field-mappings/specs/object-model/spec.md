## ADDED Requirements

### Requirement: External Adapters Implement Interface Fields With Explicit Mappings
External `implement` bodies SHALL support explicit field mappings for fields declared by the target interface. An adapter field mapping SHALL implement the interface-visible property and SHALL NOT declare class storage or implicit adapter storage.

#### Scenario: Adapter maps an interface field directly to a differently named wrapped field
- **GIVEN** an interface `Readable` declares `(field name String)`
- **AND** a class `DataBuffer` stores the same concept in `/label`
- **WHEN** an external implementation declares:

```gene
(implement Readable for DataBuffer
  (field name ^from label))
```

- **THEN** `(Readable buffer)/name` reads `buffer/label`
- **AND** assigning through `(Readable buffer)/name` updates `buffer/label` when the interface field is writable
- **AND** the implementation uses direct adapter field forwarding rather than an implicit getter/setter method

#### Scenario: Adapter maps an interface field to a computed value
- **GIVEN** an interface declares `(field display_name String)`
- **WHEN** an external adapter field accessor computes the value from the wrapped object
- **THEN** reading the interface field returns the computed value
- **AND** no storage field is created on the adapter merely because the mapping exists

### Requirement: Adapter Bodies Access Wrapped Values Through Wrapped Pseudo-Member
External adapter implementation bodies SHALL expose the wrapped value through `/_wrapped`. The name `wrapped` SHALL mean the value wrapped by the external adapter and SHALL NOT declare or imply adapter-owned state.

#### Scenario: Adapter method reads wrapped value through `_wrapped`
- **GIVEN** an external adapter method body needs to call a method on the wrapped value
- **WHEN** the method body evaluates `(/_wrapped .get_data)`
- **THEN** Gene dispatches `.get_data` on the wrapped value

#### Scenario: Adapter accessor reads wrapped field through `_wrapped`
- **GIVEN** an external adapter accessor body needs to read field `state` from the wrapped value
- **WHEN** the accessor evaluates `/_wrapped/state`
- **THEN** Gene reads `state` from the wrapped value

#### Scenario: Legacy `_genevalue` is not the new adapter API
- **WHEN** adapter field mapping documentation or new tests refer to the wrapped value
- **THEN** they use `/_wrapped`
- **AND** the public `/_genevalue` adapter API is retired unless another accepted spec still owns it

### Requirement: Direct Wrapped-Field Mappings Use A Fast Field Forwarding Path
An external adapter field mapping using `^from` SHALL map an interface field directly to a member of the wrapped value. Direct wrapped-field mappings SHALL NOT be lowered to hidden Gene methods or accessor functions.

#### Scenario: Direct mapping reads wrapped value field
- **GIVEN** an external implementation declares `(field name ^from label)`
- **WHEN** code reads `adapted/name`
- **THEN** the adapter reads `/_wrapped/label` through the direct field mapping
- **AND** no user-visible or implicit `get` method is invoked

#### Scenario: Direct mapping writes wrapped value field
- **GIVEN** an external implementation declares `(field name ^from label)`
- **AND** the interface field is writable
- **WHEN** code assigns to `adapted/name`
- **THEN** the adapter writes the assigned value to `/_wrapped/label` through the direct field mapping
- **AND** no user-visible or implicit `set` method is invoked

#### Scenario: Direct mapping write fails when wrapped field cannot be assigned
- **GIVEN** an external implementation declares `(field name ^from label)`
- **AND** the wrapped value does not support assignment to `label`
- **WHEN** code assigns to `adapted/name`
- **THEN** Gene reports an adapter field mapping diagnostic
- **AND** the assignment does not silently create or update adapter-owned state

#### Scenario: Direct mapping target must be a member name
- **WHEN** an external implementation declares a `^from` mapping whose target is not a member name
- **THEN** Gene reports an adapter field mapping diagnostic

### Requirement: Accessor Field Mappings Use Method-Like Blocks For Computed Fields
An explicit adapter field accessor mapping SHALL include exactly one `get` accessor with an empty parameter list and MAY include exactly one `set` accessor with one named parameter. Accessors SHALL be method-like implementation blocks invoked by field access or assignment, not public interface methods.

#### Scenario: Get-only accessor mapping is readable
- **GIVEN** an external implementation declares:

```gene
(field status
  (get [] /_wrapped/state))
```

- **WHEN** code reads the adapted field
- **THEN** the getter is evaluated and its result is returned
- **AND** `get` is not exposed as a method named `get` on the adapted value

#### Scenario: Set accessor handles writes
- **GIVEN** an external implementation declares a `set` accessor for an adapter field
- **WHEN** code assigns to the adapted field
- **THEN** the setter is evaluated with the assigned value
- **AND** `set` is not exposed as a method named `set` on the adapted value

#### Scenario: Accessor mapping uses adapter-owned state directly
- **GIVEN** an external adapter declares owned field `(field cached_status String)`
- **AND** an interface field mapping declares:

```gene
(field status
  (get [] /cached_status)
  (set [v] (/cached_status = v)))
```

- **WHEN** code reads or writes `adapted/status`
- **THEN** the accessor reads or writes the declared adapter-owned field directly
- **AND** no `/_geneinternal` pseudo-member is required

#### Scenario: Missing getter in accessor mapping is rejected
- **WHEN** an external implementation declares an accessor-style field mapping without `get`
- **THEN** Gene reports an adapter field mapping diagnostic

#### Scenario: Invalid accessor arity is rejected
- **WHEN** a field mapping declares `(get [x] ...)` or `(set [] ...)`
- **THEN** Gene reports an adapter field mapping diagnostic

#### Scenario: Unknown accessor form is rejected
- **WHEN** a field mapping declares an accessor-style child other than `get` or `set`
- **THEN** Gene reports an adapter field mapping diagnostic

#### Scenario: Duplicate accessor blocks are rejected
- **WHEN** a field mapping declares more than one `get` block or more than one `set` block
- **THEN** Gene reports an adapter field mapping diagnostic

#### Scenario: Direct and accessor mapping forms cannot be mixed
- **WHEN** an external implementation declares a field mapping with both `^from` and `get` or `set` accessor forms
- **THEN** Gene reports an adapter field mapping diagnostic

### Requirement: External Adapters Declare Owned State With Direct Fields
External adapter implementations SHALL support typed adapter-owned field declarations for supplemental state. Adapter-owned fields SHALL be accessed directly inside adapter implementation bodies and SHALL NOT be visible through the adapted interface surface unless an explicit field mapping or method exposes them. Normal public slash access on an adapted value SHALL match the implemented interface surface; private owned-field debugging or introspection is out of scope for this change.

#### Scenario: Adapter constructor initializes a declared owned field
- **GIVEN** an external adapter declares `(field stored_birth_year Int)`
- **WHEN** its constructor executes `(/stored_birth_year = birth_year)`
- **THEN** the adapter stores `birth_year` in adapter-owned state
- **AND** later adapter method or accessor bodies can read `/stored_birth_year` directly

#### Scenario: Adapter-owned field backs an interface field mapping
- **GIVEN** interface `Ageable` declares `(field birth_year Int ^readonly true)`
- **AND** an external adapter declares:

```gene
(implement Ageable for Int
  (field stored_birth_year Int)
  (ctor [birth_year]
    (/stored_birth_year = birth_year))
  (field birth_year
    (get [] /stored_birth_year)))
```

- **WHEN** code reads `(Ageable 2026 1990)/birth_year`
- **THEN** the value comes from the adapter-owned field `stored_birth_year`
- **AND** the field mapping itself does not allocate or initialize that state

#### Scenario: Adapter-owned fields are not public interface fields
- **GIVEN** an external adapter declares owned field `(field cached_status String)`
- **AND** the target interface does not declare `cached_status`
- **WHEN** code reads `adapted/cached_status` through the adapter interface surface
- **THEN** Gene reports that `cached_status` is not declared on the interface

#### Scenario: Debug access to adapter-owned fields is not normal slash access
- **GIVEN** an adapted value has private adapter-owned field `cached_status`
- **WHEN** code outside the adapter implementation body reads `adapted/cached_status`
- **THEN** the read is rejected as normal public interface access
- **AND** any future debug or introspection access requires a separate explicit API

#### Scenario: Assignment to undeclared adapter-owned field is rejected
- **WHEN** an adapter implementation body assigns to `/cached_status`
- **AND** the external implementation did not declare `(field cached_status TypeExpr)` as adapter-owned state
- **THEN** Gene reports an adapter-owned field diagnostic when the adapter context is statically identifiable
- **AND** the assignment does not implicitly create adapter-owned state or an interface field mapping

#### Scenario: Legacy `_geneinternal` is not the new owned-state API
- **WHEN** adapter-owned state documentation or new tests refer to supplemental adapter state
- **THEN** they use declared adapter-owned fields and direct `/field_name` access inside adapter implementation bodies
- **AND** the public `/_geneinternal` adapter API is retired unless another accepted spec still owns it
- **AND** normal public slash access still rejects private adapter-owned fields unless an explicit mapping or method exposes them

### Requirement: Adapter-Owned Field Names Do Not Conflict With Interface Fields
An adapter-owned field declaration SHALL NOT use a name declared as a field by the target interface. Gene SHALL report conflicts during compiler/checker validation when interface metadata is statically available and SHALL also reject the implementation at registration time for dynamically resolved interfaces.

#### Scenario: Owned field conflicts with interface field
- **GIVEN** interface `Ageable` declares `(field birth_year Int)`
- **WHEN** an external adapter implementation declares `(field birth_year Int)` as owned state
- **THEN** Gene reports an adapter-owned field conflict diagnostic

#### Scenario: Non-conflicting owned field is accepted
- **GIVEN** interface `Ageable` declares `(field birth_year Int)`
- **WHEN** an external adapter implementation declares `(field stored_birth_year Int)` as owned state
- **THEN** the owned field declaration is accepted

#### Scenario: Duplicate adapter-owned fields are rejected
- **WHEN** an external adapter implementation declares the same adapter-owned field name more than once
- **THEN** Gene reports an adapter-owned field diagnostic

### Requirement: Explicit Adapter Field Mappings Take Precedence Over Same-Name Fallback
When reading or writing a field through an external adapter, an explicit adapter field mapping SHALL take precedence over the wrapped value's same-name member. If no explicit mapping exists, the adapter SHALL preserve the existing same-name fallback behavior for interface-declared fields.

#### Scenario: Explicit field mapping overrides same-name wrapped field
- **GIVEN** a wrapped value has a field named `name`
- **AND** the external adapter also defines an explicit mapping for interface field `name`
- **WHEN** code reads `adapted/name`
- **THEN** the explicit adapter mapping is used instead of direct same-name fallback

#### Scenario: Same-name fallback remains available
- **GIVEN** an interface declares `(field name String)`
- **AND** an external implementation does not define a field mapping for `name`
- **AND** the wrapped value exposes `name`
- **WHEN** code reads `adapted/name`
- **THEN** the adapter uses the existing same-name fallback behavior

### Requirement: External Adapter Validation Remains Scoped To Declared Mappings
External adapter registration SHALL validate declared field mappings and adapter-owned field declarations without requiring every interface field to have an explicit mapping. Interface fields without explicit mappings SHALL use existing same-name fallback when accessed and SHALL fail at access when neither an explicit mapping nor fallback exists.

#### Scenario: Partial adapter with unmapped interface field remains valid
- **GIVEN** an interface declares fields `name` and `status`
- **WHEN** an external implementation declares a valid mapping for `name` and no mapping for `status`
- **THEN** implementation registration accepts the declared mapping without requiring a `status` mapping
- **AND** reading `adapted/status` uses same-name fallback if the wrapped value exposes `status`
- **AND** reading `adapted/status` reports an adapter/interface field diagnostic if no fallback member exists

### Requirement: Adapter Field Writes Respect Readonly And Getter-Only Boundaries
Adapter field assignment SHALL respect the target interface field's readonly policy and the explicit mapping's shape. Setter declarations for readonly interface fields SHALL be rejected during compiler/checker validation when interface field metadata is statically available and SHALL also be rejected during implementation registration for dynamically resolved interfaces.

#### Scenario: Readonly interface field rejects adapter write
- **GIVEN** an interface declares `(field id Int ^readonly true)`
- **AND** an external adapter defines a field mapping for `id`
- **WHEN** code assigns to `adapted/id`
- **THEN** the write is rejected through the adapter

#### Scenario: Setter on readonly interface field is rejected
- **GIVEN** an interface declares `(field id Int ^readonly true)`
- **WHEN** an external adapter mapping for `id` declares a `set` accessor
- **THEN** implementation registration reports an adapter field mapping diagnostic

#### Scenario: Direct mapping on readonly interface field is read-only through adapter
- **GIVEN** an interface declares `(field id Int ^readonly true)`
- **AND** an external adapter declares `(field id ^from raw_id)`
- **WHEN** code reads `adapted/id`
- **THEN** the direct mapping returns `/_wrapped/raw_id`
- **WHEN** code assigns to `adapted/id`
- **THEN** the write is rejected through the adapter

#### Scenario: Interface field readonly flag is preserved for field syntax
- **GIVEN** an interface declares `(field id Int ^readonly true)`
- **WHEN** the interface is registered
- **THEN** the interface property metadata records `id` as readonly

#### Scenario: Get-only adapter field rejects writes
- **GIVEN** an external accessor mapping declares `get` but no `set`
- **AND** the interface field is not readonly
- **WHEN** code assigns to the field through the adapter
- **THEN** the write is rejected with an adapter field diagnostic

### Requirement: Adapter Field Mappings Are Limited To Interface-Declared Fields
An external adapter field mapping SHALL target a field declared by the interface being implemented. Unknown interface-field mappings SHALL be rejected during compiler/checker validation when interface metadata is statically available and SHALL also be rejected during implementation registration for dynamically resolved interfaces.

#### Scenario: Mapping unknown interface field is rejected
- **GIVEN** interface `Readable` does not declare `display_name`
- **WHEN** an external implementation for `Readable` declares `(field display_name ^from label)`
- **THEN** implementation registration reports an adapter field mapping diagnostic

#### Scenario: Duplicate adapter field mappings are rejected
- **GIVEN** interface `Readable` declares `(field name String)`
- **WHEN** an external implementation for `Readable` declares more than one mapping for `name`
- **THEN** Gene reports an adapter field mapping diagnostic
