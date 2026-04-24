# Phase 08 Pattern Map

## Existing Patterns To Reuse

| Existing file | Pattern | Phase 08 use |
|---------------|---------|--------------|
| `src/gene/types/type_defs.nim` | Central type definitions for `InstructionKind`, `Instruction`, `CompilationUnit`, `ExceptionHandler`, `VirtualMachine`, and `Frame`. | Add `checked_vm` VM flag and keep metadata keyed by `InstructionKind`. |
| `src/gene/types/instructions.nim` | Compilation-unit helpers, trace-capacity maintenance, labels, and instruction `$` formatting. | Delegate instruction debug formatting to metadata and test formatting from one source of truth. |
| `src/gene/types.nim` | Aggregates and exports `types/*` modules. | Import/export new `types/instruction_metadata.nim`. |
| `src/gene/vm.nim` | Imports VM dependencies, defines constants, includes helper modules, and includes `vm/exec.nim`. | Include `vm/checks.nim` before `exec.nim` so checked-mode hooks are available in the hot loop. |
| `src/gene/vm/exec.nim` | Main computed-goto dispatch loop with checks disabled for speed. | Add compile-time-elided `check_before_instruction` and `check_after_instruction` calls. |
| `src/gene/vm/exceptions.nim` | Exception dispatch, handler frame/scope mismatch checks, and frame handler cleanup. | Add targeted checked-mode validation for handler shape and `current_exception` lifecycle. |
| `src/gene/types/core/frames.nim` | Frame pool, stack push/pop, call-base stack, and stack overflow diagnostics. | Use frame stack/call-base state in invariant helpers; do not change normal push/pop ownership semantics unless tests require it. |
| `src/gene/types/core/collections.nim` | Scope pool and refcounted scope parent relationships. | Validate scope refcount/parent-chain sanity at runtime boundaries. |
| `src/gene/gir.nim` | GIR header markers, bytecode read/write, trace serialization, type descriptor persistence, and cache freshness check. | Improve compatibility diagnostics and add corruption/freshness regression tests. |
| `tests/helpers.nim` | Shared `init_all`, `test_vm`, parser, and serdes helpers. | Reuse for checked-mode and stress tests instead of creating separate setup. |
| `tests/integration/test_cli_gir.nim` | Direct GIR save/load and metadata round-trip tests. | Extend for clearer compatibility failure messages and instruction metadata/GIR boundaries. |
| `tests/integration/test_cli_run.nim` | Run-command GIR cache invalidation tests. | Extend to value ABI, instruction ABI, compiler version, and source-hash cache refresh behavior. |
| `tests/integration/test_core_semantics.nim` | Stable nil/void semantics from Phase 06. | Reuse cases in the stable-core stress corpus. |
| `tests/integration/test_serdes.nim` and `tests/integration/test_tree_serdes.nim` | Runtime serialization/deserialization round-trip and failure-path coverage. | Reuse patterns for stable-core serdes stress tests. |

## Target File Additions

- `src/gene/types/instruction_metadata.nim` - one source of truth for opcode
  stack effects, operands, debug formatting, reference/lifetime notes, and
  staged metadata gaps.
- `src/gene/vm/checks.nim` - compile-time-elided checked-mode invariant
  helpers for dispatch, frame/scope/stack, exception, and diagnostics.
- `tests/test_instruction_metadata.nim` - metadata completeness, formatting,
  and explicit-gap tests.
- `tests/test_vm_checked_mode.nim` - direct checked-mode VM invariant tests
  compiled with `-d:geneVmChecks`.
- `tests/integration/test_stable_core_stress.nim` - parser, serdes, and GIR
  round-trip stress corpus.

## Command Patterns

- `src/commands/run.nim`, `src/commands/eval.nim`, and `src/commands/pipe.nim`
  already parse opt-in runtime flags before calling `init_app_and_vm()`.
  Add `--checked-vm` beside `--trace` and set `VM.checked_vm` after VM
  initialization.
- If `--checked-vm` is passed without `-d:geneVmChecks`, return a command
  failure with `checked VM mode requires building with -d:geneVmChecks`.

## Diagnostics Patterns

- Follow existing direct exception style from `not_allowed` and
  `new_exception(types.Exception, ...)`.
- Checked diagnostics should include:
  - prefix: `VM invariant failed`
  - `pc=<number>`
  - `kind=<InstructionKind>`
  - boundary name such as `stack`, `operand`, `frame`, `scope`, `exception`,
    `refcount`, or `gir`
  - short action hint when practical.

## Anti-Patterns To Avoid

- Do not put broad retain/release accounting in Phase 08.
- Do not add runtime checks to release/default execution outside a compile-time
  guard.
- Do not duplicate opcode metadata separately in the VM checker, debug
  formatter, and tests.
- Do not claim unknown dynamic opcodes are covered; report metadata gaps.
- Do not replace the existing GIR version/hash/ABI compatibility model.
- Do not skip direct invalid-bytecode tests; normal behavioral tests alone do
  not prove the checker catches corruption early.
