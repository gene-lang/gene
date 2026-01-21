## Why
Gene needs a `method_missing` hook to enable dynamic method dispatch patterns like proxies, DSLs, and delegation without requiring all methods to be predefined. This is a common metaprogramming feature in dynamic languages (Ruby, Smalltalk) that enables powerful abstractions with minimal boilerplate.

## What Changes
- Add `method_missing` field to `ClassObj` (already commented out in `type_defs.nim`)
- Modify VM method dispatch to check for `method_missing` when a method is not found
- `method_missing` receives the method name and arguments, allowing dynamic handling
- Inheritance: child classes inherit parent's `method_missing` if not overridden
- Scope: method calls only (not property access)

## Impact
- Affected specs: method-missing (new capability)
- Affected code: `src/gene/types/type_defs.nim` (ClassObj), `src/gene/vm.nim` (method dispatch), `src/gene/types/classes.nim` (method lookup)
