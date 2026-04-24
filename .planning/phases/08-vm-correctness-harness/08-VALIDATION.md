# Phase 08 Validation Strategy

status: planned
phase: 08-vm-correctness-harness
requirements: [VMCHK-01, VMCHK-02, VMCHK-03, VMCHK-04, VMCHK-05]
nyquist_compliant: true

## Validation Approach

Phase 08 is a VM/runtime correctness phase. Validation must sample both normal
behavior and intentionally invalid bytecode/runtime state so the new checked
mode is proven to fail at the invariant boundary instead of after unchecked VM
mutation.

## Acceptance Checks

Run these checks after execution:

```bash
rg -n "InstructionMetadata|instruction_metadata|metadata_gap_kinds|format_instruction_debug" src/gene/types tests/test_instruction_metadata.nim
rg -n "checked_vm|geneVmChecks|check_before_instruction|check_after_instruction|VM invariant" src/gene tests/test_vm_checked_mode.nim
rg -n "VALUE_ABI|INSTRUCTION_ABI|Unsupported GIR version|source hash|cache" src/gene/gir.nim tests/integration/test_cli_gir.nim tests/integration/test_cli_run.nim
rg -n "stable-core stress|parser stress|serdes stress|GIR stress" tests/integration/test_stable_core_stress.nim
nim c -r tests/test_instruction_metadata.nim
nim c -d:geneVmChecks -r tests/test_vm_checked_mode.nim
nim c -r tests/integration/test_cli_gir.nim
nim c -r tests/integration/test_cli_run.nim
nim c -r tests/integration/test_stable_core_stress.nim
git diff --check
```

Because this phase touches VM dispatch, GIR compatibility, and shared test
coverage, also run:

```bash
nimble testintegration
```

## Requirement Coverage

| Requirement | Validation |
|-------------|------------|
| VMCHK-01 | `tests/test_vm_checked_mode.nim` proves checked mode can be enabled in a `-d:geneVmChecks` build and remains disabled by default. |
| VMCHK-02 | `tests/test_instruction_metadata.nim` proves every `InstructionKind` has metadata and reports staged gaps explicitly. |
| VMCHK-03 | GIR tests corrupt version, compiler version, value ABI, instruction ABI, source hash, and magic bytes, then assert clear diagnostics or cache refresh. |
| VMCHK-04 | `tests/integration/test_stable_core_stress.nim` covers parser, serdes, and GIR round trips for stable-core values and failure paths. |
| VMCHK-05 | Checked-mode tests assert diagnostics contain PC/opcode/boundary text such as `VM invariant`, `pc=`, and the instruction kind. |

## Sampling Rate

- After metadata changes: run `nim c -r tests/test_instruction_metadata.nim`.
- After checked-mode helper or VM dispatch changes: run
  `nim c -d:geneVmChecks -r tests/test_vm_checked_mode.nim`.
- After GIR changes: run `nim c -r tests/integration/test_cli_gir.nim` and
  `nim c -r tests/integration/test_cli_run.nim`.
- After stress-corpus changes: run
  `nim c -r tests/integration/test_stable_core_stress.nim`.
- Before phase closeout: run `nimble testintegration`.

## Verification Gate

Phase 08 is not complete until the focused checks and `nimble testintegration`
pass, or any integration failure is documented as unrelated with concrete
evidence.
