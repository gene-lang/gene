# PostgreSQL Database Client Specification

## ADDED Requirements

### Requirement: PostgreSQL Connection

The system SHALL provide a function to open PostgreSQL database connections using connection strings.

#### Scenario: Open PostgreSQL connection with valid connection string

- **GIVEN** the `genex/postgres` namespace is available
- **WHEN** `(genex/postgres/open "host=localhost port=5432 dbname=test user=postgres")` is called
- **THEN** a Connection instance is returned
- **AND** the connection is open and ready for queries

#### Scenario: Open PostgreSQL connection with URL format

- **GIVEN** the `genex/postgres` namespace is available
- **WHEN** `(genex/postgres/open "postgresql://user:password@localhost:5432/test")` is called
- **THEN** a Connection instance is returned
- **AND** the connection is open and ready for queries

#### Scenario: Open PostgreSQL connection fails with invalid connection string

- **GIVEN** the `genex/postgres` namespace is available
- **WHEN** `(genex/postgres/open "host=invalid port=9999")` is called
- **THEN** an exception is raised
- **AND** the exception message indicates connection failure

### Requirement: Query Execution with Results

The system SHALL provide a method to execute SQL queries that return result sets.

#### Scenario: Execute SELECT query returning rows

- **GIVEN** an open PostgreSQL connection
- **WHEN** `(conn .query "SELECT id, name FROM users WHERE active = $1" true)` is called
- **THEN** an array of row arrays is returned
- **AND** each row array contains column values as Gene Values
- **AND** column values are converted to appropriate Gene types (string, int, float, nil)

#### Scenario: Execute SELECT query with no results

- **GIVEN** an open PostgreSQL connection
- **WHEN** `(conn .query "SELECT * FROM users WHERE id = $1" 999)` is called and no rows match
- **THEN** an empty array is returned

#### Scenario: Execute SELECT query with multiple parameters

- **GIVEN** an open PostgreSQL connection
- **WHEN** `(conn .query "SELECT * FROM users WHERE age > $1 AND city = $2" 18 "New York")` is called
- **THEN** the query is executed with both parameters bound
- **AND** matching rows are returned

#### Scenario: Query with non-string SQL parameter

- **GIVEN** an open PostgreSQL connection
- **WHEN** the SQL argument is not a string
- **THEN** an exception is raised

### Requirement: Statement Execution Without Results

The system SHALL provide a method to execute SQL statements that do not return result sets.

#### Scenario: Execute INSERT statement

- **GIVEN** an open PostgreSQL connection
- **WHEN** `(conn .exec "INSERT INTO users (name, age) VALUES ($1, $2)" "Alice" 30)` is called
- **THEN** the statement is executed
- **AND** nil is returned

#### Scenario: Execute UPDATE statement

- **GIVEN** an open PostgreSQL connection
- **WHEN** `(conn .exec "UPDATE users SET age = $1 WHERE id = $2" 31 1)` is called
- **THEN** the statement is executed
- **AND** nil is returned

#### Scenario: Execute DELETE statement

- **GIVEN** an open PostgreSQL connection
- **WHEN** `(conn .exec "DELETE FROM users WHERE id = $1" 1)` is called
- **THEN** the statement is executed
- **AND** nil is returned

#### Scenario: Execute fails due to SQL error

- **GIVEN** an open PostgreSQL connection
- **WHEN** `(conn .exec "INSERT INTO nonexistent_table (col) VALUES ($1)" "value")` is called
- **THEN** an exception is raised
- **AND** the exception message indicates the SQL error

### Requirement: Connection Closing

The system SHALL provide a method to close PostgreSQL connections.

#### Scenario: Close open connection

- **GIVEN** an open PostgreSQL connection
- **WHEN** `(conn .close)` is called
- **THEN** the connection is closed
- **AND** nil is returned

#### Scenario: Execute on closed connection

- **GIVEN** a closed PostgreSQL connection
- **WHEN** `(conn .query "SELECT 1")` is called
- **THEN** an exception is raised
- **AND** the exception message indicates the connection is closed

#### Scenario: Close already closed connection

- **GIVEN** a closed PostgreSQL connection
- **WHEN** `(conn .close)` is called
- **THEN** no error occurs (idempotent)

### Requirement: Transaction Support

The system SHALL provide methods for transaction management.

#### Scenario: Begin transaction

- **GIVEN** an open PostgreSQL connection
- **WHEN** `(conn .begin)` is called
- **THEN** a transaction is started
- **AND** nil is returned

#### Scenario: Commit transaction

- **GIVEN** an open PostgreSQL connection with an active transaction
- **WHEN** `(conn .commit)` is called
- **THEN** the transaction is committed
- **AND** changes are persisted
- **AND** nil is returned

#### Scenario: Rollback transaction

- **GIVEN** an open PostgreSQL connection with an active transaction
- **WHEN** `(conn .rollback)` is called
- **THEN** the transaction is rolled back
- **AND** changes are discarded
- **AND** nil is returned

#### Scenario: Transaction isolation - rollback on error

- **GIVEN** an open PostgreSQL connection
- **WHEN** a transaction is begun
- **AND** an INSERT is executed
- **AND** a statement fails causing an error
- **AND** rollback is called
- **THEN** the INSERT is not persisted

### Requirement: Parameter Type Conversion

The system SHALL convert Gene Value types to appropriate PostgreSQL parameter types.

#### Scenario: Nil parameter converts to NULL

- **GIVEN** an open PostgreSQL connection
- **WHEN** `(conn .exec "INSERT INTO users (name) VALUES ($1)" NIL)` is called
- **THEN** NULL is inserted into the database

#### Scenario: Boolean parameter converts

- **GIVEN** an open PostgreSQL connection
- **WHEN** `(conn .exec "INSERT INTO users (active) VALUES ($1)" true)` is called
- **THEN** a boolean value is inserted

#### Scenario: Integer parameter converts

- **GIVEN** an open PostgreSQL connection
- **WHEN** `(conn .exec "INSERT INTO users (age) VALUES ($1)" 42)` is called
- **THEN** an integer value is inserted

#### Scenario: Float parameter converts

- **GIVEN** an open PostgreSQL connection
- **WHEN** `(conn .exec "INSERT INTO users (score) VALUES ($1)" 3.14)` is called
- **THEN** a float value is inserted

#### Scenario: String parameter converts

- **GIVEN** an open PostgreSQL connection
- **WHEN** `(conn .exec "INSERT INTO users (name) VALUES ($1)" "Alice")` is called
- **THEN** a string value is inserted

### Requirement: Result Type Conversion

The system SHALL convert PostgreSQL result values to appropriate Gene Value types.

#### Scenario: NULL result converts to Nil

- **GIVEN** a query returning NULL values
- **WHEN** results are fetched
- **THEN** NULL values are converted to Gene `NIL`

#### Scenario: Integer result converts

- **GIVEN** a query returning integer columns
- **WHEN** results are fetched
- **THEN** integers are converted to Gene `VkInt` values

#### Scenario: Float result converts

- **GIVEN** a query returning float columns
- **WHEN** results are fetched
- **THEN** floats are converted to Gene `VkFloat` values

#### Scenario: String result converts

- **GIVEN** a query returning text columns
- **WHEN** results are fetched
- **THEN** text values are converted to Gene `VkString` values

#### Scenario: Boolean result converts

- **GIVEN** a query returning boolean columns
- **WHEN** results are fetched
- **THEN** booleans are converted to Gene `VkBool` values
