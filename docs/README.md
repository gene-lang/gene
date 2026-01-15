# Gene Documentation Index

The documents below describe the current VM implementation, design decisions, and performance work.  
Files live in `docs/` unless stated otherwise.

## Architecture & Design Notes

- [architecture.md](architecture.md) — bird’s-eye view of the VM and compiler pipeline
- [selector_design.md](selector_design.md) — method/selector dispatch strategy
- [spread_design.md](spread_design.md) — plans for the spread operator and collection literals
- [simd_support.md](simd_support.md) — exploratory notes on SIMD integration
- [gene_principles.md](gene_principles.md) — guiding principles behind language features

## Language & Runtime Topics

- [gir.md](gir.md) — Gene Intermediate Representation file format
- [generator-functions.md](generator-functions.md) — generator semantics and VM support
- [if_scope_bug.md](if_scope_bug.md) — exception-driven scope unwinding bug and fix
- [arg_counter.md](arg_counter.md) — argument counting logic used by function matchers
- [http_server_and_client.md](http_server_and_client.md) — HTTP extensions and runtime hooks
- [lsp.md](lsp.md) — Language Server Protocol implementation and editor integration

## Implementation Diaries

- [IMPLEMENTATION_STATUS.md](IMPLEMENTATION_STATUS.md) — parity snapshot between VM and reference interpreter
- [implementation/async_design.md](implementation/async_design.md) — architecture for pseudo-async futures
- [implementation/async_progress.md](implementation/async_progress.md) — task-level todo list for async work
- [implementation/caller_eval.md](implementation/caller_eval.md) — `$caller_eval` design trade-offs
- [implementation/development_notes.md](implementation/development_notes.md) — open questions and troubleshooting log

## Performance & Benchmarking

- [performance.md](performance.md) — current benchmarks (~3.8M calls/sec fib(24)) and optimisation roadmap
- [performance-improvements-summary.md](performance-improvements-summary.md) — changelog of recent speedups
- [gir-benchmarks.md](gir-benchmarks.md) — GIR-specific profiling data and insights

## Reference Implementation

Documentation for the feature-complete interpreter remains under `gene-new/docs/`.  
Use it as the behavioural oracle when aligning VM semantics with the reference implementation.
