# Implement Complex Symbol Access

## Overview

Implement the complex symbol access system as designed in `docs/complex_symbol_access_design.md`. This will enable slash-delimited paths like `geometry/shapes/Circle` and `/status` for classes, variables, and assignments with automatic rewriting to `^container` expressions.

## Why

The current Gene language has basic symbol support but lacks the sophisticated symbol resolution system outlined in the design document. While the foundation exists (VkComplexSymbol, basic namespaces, property access), the core rewriting rules and container-based resolution system are not implemented.

This design proposes a **compile-time stack-based approach** rather than runtime container evaluation. Instead of evaluating container expressions dynamically, the compiler will use existing VM instructions like `IkClassAsMember` and proper stack management. This approach offers better performance, simpler implementation, and more predictable behavior while leveraging existing VM infrastructure.

## Background

The Gene language currently supports basic symbol access but lacks the sophisticated symbol resolution system outlined in the design document. The existing codebase has the foundation (VkComplexSymbol, basic namespaces, property access) but does not implement the core rewriting rules and container-based resolution system.

## Goals

1. **Implement complex symbol rewriting** for definitions and assignments
2. **Enable container-based symbol resolution** for nested namespaces
3. **Support numeric segment handling** for array/gene indexing
4. **Maintain backward compatibility** with existing symbol access patterns
5. **Add comprehensive test coverage** for all symbol access scenarios

## Scope

**In Scope:**
- Complex symbol parsing and stack-based rewriting (class, var, assignment targets)
- Compile-time container resolution using existing VM instructions
- Multi-segment symbol handling with proper stack management
- Numeric segment detection and child access integration
- Integration with existing namespace and property access systems
- Comprehensive test suite for all scenarios

**Out of Scope:**
- Module system integration (future enhancement)
- Dynamic symbol resolution with runtime-evaluated segments
- Global namespace implementation (can be added separately)
- Runtime container expression evaluation (replaced by compile-time approach)

## Success Criteria

- `class geometry/shapes/Circle` works and creates nested class structure
- `var /x value` assigns to self container correctly
- `arr/0 = value` modifies array element, not string property
- All existing symbol access patterns continue working
- Comprehensive test suite validates all rewrite rules and edge cases

## Dependencies

- Existing VkComplexSymbol type system
- Current namespace implementation
- Property access (/) infrastructure
- Container (^container) property system

## Risks

- **Complexity**: Multi-segment symbol resolution may introduce parsing ambiguities
- **Performance**: Container lookup overhead for deeply nested symbols
- **Compatibility**: Risk of breaking existing symbol access patterns

## Timeline

Estimated 2-3 weeks for complete implementation including testing and validation.