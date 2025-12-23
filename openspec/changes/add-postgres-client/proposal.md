# Proposal: Add PostgreSQL Client

## Why

Gene currently has SQLite support (`src/genex/sqlite.nim`) but lacks PostgreSQL client functionality. Adding PostgreSQL support enables Gene applications to connect to production databases commonly used in enterprise environments.

## What Changes

- **ADDED**: New `src/genex/postgres.nim` extension module with PostgreSQL client API
- **ADDED**: `genex/postgres` namespace in Gene with `open` function and `Connection` class
- **ADDED**: `Connection.exec(sql, ...params)` - executes query and returns results as array of arrays
- **ADDED**: `Connection.execute(sql, ...params)` - executes statement without returning results (for INSERT/UPDATE/DELETE)
- **ADDED**: `Connection.close()` - closes the database connection
- **MODIFIED**: Build system (`gene.nimble`) to include postgres extension compilation
- **MODIFIED**: Project dependencies to require `db_postgres` Nim module

## Impact

- **Affected specs**: New capability - `postgres` database client
- **Affected code**:
  - New: `src/genex/postgres.nim` - PostgreSQL client implementation
  - New: `tests/test_stdlib_postgres.nim` - PostgreSQL client tests
  - Modified: `gene.nimble` - add `buildext` task for postgres library
  - Modified: `openspec/project.md` - document postgres in tech stack

## API Compatibility Notes

The new PostgreSQL client will maintain API compatibility with `src/genex/sqlite.nim` with the following proposed improvements:

1. **Unified Connection API**: Both `sqlite/open` and `postgres/open` return `Connection` instances with the same interface
2. **Parameter Binding**: Support for named parameters (PostgreSQL `$1`, `$2` style vs SQLite `?` style)
3. **Connection String**: PostgreSQL uses connection strings (`host=localhost port=5432...`) instead of file paths
