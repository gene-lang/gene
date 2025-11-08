# Implementation Status

This repository contains **two implementations** of the Gene programming language:

## 1. VM Implementation (Root Directory) - ACTIVE DEVELOPMENT

Location: `/src/`

This is the **current focus** - a bytecode VM implementation for better performance.

### Status
- ✅ Parser & AST builder
- ✅ Bytecode compiler + GIR serializer
- ✅ Stack-based VM with computed-goto dispatch
- ✅ Core data types (ints, floats, strings, arrays, maps, sets, futures, classes)
- ✅ Functions, closures, and macro-like functions (`fn!`, `$caller_eval`)
- ✅ Basic control flow (if/else, loops, try/catch/finally)
- ✅ CLI commands (`run`, `eval`, `repl`, `parse`, `compile`)
- ✅ Async/await via synchronous futures (pseudo-async)
- ✅ Scope lifetime management with proper ref-counting (async-safe)
- 🚧 Classes/OOP: constructors, inheritance, and method dispatch coverage still limited
- 🚧 Pattern matching: argument binders work; general `match` forms incomplete
- 🚧 Module/import system and package tooling

### Performance
- fib(24) benchmark (2025 ARM64 measurements): ~3.8M function calls/sec
- Optimisation roadmap focuses on allocation pooling, inline caches, and instruction specialisation (see `docs/performance.md`)

## 2. Reference Implementation (gene-new/) - FEATURE COMPLETE

Location: `/gene-new/`

This is the **reference implementation** - a tree-walking interpreter with all language features.

### Status
- ✅ All language features implemented
- ✅ Complete standard library
- ✅ Extensive test suite
- ✅ Production-ready

### Purpose
- Language specification reference
- Testing new language features
- Validating VM implementation behavior

## Development Strategy

1. The VM implementation is being developed to match the reference implementation's behavior
2. New language features are prototyped in the reference implementation first
3. The VM implementation focuses on performance while maintaining compatibility

## For Contributors

- **Performance work**: Focus on the VM implementation (`/src/`)
- **Language features**: Check the reference implementation (`/gene-new/`)
- **Bug fixes**: Fix in both implementations if applicable

## Why Two Implementations?

1. **Reference implementation** ensures language consistency and provides a stable baseline
2. **VM implementation** provides the performance needed for production use
3. Having both allows safe experimentation while maintaining stability
