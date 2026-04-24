# Phase 08 Research: VM correctness harness

## Current State

Phase 08 should add a checked execution surface around the existing optimized
VM, not replace the VM loop. The current runtime already has a few useful
debug/observability toggles:

- `src/gene/types/type_defs.nim` keeps `InstructionKind`, `Instruction`,
  `CompilationUnit`, `ExceptionHandler`, `VirtualMachine`, and `Frame`
  together, making it the right place for shared types and a VM checked-mode
  flag.
- `src/gene/types/instructions.nim` centralizes compilation-unit construction,
  instruction trace capacity maintenance, labels, and `$` formatting for
  instructions.
- `src/gene/vm/exec.nim` is the main computed-goto hot loop and explicitly
  disables bound, overflow, nil, and assertion checks for speed.
- `src/gene/types/core/frames.nim` owns frame pools, stack push/pop, and
  call-base stack helpers.
- `src/gene/types/core/collections.nim` owns scope pools and refcounted scope
  parent links.
- `src/gene/vm/exceptions.nim` owns exception dispatch, frame unwinding, scope
  unwinding, handler mismatch detection, and frame handler cleanup.
- `src/gene/gir.nim` persists bytecode, trace data, type descriptors, and GIR
  header compatibility markers.
- `tests/helpers.nim` already gives focused parser/VM/serdes helpers that
  direct checked-mode tests can reuse.

The current risk is that VM failures are discovered through end-to-end symptoms
after unchecked stack/frame/scope mutation has already happened. Phase 08
should make common corruption fail near the instruction or runtime boundary
that caused it.

## Phase Requirements

Phase 08 covers:

- `VMCHK-01`: maintainers can run a checked VM mode without changing optimized
  default execution.
- `VMCHK-02`: instruction metadata exists for stack effects, operands,
  reference/lifetime behavior, and debug formatting for the supported opcode
  set.
- `VMCHK-03`: GIR compatibility checks fail clearly for stale or incompatible
  bytecode caches and are covered by regression tests.
- `VMCHK-04`: parser, serdes, and GIR round-trip stress coverage exists for
  representative stable-core values and failure paths.
- `VMCHK-05`: checked-mode failures produce diagnostics that identify the
  instruction or runtime boundary that violated an invariant.

## Implementation Findings

### Checked-mode activation

The VM loop in `src/gene/vm/exec.nim` currently uses a hot `while true` dispatch
loop with checks disabled. The safe implementation path is a two-part gate:

1. Add a runtime field such as `checked_vm*: bool` to `VirtualMachine`, default
   false in `new_vm_ptr`.
2. Guard all check helpers with a compile-time symbol such as
   `when defined(geneVmChecks)`.

This lets maintainers run checked builds with `-d:geneVmChecks` and enable the
mode with a direct test helper or CLI flag. Release/default builds keep the
checks compiled out, and normal debug builds pay only for the new field unless
the symbol is enabled.

CLI commands that execute code should accept `--checked-vm` consistently where
they already accept `--trace`, `--trace-instruction`, `--no-type-check`, and
native-code flags:

- `src/commands/run.nim`
- `src/commands/eval.nim`
- `src/commands/pipe.nim`

If a user passes `--checked-vm` to a binary not compiled with
`-d:geneVmChecks`, return a deterministic command failure such as
`checked VM mode requires building with -d:geneVmChecks`.

### Instruction metadata architecture

`InstructionKind` is centralized, but metadata is currently spread across enum
comments, compiler emission sites, `$` formatting, GIR read/write code, and VM
dispatch behavior. Phase 08 should add a shared metadata module rather than
requiring every checker to duplicate opcode knowledge.

Recommended file:

- `src/gene/types/instruction_metadata.nim`

Recommended exported types:

- `InstructionOperandKind* = enum IokNone, IokValue, IokKey, IokLabel,
  IokPc, IokLocalIndex, IokParentDepth, IokCount, IokFlags, IokTypeId,
  IokMethodName, IokSelector, IokCompiledUnit`
- `InstructionStackEffectKind* = enum SekFixed, SekDynamic, SekUnknown`
- `InstructionStackEffect* = object min_pops*, pushes*, kind*, note*`
- `InstructionMetadata* = object stack*, arg0*, arg1*, touches_refs*,
  lifetime_note*, debug_format*, family*, checked*`

Recommended procs:

- `instruction_metadata*(kind: InstructionKind): InstructionMetadata`
- `instruction_stack_effect*(inst: Instruction): InstructionStackEffect`
- `metadata_gap_kinds*(): seq[InstructionKind]`
- `format_instruction_debug*(inst: Instruction): string`

The `$` formatter in `src/gene/types/instructions.nim` should delegate to the
metadata-aware debug formatter so debug output and checked-mode diagnostics use
one source of truth. The first implementation does not need perfect stack math
for every dynamic opcode; it should mark unknown or staged opcodes explicitly
instead of silently treating them as covered.

### Invariant families for MVP

The Phase 08 discussion selected a middle boundary: structural invariants plus
runtime-state checks. The MVP should cover these families:

- Compilation-unit invariants: non-nil `cu`, PC within instruction bounds,
  trace capacity not shorter than instruction count after compile/GIR load,
  inline cache length matching instruction count after GIR load.
- Instruction metadata invariants: every `InstructionKind` has a metadata
  entry; explicitly staged gaps are visible through `metadata_gap_kinds`.
- Operand invariants: jump/handler PCs are in range; label-derived PCs are
  integers where optimized bytecode expects PCs; local indices are nonnegative;
  parent depths are nonnegative; call counts and collection counts are sane.
