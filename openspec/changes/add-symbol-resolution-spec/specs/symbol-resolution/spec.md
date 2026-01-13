## ADDED Requirements

### Requirement: Reserved keywords and literals
The language SHALL treat the following symbols as reserved keywords handled by the parser/compiler and SHALL NOT allow them to be redefined: `if`, `elif`, `else`, `fn`, `fnx`, `class`, `var`, `loop`, `break`, `continue`, `return`, `try`, `catch`, `finally`, `throw`, `import`, `ns`, `macro`, `new`, `nil`, `void`, `true`, `false`.

#### Scenario: Keyword rebinding is rejected
- **WHEN** a program attempts to bind a reserved keyword (for example `(var if 1)`)
- **THEN** the compiler SHALL reject the program and SHALL NOT create the binding.

### Requirement: Nil literal uses `nil`
The language SHALL recognize `nil` as the nil literal, and `NIL` SHALL be treated as a normal symbol subject to standard resolution rules.

#### Scenario: Nil literal evaluates to nil
- **WHEN** a program evaluates the literal `nil`
- **THEN** the value SHALL be the nil literal.

#### Scenario: Void literal evaluates to void
- **WHEN** a program evaluates the literal `void`
- **THEN** the value SHALL be the void value.

#### Scenario: Uppercase NIL is not reserved
- **WHEN** a program evaluates `NIL`
- **THEN** the symbol SHALL be resolved using standard symbol resolution rules.

### Requirement: Built-in namespaces
The language SHALL expose the built-in namespaces `gene` and `genex`, which are accessible from any scope only through explicit prefixes (`gene/...`, `genex/...`).

#### Scenario: Built-in namespace access
- **WHEN** a program references `gene/Object`
- **THEN** the lookup SHALL resolve to the `Object` member of the `gene` namespace.

#### Scenario: No implicit fallback to built-in namespaces
- **WHEN** a program references `Object` without an explicit `gene/` or `genex/` prefix
- **THEN** resolution SHALL NOT treat it as `gene/Object` or `genex/Object`.

### Requirement: Global variables via `$` prefix
Global variables SHALL be referenced and assigned using the `$` prefix, and `$name` SHALL resolve to the global binding regardless of local or namespace bindings. The `global/` prefix SHALL NOT be treated as a global-variable namespace.

#### Scenario: Global lookup bypasses local bindings
- **WHEN** a local `x` exists and code evaluates `$x`
- **THEN** the global `x` binding SHALL be returned.

#### Scenario: Global assignment updates the global binding
- **WHEN** a program evaluates `($debug = true)`
- **THEN** the global `debug` binding SHALL be updated to `true`.

#### Scenario: `global/` does not access globals
- **WHEN** a program references `global/x`
- **THEN** the symbol SHALL be resolved using normal namespace rules and SHALL NOT read or write the global `x` binding.

### Requirement: Global assignment validation
Global assignments SHALL be compiled to call the built-in `global_set` function, which validates write permissions and rejects writes to read-only system globals (`$ex`, `$env`).

#### Scenario: Global assignment compiles to validation
- **WHEN** a program evaluates `($x = 1)`
- **THEN** the compiler SHALL emit a call equivalent to `(global_set "x" 1)`.

#### Scenario: Read-only globals reject writes
- **WHEN** a program evaluates `($env = {})` or `($ex = 1)`
- **THEN** the runtime SHALL raise an error and SHALL NOT update the binding.

### Requirement: Global access concurrency rules
Direct reads and assignments to `$name` SHALL be atomic with respect to other threads. Nested mutations of global data (for example `$shared_data/x = 1`) SHALL require `synchronized` guarding the global root; otherwise the runtime SHALL NOT guarantee consistent results.

#### Scenario: Atomic global assignment
- **WHEN** one thread evaluates `($flag = true)` while another thread reads `$flag`
- **THEN** the read SHALL observe either the value before or after the assignment.

#### Scenario: Nested mutation without synchronization
- **WHEN** a program performs `$shared_data/x = 1` outside of `synchronized`
- **THEN** the runtime SHALL NOT guarantee consistent results.

### Requirement: Global synchronization
The language SHALL provide a `synchronized` form that executes its body while holding a global-access lock. The optional `^on` property SHALL specify a direct child of the global namespace as a string including the `$` prefix (for example `"$shared_data"`), consistent with how global variables are accessed elsewhere. Implementations SHALL treat the `^on` string as a direct global child name, not a path. When `^on` is provided, the lock SHALL apply only to that global child and its nested members; other global children remain accessible. Using `synchronized` without `^on` is discouraged; implementations MAY emit warnings.

#### Scenario: Lock covers the specified child
- **WHEN** a program executes `(synchronized ^on "$shared_data" ($shared_data/x = 1))`
- **THEN** other threads SHALL be blocked from accessing `$shared_data` or `$shared_data/x` until the block completes.

#### Scenario: Unrelated globals remain accessible
- **WHEN** one thread holds `(synchronized ^on "$shared_data" ...)` and another thread accesses `$other_data`
- **THEN** the second thread SHALL NOT be blocked by the lock.

#### Scenario: Omitted `^on` locks all globals
- **WHEN** a program executes `(synchronized ...)` without an `^on` property
- **THEN** the runtime SHALL prevent other threads from accessing any global variables until the block completes.

### Requirement: Unprefixed symbol resolution order
Unprefixed symbols SHALL be resolved in the following order: local scope, enclosing scopes, current namespace, then parent namespaces up to root. Automatic resolution SHALL NOT search global variables or built-in namespaces.

#### Scenario: Local scope wins over namespace
- **WHEN** a name exists in both the local scope and the current namespace
- **THEN** the local binding SHALL be used.

#### Scenario: Parent namespace fallback
- **WHEN** a name is not found in the current namespace but exists in a parent namespace
- **THEN** the parent namespace binding SHALL be used.

### Requirement: Special variables
The language SHALL provide context-bound variables: `self` inside method bodies, `$ex` inside `catch` blocks, and `$env` for environment access. `$ex` SHALL be thread-local even though it uses the `$` prefix.

#### Scenario: `self` in method bodies
- **WHEN** a method body references `self`
- **THEN** it SHALL resolve to the current instance.

#### Scenario: `$ex` in catch blocks
- **WHEN** a `catch *` block executes
- **THEN** `$ex` SHALL refer to the current exception object.

#### Scenario: `$ex/message` returns the exception message
- **WHEN** a `catch *` block evaluates `$ex/message`
- **THEN** the value SHALL be the exception message.

#### Scenario: `$ex` is thread-local
- **WHEN** two threads each catch different exceptions and read `$ex`
- **THEN** each thread SHALL see its own exception object.

#### Scenario: `$env` access
- **WHEN** code accesses `$env/HOME` or `($env .get "HOME" "/tmp")`
- **THEN** the environment value for `HOME` SHALL be returned, or the default if unset.

### Requirement: Namespace import aliasing
The `import` form SHALL bind a namespace alias into the current namespace using either the last path segment or an explicit alias.

#### Scenario: Import binds last segment
- **WHEN** a program evaluates `(import genex/llm)`
- **THEN** the current namespace SHALL bind `llm` to `genex/llm`.

#### Scenario: Import binds explicit alias
- **WHEN** a program evaluates `(import genex/llm:llm2)`
- **THEN** the current namespace SHALL bind `llm2` to `genex/llm`.
