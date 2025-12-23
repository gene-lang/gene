# Design: PostgreSQL Client for Gene

## Context

Gene currently has SQLite support in `src/genex/sqlite.nim` using Nim's `db_connector/db_sqlite` module. The user wants PostgreSQL support with API compatibility to the existing SQLite client, with permission to propose API improvements since the project is in alpha.

### Existing SQLite API Analysis

From `src/genex/sqlite.nim`:

```nim
# Namespace: genex/sqlite
genex/sqlite/open(path: string) -> Connection

# Connection methods:
conn.exec(sql: string, ...params) -> array<array<Value>>  # Returns rows
conn.execute(sql: string, ...params) -> nil               # No results
conn.close() -> nil
```

**Issues identified**:
1. `exec` vs `execute` naming is confusing (both execute SQL, difference is return value)
2. No transaction support methods (`begin`, `commit`, `rollback`)
3. No prepared statement caching/reuse
4. No way to get last insert ID or rows affected
5. Global connection table with manual IDs is fragile

## Goals / Non-Goals

### Goals
- PostgreSQL client with API compatible to SQLite
- Unified database interface for future database additions
- Transaction support (begin, commit, rollback)
- Connection string support for PostgreSQL
- Proper parameter binding for PostgreSQL (`$1`, `$2` syntax)

### Non-Goals
- Async query execution (can be added later)
- Connection pooling (single connection per client instance)
- ORM or query builder
- Database migration tools

## Decisions

### Decision 1: Unified Database Interface

Create a common `genex/db` namespace with database-agnostic types and methods.

**Rationale**: Allows code to work with different databases by changing only the connection open call.

**Proposed API**:
```nim
# Database-agnostic types (in genex/db)
genex/db/Connection  # Base Connection class
genex/db/Statement   # Prepared statement (future)

# Database-specific modules
genex/sqlite/open(path: string) -> Connection
genex/postgres/open(conn_string: string) -> Connection

# Unified Connection methods
conn.query(sql: string, ...params) -> array<array<Value>>  # SELECT
conn.exec(sql: string, ...params) -> nil                    # INSERT/UPDATE/DELETE
conn.execute(sql: string, ...params) -> nil                 # Alias for exec
conn.begin() -> nil
conn.commit() -> nil
conn.rollback() -> nil
conn.close() -> nil
```

### Decision 2: API Naming Changes

**BREAKING**: Rename SQLite's `exec` → `query` for clarity.

**Rationale**: `exec` is ambiguous - does it return results? `query` clearly indicates data retrieval, `exec` clearly indicates mutation.

**Migration**: Existing SQLite code using `exec` will need to change to `query`. Since project is alpha, this is acceptable.

### Decision 3: PostgreSQL Library

Use Nim's standard `db_connector/db_postgres` module.

**Rationale**:
- Part of Nim's standard db_connector family (same as db_sqlite)
- Well-maintained and stable
- Consistent API with other db_* modules

**Alternatives considered**:
- `asyncpg`: Async-only, adds complexity
- `ndbex`: Extension module, not core
- `debby`: Higher-level ORM, not needed

### Decision 4: Connection String Format

PostgreSQL uses standard libpq connection strings:

```
"host=localhost port=5432 dbname=mydb user=postgres password=secret"
```

OR URL format:
```
"postgresql://user:password@localhost:5432/mydb"
```

**Decision**: Support both formats, pass through to libpq.

### Decision 5: Parameter Binding

PostgreSQL uses positional parameters (`$1`, `$2`, ...) vs SQLite's `?`.

**Decision**: User writes SQL with database-specific parameter syntax. This is documented as part of the API.

```gene
# SQLite
(db .query "SELECT * FROM users WHERE id = ?" 123)

# PostgreSQL
(db .query "SELECT * FROM users WHERE id = $1" 123)
```

## Architecture

### Module Structure

```
src/genex/
├── db.nim           # New: Shared database types and utilities
├── sqlite.nim       # Modified: Use shared Connection type
└── postgres.nim     # New: PostgreSQL client
```

### Implementation Approach

1. **Shared Types** (`db.nim`):
   - `DatabaseConnection` ref object
   - `bind_gene_param` proc for type-to-SQL conversion
   - Shared error handling

2. **PostgreSQL** (`postgres.nim`):
   - `vm_open` - connection from connection string
   - `vm_query` - execute SELECT, return rows
   - `vm_exec` - execute INSERT/UPDATE/DELETE
   - `vm_begin`, `vm_commit`, `vm_rollback`
   - `vm_close`
   - Register `genex/postgres` namespace

3. **SQLite Refactor** (`sqlite.nim`):
   - Rename `exec` → `query` (BREAKING)
   - Add transaction methods
   - Use shared types from `db.nim`

### File Organization

```nim
# db.nim - Shared database infrastructure
type
  DatabaseConnection = ref object
    closed*: bool

proc bind_gene_param(...)

# sqlite.nim - SQLite client
type
  SQLiteConnection = ref object of DatabaseConnection
    conn*: DbConn

# postgres.nim - PostgreSQL client
type
  PostgresConnection = ref object of DatabaseConnection
    conn*: DbConn
```

## Risks / Trade-offs

### Risk: Breaking API Changes

**Risk**: Renaming `exec` → `query` breaks existing SQLite code.

**Mitigation**: Project is in alpha; breaking changes are acceptable. Document migration clearly.

### Risk: libpq Dependency

**Risk**: PostgreSQL requires libpq (C library) to be installed.

**Mitigation**:
- Document dependency in README
- libpq is widely available (most systems have it)
- Can be installed via package manager

### Trade-off: Database-Specific SQL

**Trade-off**: Users must write database-specific SQL (parameters, function names).

**Decision**: Acceptable. Full SQL abstraction is out of scope. This is a database client, not an ORM.

## Migration Plan

### Phase 1: Add PostgreSQL
1. Create `src/genex/db.nim` with shared types
2. Create `src/genex/postgres.nim`
3. Add to `gene.nimble` buildext task
4. Write tests

### Phase 2: Refactor SQLite
1. Modify `src/genex/sqlite.nim` to use shared types
2. Rename `exec` → `query`
3. Update tests

### Phase 3: Documentation
1. Update `CLAUDE.md` with database client docs
2. Add examples for both SQLite and PostgreSQL

## Open Questions

1. **Should we add a `rows_affected` return value for `exec`?**
   - SQLite: `db.getRowsAffected()` after execution
   - PostgreSQL: Different approach needed
   - **Decision**: Defer to future enhancement

2. **Should we support named parameters?**
   - Would allow `:name` style parameters
   - Requires additional parsing layer
   - **Decision**: Use native database parameter syntax for simplicity

3. **Connection pooling?**
   - Useful for web applications
   - Adds complexity
   - **Decision**: Defer until requested (async support needed first)

4. **Prepared statement caching?**
   - Performance optimization
   - Adds state management complexity
   - **Decision**: Defer until profiling shows need
