# Implementation Tasks

## 1. Foundation
- [ ] 1.1 Create `src/genex/db.nim` with shared database types
  - [ ] Define `DatabaseConnection` ref object with `closed` field
  - [ ] Create `bind_gene_param` proc for Value to SQL parameter conversion
  - [ ] Create `collect_params` helper for extracting positional arguments
  - [ ] Add error handling utilities
- [ ] 1.2 Add `db_postgres` to project dependencies
  - [ ] Update `gene.nimble` to require `db_postgres` (alongside `db_connector`)
  - [ ] Document libpq system dependency in README

## 2. PostgreSQL Client Implementation
- [ ] 2.1 Create `src/genex/postgres.nim` module
- [ ] 2.2 Implement connection management
  - [ ] `PostgresConnection` type (inherits from `DatabaseConnection`)
  - [ ] `vm_open` proc - accepts connection string, returns Connection instance
  - [ ] `vm_close` proc - closes PostgreSQL connection
  - [ ] Connection tracking via instance properties (`__conn_id__`)
- [ ] 2.3 Implement query execution
  - [ ] `vm_query` proc - executes SELECT, returns array of arrays
  - [ ] Parameter binding using `$1`, `$2` PostgreSQL syntax
  - [ ] Result row conversion to Gene Value arrays
  - [ ] NULL value conversion to NIL
- [ ] 2.4 Implement statement execution
  - [ ] `vm_exec` proc - executes INSERT/UPDATE/DELETE without returning results
  - [ ] Parameter binding
  - [ ] Error handling for SQL failures
- [ ] 2.5 Implement transaction methods
  - [ ] `vm_begin` proc - start transaction (`BEGIN`)
  - [ ] `vm_commit` proc - commit transaction (`COMMIT`)
  - [ ] `vm_rollback` proc - rollback transaction (`ROLLBACK`)
- [ ] 2.6 Register Gene namespace and classes
  - [ ] Create `genex/postgres` namespace
  - [ ] Define `Connection` class with native methods
  - [ ] Register `open` function in namespace

## 3. Build System Integration
- [ ] 3.1 Update `gene.nimble`
  - [ ] Add postgres compilation to `buildext` task: `nim c --app:lib ... -o:build/libpostgres.dylib src/genex/postgres.nim`

## 4. Testing
- [ ] 4.1 Create `tests/test_stdlib_postgres.nim`
  - [ ] Test connection open/close
  - [ ] Test SELECT with results
  - [ ] Test INSERT/UPDATE/DELETE
  - [ ] Test parameter binding (all types: nil, bool, int, float, string)
  - [ ] Test transactions (begin, commit, rollback)
  - [ ] Test error handling (invalid SQL, connection errors)
  - [ ] Test closed connection behavior
- [ ] 4.2 Create integration test Gene file in `testsuite/database/`
  - [ ] `001_postgres_connection.gene` - basic connection test
  - [ ] `002_postgres_query.gene` - SELECT queries
  - [ ] `003_postgres_mutate.gene` - INSERT/UPDATE/DELETE
  - [ ] `004_postgres_transactions.gene` - transaction support
  - [ ] `005_postgres_types.gene` - type conversion tests

## 5. SQLite API Refactor (Breaking Change)
- [ ] 5.1 Modify `src/genex/sqlite.nim`
  - [ ] Import shared types from `db.nim`
  - [ ] Rename `vm_exec` → `vm_query` (BREAKING: return results)
  - [ ] Rename `vm_execute` → `vm_exec` (BREAKING: now the no-return method)
- [ ] 5.2 Update SQLite tests
  - [ ] Modify `tests/test_stdlib_sqlite.nim` to use new API (`query` instead of `exec`)

## 6. Documentation
- [ ] 6.1 Update `CLAUDE.md`
  - [ ] Add database client section with SQLite and PostgreSQL examples
  - [ ] Document API differences (`query` vs `exec`, connection strings)
  - [ ] Document parameter syntax differences (`?` vs `$1`)
- [ ] 6.2 Update `openspec/project.md`
  - [ ] Add PostgreSQL to tech stack
  - [ ] Document libpq dependency

## 7. Validation
- [ ] 7.1 Run `openspec validate add-postgres-client --strict` and resolve issues
- [ ] 7.2 Verify all tests pass: `nimble test`
- [ ] 7.3 Verify test suite passes: `./testsuite/run_tests.sh`
