# Gene Programming Language

Gene is a general-purpose, homoiconic language with a Lisp-like surface syntax.  
This repository hosts the bytecode virtual machine (VM) implementation written in Nim.  
The original tree-walking interpreter lives in `gene-new/` and serves as the language reference.

## Repository Layout

- `src/gene.nim` — entry point for the VM executable  
- `src/gene/` — core compiler, VM, GIR, and command modules  
- `bin/` — build output from `nimble build` (`bin/gene`)  
- `build/` — cached Gene IR (`*.gir`) emitted by the compiler  
- `tests/` — Nim-based unit and integration tests for the VM  
- `testsuite/` — black-box Gene programs with an expectation harness  
- `examples/` — sample Gene source files  
- `gene-new/` — reference interpreter implementation (feature-complete)

## VM Status

- **Available today**
  - Bytecode compiler + stack-based VM with computed-goto dispatch
  - S-expression parser compatible with the reference interpreter
  - Macro system (`fn!`, `$caller_eval`) with unevaluated argument support
  - Basic class system (`class`, `new`, nested classes) and namespaces
  - Pseudo-async primitives (`async`, `await`) backed by futures
  - Command-line toolchain (`run`, `eval`, `repl`, `parse`, `compile`)
  - File I/O helpers via the `io` namespace (`io/read`, `io/write`, async variants)
- **In progress / known limitations**
  - Pattern matching beyond argument binders is still experimental
  - Many class features (constructors, method dispatch, inheritance) need more coverage
  - Module/import system and package management are not yet available
  - Async primitives execute synchronously; scope lifetime bugs still surface in nested async code (see `IkScopeEnd` in `src/gene/vm.nim`)

## Building

```bash
# Clone the repository
git clone https://github.com/gcao/gene
cd gene

# Build the VM (produces bin/gene)
nimble build

# Optimised build (native flags, release mode)
nimble speedy

# Direct Nim invocation (places the binary in ./bin/gene by default)
nim c -o:bin/gene src/gene.nim
```

## Command-Line Tool

All commands are dispatched through `bin/gene <command> [options]`:

- `run <file>` — parse, compile (with GIR caching), and execute a `.gene` program  
  - respects cached IR in `build/` unless `--no-gir-cache` is supplied  
- `eval <code>` — evaluate inline Gene code or read from `stdin`  
  - supports debug output (`--debug`), instruction tracing, CSV/Gene formatting  
- `repl` — interactive REPL with multi-line input and helpful prompts  
- `parse <file | code>` — parse Gene source and print the AST representation  
- `compile` — compile to bytecode or `.gir` on disk (`-f pretty|compact|bytecode|gir`, `-o`, `--emit-debug`)

Run `bin/gene help` for the complete command list and examples.

## Examples

```gene
# Hello World
(print "Hello, World!")

# Define a function
(fn add [a b]
  (+ a b))

# Fibonacci
(fn fib [n]
  (if (< n 2)
    n
    (+ (fib (- n 1)) (fib (- n 2)))))

(print "fib(10) =" (fib 10))
```

See `examples/` for additional programs and CLI demonstrations.

## Testing

```bash
# Run the curated Nim test suite (see gene.nimble)
nimble test

# Execute an individual Nim test
nim c -r tests/test_parser.nim

# Run the Gene program suite (requires bin/gene)
./testsuite/run_tests.sh
```

The Nim tests exercise compiler/VM internals, while the shell suite runs real Gene code end-to-end.

## Documentation

The documentation index in `docs/README.md` lists the current architecture notes, design discussions, and implementation diaries. Highlights include:
- `docs/architecture.md` — VM and compiler design overview
- `docs/gir.md` — Gene Intermediate Representation format
- `docs/performance.md` — benchmark data and optimisation roadmap
- `docs/IMPLEMENTATION_STATUS.md` — snapshot of feature parity vs. the reference interpreter

## Performance

Latest fib(24) benchmarks (2025 measurements) place the optimised VM around **3.8M function calls/sec** on macOS ARM64. See `docs/performance.md` for methodology, historical comparisons, and profiling insights.

## License

[MIT License](LICENSE)

## Credits

Created by Yanfeng Liu (@gcao) with contributions from the Gene community.
