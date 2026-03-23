# Gene Documentation

`spec/` is the canonical language reference for implemented behavior.

`docs/` is for current implementation notes, subsystem reference material, and
operational guidance. Design proposals, speculative work, and design-era docs
for implemented subsystems now live under [`docs/proposals/`](proposals/README.md).

## Current Reference Docs

- [architecture.md](architecture.md) — VM/compiler/runtime architecture overview
- [compiler.md](compiler.md) — compiler pipeline and descriptor-first typing notes
- [gir.md](gir.md) — GIR format, caching, and CLI workflow
- [thread_support.md](thread_support.md) — current thread model and APIs
- [generator_functions.md](generator_functions.md) — shipped generator semantics
- [regex.md](regex.md) — current regex syntax and helper behavior
- [package_support.md](package_support.md) — current package/import behavior
- [type-system-mvp.md](type-system-mvp.md) — current gradual typing status
- [descriptor-pipeline-migration.md](descriptor-pipeline-migration.md) — descriptor pipeline migration notes
- [wasm.md](wasm.md) — current wasm build target and ABI contract
- [http_server_and_client.md](http_server_and_client.md) — HTTP extension surface
- [c_extensions.md](c_extensions.md) — native extension API and build flow
- [deserialize_command.md](deserialize_command.md) — `gene deser` command behavior
- [lsp.md](lsp.md) — current LSP implementation status
- [symbol_resolution.md](symbol_resolution.md) — symbol lookup rules
- [../examples/how-types-work.md](../examples/how-types-work.md) — runnable typing walkthrough

## Performance And Ops

- [performance.md](performance.md) — benchmark numbers and optimization priorities
- [gir-benchmarks.md](gir-benchmarks.md) — GIR-specific benchmark notes
- [benchmark_http_server.md](benchmark_http_server.md) — HTTP benchmarking workflow
- [ongoing-cleanup.md](ongoing-cleanup.md) — living cleanup tracker

## Working Notes

- [implementation/async_design.md](implementation/async_design.md) — async implementation diary
- [implementation/async_progress.md](implementation/async_progress.md) — async rollout progress log
- [implementation/async_tasks.md](implementation/async_tasks.md) — async task checklist
- [implementation/caller_eval.md](implementation/caller_eval.md) — `$caller_eval` implementation notes
- [implementation/development_notes.md](implementation/development_notes.md) — development scratchpad

## Design And Proposal Docs

- [proposals/README.md](proposals/README.md) — future proposals, implemented-but-design-era notes, and archived historical docs
