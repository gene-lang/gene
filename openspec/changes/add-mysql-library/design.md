# MySQL Library Design

## Architecture Overview

The MySQL library follows the same architectural pattern as the existing SQLite library:

1. **Connection Management**: Global thread-safe connection table with unique IDs
2. **Wrapper Pattern**: `ConnectionWrapper` object managing `DbConn` and closed state
3. **Native Functions**: VM-integrated functions for MySQL operations
4. **Class Integration**: Connection and Statement classes in Gene type system
5. **Namespace Organization**: `genex/mysql` namespace with all MySQL functionality

## Technical Design

### Connection Management
```nim
type
  ConnectionWrapper = ref object of RootObj
    conn*: DbConn
    closed*: bool

var connection_table {.threadvar.}: Table[system.int64, ConnectionWrapper]
var next_conn_id {.threadvar.}: system.int64
```

### API Design
- `mysql/open(path)` - Opens MySQL connection
- `connection.exec(sql, ...params)` - Executes query returning results
- `connection.execute(sql, ...params)` - Executes statement without results
- `connection.close()` - Closes connection

### Parameter Binding
Supports all Gene value types:
- `VkNil` → SQL NULL
- `VkBool` → 1/0 integer
- `VkInt` → 64-bit integer
- `VkFloat` → double precision float
- `VkString` → string
- Other types → string conversion

### Error Handling
- Database connection errors
- SQL execution errors
- Invalid parameter errors
- Resource cleanup errors

## Integration Points

### VM Integration
- Native function registration using `def_native_method`
- Value conversion between Gene and MySQL types
- Exception handling with Gene's exception system

### Build Integration
- Extends `buildext` task in `gene.nimble`
- Compiles to `build/libmysql.dylib`
- Uses existing extension loading infrastructure

### Namespace Integration
- `genex.mysql` namespace for all MySQL functionality
- Connection and Statement class registration
- Open function registration in namespace