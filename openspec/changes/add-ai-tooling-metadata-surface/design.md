## Context

`gene compile` currently optimizes for bytecode/GIR output and human-readable listings. AI and tooling integrations need structured output without reverse-engineering textual listings.

## Goals

- Provide a stable machine-readable metadata payload from CLI.
- Reuse descriptor-first metadata already present in `CompilationUnit`.
- Keep output deterministic for tests and downstream consumption.

## Non-Goals

- Full formatter implementation.
- LSP protocol redesign.
- Semantic indexing service implementation.

## Output Shape

Introduce `-f ai-metadata` for `gene compile`, returning JSON with:

- source/module path
- module type tree summary
- descriptor table summary (ids + kinds + module ownership)
- typed callable summaries (name, param type ids, return type id)

## Compatibility

- Existing compile formats remain unchanged.
- Metadata format is additive and opt-in.
