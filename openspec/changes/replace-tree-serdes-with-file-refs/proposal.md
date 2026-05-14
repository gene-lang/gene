## Why

Gene currently has two filesystem serialization stories: the canonical text payload API under `gene/serdes/serialize` / `gene/serdes/deserialize`, and the tree-serdes filesystem API exposed as `gene/serdes/read_tree` / `gene/serdes/write_tree`. The tree API creates a second public model with exploded directory semantics, reserved marker names, and lazy-loading behavior that now conflicts with the desired single filesystem persistence contract.

M012 replaces that split with one unified filesystem serialization model: values are still serialized as Gene-native text payloads, while filesystem persistence is expressed only through `gene/serdes/write`, `gene/serdes/read`, `gene/serdes/read_file`, and `gene/serdes/read_dir`. This proposal is the implementation approval gate; S02 runtime work MUST NOT begin until this change is reviewed and accepted.

## What Changes

- **BREAKING**: Remove `gene/serdes/read_tree` and `gene/serdes/write_tree` from the supported public API; they are removal targets, not compatibility aliases.
- Add a `filesystem-serdes` contract for the exact filesystem surface: `write`, `read`, `read_file`, and `read_dir`; `read` aliases `read_file`.
- Keep `serialize` and `deserialize` as text payload APIs, not filesystem persistence APIs.
- Define explicit serialized reference forms such as `(gene/serdes/read_file "path.gene")` and `(gene/serdes/read_dir "dir" ...)` that are dispatched by the deserializer with containing-file context, not evaluated as arbitrary Gene code.
- Define eager-by-default file and directory refs with `^lazy true` transparent lazy values.
- Require fail-closed path safety, missing/invalid target diagnostics, malformed option rejection, and cycle rejection.
- Define selector-driven writer externalization from `gene/serdes/write` using deterministic child names and explicit `read_file` / `read_dir` forms in the parent file.
- Define `read_dir` shape and ordering options for ordered arrays and keyed maps.
- Require public docs/spec cleanup and implementation verification before the change can be considered complete.

## Impact

- Affected specs: `filesystem-serdes` (new delta; no current baseline spec exists in this repository)
- Affected code in later slices only: `src/gene/serdes.nim`, serializer registration/runtime helpers, serialization tests, GeneClaw storage helpers, and public serialization docs
- S01 affected files only: this OpenSpec change and later S01 documentation/gate artifacts
- Requirements advanced/supported: R120 through R130, especially R120 as the public API contract and R126/R129 as the old API removal/public cleanup constraints
- Accepted constraints honored: D072, D073, D074, D075, D076, D077, D078, and D079
- Risk: medium-high because serialization crosses runtime, durable files, docs, and downstream app storage

## Approval Boundary

This proposal deliberately performs no runtime implementation. The accepted OpenSpec change is the approval artifact that authorizes S02-S06 implementation; before approval, runtime files, GeneClaw helpers, tests, and public examples MUST remain untouched except for separate documentation/gate work owned by S01.
