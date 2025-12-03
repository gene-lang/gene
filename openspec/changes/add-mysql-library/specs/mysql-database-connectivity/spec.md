# MySQL Database Connectivity

## ADDED Requirements

### Requirement: Open MySQL Database Connection
The system SHALL provide functionality to open MySQL database connections with proper authentication and error handling, supporting both connection string and parameter-based connection methods.

#### Scenario: Successful connection opening
```gene
(var conn (mysql/open "mysql://user:pass@localhost:3306/database"))
(assert (not (is_nil conn)))
(assert (eq (. conn class) "Connection"))
```

#### Scenario: Connection with connection string parameters
```gene
(var conn (mysql/open "mysql://localhost:3306/testdb" "user" "password"))
(assert (not (is_nil conn)))
```

#### Scenario: Invalid connection string should raise exception
```gene
(try
  (mysql/open "invalid://connection/string")
catch * ex
  (assert (contains ($ ex) "Failed to open database"))
)
```

### Requirement: Execute SELECT Queries and Return Results
The system SHALL provide functionality to execute SELECT queries on MySQL connections and return result sets as Gene arrays, supporting parameterized queries with proper type conversion.

#### Scenario: Simple SELECT query execution
```gene
(var conn (mysql/open "mysql://localhost:3306/testdb"))
(var results (conn/exec "SELECT 1 as test_col"))
(assert (eq (len results) 1))
(assert (eq (len (results/0)) 1))
(assert (eq ((results/0)/0) "1"))
```

#### Scenario: SELECT query with parameters
```gene
(var conn (mysql/open "mysql://localhost:3306/testdb"))
(var results (conn/exec "SELECT ? as number, ? as text" 42 "hello"))
(assert (eq (len results) 1))
(assert (eq ((results/0)/0) "42"))
(assert (eq ((results/0)/1) "hello"))
```

#### Scenario: Multiple row result handling
```gene
(var conn (mysql/open "mysql://localhost:3306/testdb"))
(var results (conn/exec "SELECT 1 UNION SELECT 2"))
(assert (eq (len results) 2))
```

### Requirement: Execute Non-SELECT SQL Statements
The system SHALL provide functionality to execute INSERT/UPDATE/DELETE statements on MySQL connections without returning result sets, supporting parameterized statements with proper error handling.

#### Scenario: INSERT statement execution
```gene
(var conn (mysql/open "mysql://localhost:3306/testdb"))
(var result (conn/execute "INSERT INTO test_table (name) VALUES (?)", "test"))
(assert (is_nil result))  # execute returns nil for non-SELECT
```

#### Scenario: UPDATE statement execution
```gene
(var conn (mysql/open "mysql://localhost:3306/testdb"))
(var result (conn/execute "UPDATE test_table SET name = ? WHERE id = ?", "updated", 1))
(assert (is_nil result))
```

#### Scenario: DELETE statement execution
```gene
(var conn (mysql/open "mysql://localhost:3306/testdb"))
(var result (conn/execute "DELETE FROM test_table WHERE id = ?", 1))
(assert (is_nil result))
```

### Requirement: Support All Gene Value Types in SQL Parameters
The system SHALL support binding all Gene value types (nil, bool, int, float, string) as SQL parameters in MySQL queries with proper type conversion from Gene values to MySQL-compatible types.

#### Scenario: Boolean parameter binding
```gene
(var conn (mysql/open "mysql://localhost:3306/testdb"))
(var results (conn/exec "SELECT ? as bool_val" true))
(assert (eq ((results/0)/0) "1"))  # true becomes 1
```

#### Scenario: Integer parameter binding
```gene
(var conn (mysql/open "mysql://localhost:3306/testdb"))
(var results (conn/exec "SELECT ? as int_val" 42))
(assert (eq ((results/0)/0) "42"))
```

#### Scenario: Float parameter binding
```gene
(var conn (mysql/open "mysql://localhost:3306/testdb"))
(var results (conn/exec "SELECT ? as float_val" 3.14))
(assert (contains ((results/0)/0) "3.14"))
```

#### Scenario: String parameter binding
```gene
(var conn (mysql/open "mysql://localhost:3306/testdb"))
(var results (conn/exec "SELECT ? as string_val" "hello"))
(assert (eq ((results/0)/0) "hello"))
```

#### Scenario: NULL parameter binding
```gene
(var conn (mysql/open "mysql://localhost:3306/testdb"))
(var results (conn/exec "SELECT ? as null_val" NIL))
(assert (eq ((results/0)/0) ""))  # NULL becomes empty string
```

### Requirement: Close MySQL Connections Properly
The system SHALL provide functionality to properly close MySQL connections and clean up associated resources, with proper state management to prevent operations on closed connections.

#### Scenario: Successful connection closing
```gene
(var conn (mysql/open "mysql://localhost:3306/testdb"))
(var result (conn/close))
(assert (is_nil result))
```

#### Scenario: Operations on closed connection should raise exception
```gene
(var conn (mysql/open "mysql://localhost:3306/testdb"))
(conn/close)
(try
  (conn/exec "SELECT 1")
catch * ex
  (assert (contains ($ ex) "Connection is closed"))
)
```

### Requirement: Handle MySQL Errors Gracefully
The system SHALL handle MySQL errors gracefully by converting them to Gene exceptions with meaningful error messages, allowing proper error handling using Gene's exception handling system.

#### Scenario: Invalid SQL syntax
```gene
(var conn (mysql/open "mysql://localhost:3306/testdb"))
(try
  (conn/exec "INVALID SQL SYNTAX")
catch * ex
  (assert (contains ($ ex) "SQL execution failed"))
)
```

#### Scenario: Non-existent table error
```gene
(var conn (mysql/open "mysql://localhost:3306/testdb"))
(try
  (conn/exec "SELECT * FROM non_existent_table")
catch * ex
  (assert (contains ($ ex) "SQL execution failed"))
)
```

## MODIFIED Requirements

### Requirement: Extend Build System for MySQL Library Compilation
The build system SHALL be extended to compile MySQL extension library alongside existing extensions, ensuring proper dependency management and library loading integration.

#### Scenario: Buildext task includes MySQL library
```bash
nimble buildext
# Should compile both libsqlite.dylib and libmysql.dylib
ls build/
# Should contain libmysql.dylib
```

#### Scenario: MySQL library is properly linked
The built MySQL library should be discoverable and loadable by the Gene runtime when MySQL functionality is used.

## Cross-Reference to Related Capabilities

- **SQLite Database Connectivity** (existing): MySQL implementation should follow the same API pattern as SQLite for consistency
- **Type System Integration** (existing): All Gene value types should be properly convertible to MySQL parameter types
- **Exception Handling** (existing): MySQL errors should integrate with Gene's existing exception handling system