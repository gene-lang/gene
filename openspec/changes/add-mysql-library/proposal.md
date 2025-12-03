# Add MySQL Library to Gene

## Summary

This change adds MySQL database connectivity to Gene through the genex extension system, following the same pattern as the existing SQLite library. It provides a native MySQL connection class with methods for executing queries and managing connections.

## Requirements

### Database Connectivity
- Provide MySQL connection functionality using `db_connector/db_mysql`
- Support connection opening/closing with proper resource management
- Enable both query execution (with results) and statement execution (without results)
- Support parameter binding for prepared statements

### API Compatibility
- Follow the same API pattern as the existing SQLite library for consistency
- Provide `mysql/open`, Connection class with `exec`, `execute`, and `close` methods
- Integrate with the gene type system and error handling
- Support all Gene value types in parameter binding (nil, bool, int, float, string)

### Integration
- Add MySQL namespace under `genex/mysql`
- Build as dynamic library `libmysql.dylib` via existing `buildext` task
- Thread-safe connection management using connection IDs
- Proper cleanup and resource management

### Build System
- Extend `gene.nimble` buildext task to include MySQL library compilation
- Ensure MySQL connector dependency is properly declared
- Support development and release builds

## Dependencies

This change requires:
- `db_connector/db_mysql` (MySQL database connector)
- Existing Gene VM infrastructure
- `db_connector` dependency (already in gene.nimble)

## Testing

- Test MySQL connection opening and closing
- Test query execution with various data types
- Test parameter binding and prepared statements
- Test error handling for invalid connections or SQL
- Test resource cleanup and connection management

## Impact

- Adds new MySQL namespace and functionality
- Extends build system with additional library compilation
- Provides database connectivity capabilities for Gene applications