- Stack invariants: fixed-pop instructions must have enough stack values
  before dispatch; fixed push/pop effects must not exceed frame stack capacity;
  call-base operations must have a corresponding `IkCallArgsStart` base where
  practical.
- Frame/scope invariants: checked mode fails on nil frame when executing an
  instruction requiring a frame; nil scope where scope/variable instructions
  require scope; broken parent-scope chains when resolving inherited variables.
- Exception invariants: handler frame/scope/cu are non-nil where required;
  handler catch/finally PCs are in range or known sentinel values;
  `current_exception` is non-nil while dispatching a normal catch/finally
  path and is cleared after normal catch/finally completion and root cleanup.
- Boundary refcount/lifetime sanity: frame and scope refcounts observed by
  checked mode must be positive; impossible nil caller-frame or handler-frame
  relationships should fail. Do not attempt broad retain/release accounting.

The checker should be integrated in small hooks around dispatch:

- `check_before_instruction(self, inst[])` near the top of the loop, before the
  `case inst.kind` dispatch.
- `check_after_instruction(self, before_stack, inst[])` after successful
  instruction execution and before advancing to the next PC.
- targeted helpers from exception dispatch and return paths where the normal
  before/after hook cannot see enough state.

### GIR compatibility

`src/gene/gir.nim` already stores `GIR_VERSION`, `COMPILER_VERSION`,
`VALUE_ABI_VERSION`, and `INSTRUCTION_ABI_VERSION`. `load_gir_file` rejects
bad magic, version mismatch, value ABI mismatch, and instruction ABI mismatch.
`is_gir_up_to_date` returns false for cache staleness and the run command
recompiles stale caches.

The useful Phase 08 improvement is not a new cache model. It is clearer failure
messages and regression tests around the existing model:

- `load_gir_file` version errors should include expected and actual versions
  plus the path.
- ABI mismatch errors should include expected marker, actual marker, and a
  "recompile" hint.
- cache freshness tests should cover version, compiler version, value ABI,
  instruction ABI, and source hash.
- run-command tests should prove stale/incompatible caches are refreshed rather
  than reused.
- direct GIR load tests should prove corrupt cache data fails clearly when the
  caller explicitly loads a `.gir`.

### Parser, serdes, and GIR stress coverage

The existing tests cover many targeted cases, but Phase 08 needs a single
stress-style corpus that exercises representative stable-core values through
multiple layers:

- parser round trip through `read`, `read_all`, and `value_to_gene_str`
- serdes round trip through `serialize(value).to_s()` and `deserialize`
- GIR save/load/execute round trip for compiled stable-core snippets
- failure paths for malformed parser input, unsupported serdes refs, corrupt
  GIR headers, and incompatible cache markers

Recommended new integration test:

- `tests/integration/test_stable_core_stress.nim`

Recommended corpus categories:

- nil/void boundary behavior from Phase 06
- booleans, ints, floats, strings, symbols
- arrays, maps, nested genes, selectors
- local variables, inherited variables, loops, functions, blocks
- exceptions with catch/finally
- package-independent module snippets that can be compiled and saved to GIR

Add the test to `gene.nimble` `testintegration`.

## Sequencing Recommendation

1. Add instruction metadata first and lock coverage with tests. This gives
   checked mode a stable source of truth and prevents drift.
2. Add checked-mode flag/helpers and focused direct VM corruption tests.
3. Integrate checker hooks in `exec.nim` and exception helpers with diagnostic
   tests.
4. Improve GIR compatibility diagnostics/tests.
5. Add stress corpus and update docs/status.

## Risks

- **Hot-path regression:** avoid by compile-time gating helpers with
  `defined(geneVmChecks)` and leaving `checked_vm` false by default.
- **Metadata overreach:** avoid by explicitly reporting staged gaps instead of
  guessing dynamic stack behavior for every opcode.
- **False confidence:** tests must include deliberately invalid bytecode/VM
  state to prove checked failures occur before unchecked mutation.
- **Exception complexity:** keep exception checks to handler shape,
  frame/scope/PC sanity, and `current_exception` lifecycle consistency rather
  than a full formal audit of every try/catch/finally edge.
- **GIR churn:** improve diagnostics and tests around existing markers instead
  of inventing a second compatibility mechanism.

## Validation Architecture

Phase 08 validation must prove four layers:

1. **Metadata completeness:** every `InstructionKind` returns metadata, and
   `metadata_gap_kinds` reports staged gaps instead of hiding them.
2. **Checked VM diagnostics:** focused tests run with `-d:geneVmChecks`, enable
   `VM.checked_vm`, inject invalid bytecode or state, and assert deterministic
   diagnostics with PC, opcode, and boundary information.
3. **Compatibility diagnostics:** GIR load/up-to-date tests corrupt version,
   compiler version, value ABI, instruction ABI, source hash, and magic bytes,
   then assert clear failures or cache refresh behavior.
4. **Stress corpus:** parser, serdes, and GIR round-trip tests exercise the
   stable-core representative values and known failure paths.

Required focused checks:

```bash
nim c -r tests/test_instruction_metadata.nim
nim c -d:geneVmChecks -r tests/test_vm_checked_mode.nim
nim c -r tests/integration/test_cli_gir.nim
nim c -r tests/integration/test_cli_run.nim
nim c -r tests/integration/test_stable_core_stress.nim
nimble testintegration
git diff --check
```

## Out Of Scope

- Full retain/release accounting across the VM.
- Rewriting the computed-goto dispatch loop.
- Enabling checked mode by default in optimized builds.
- Formal verification of every exception-control-flow edge.
- New GIR cache format beyond the existing version/hash/ABI marker model.

## RESEARCH COMPLETE
