# Phase 08: VM correctness harness - Context

**Gathered:** 2026-04-24
**Status:** Ready for planning

<domain>
## Phase Boundary

Phase 08 adds an opt-in correctness harness around the optimized Gene VM so
runtime changes can fail through clear invariant diagnostics instead of only
through later end-to-end behavior regressions. The phase covers checked VM
mode, instruction metadata, GIR compatibility checks, and parser/serdes/GIR
stress coverage. It must not slow optimized default execution.

</domain>

<decisions>
## Implementation Decisions

### Invariant coverage boundary
- **D-01:** Checked-mode MVP includes both structural VM invariants and
  runtime-state checks. Structural checks include stack height/effects, frame
  validity, scope availability, operand kinds, PC/jump targets, and call-base
  balance where practical.
- **D-02:** Runtime-state checks include exception-handler stack shape,
  `current_exception` consistency, frame/scope sanity, and selected lifetime
  boundary checks.
- **D-03:** Refcount/lifetime checks are boundary sanity checks only. Checked
  mode should fail on impossible live state such as nil frame/scope where a
  handler requires one, negative or zero live refcounts, caller-frame mismatch,
  scope-chain breakage, and handler frame mismatch. Do not attempt broad
  retain/release accounting across the VM in this phase.
- **D-04:** Exception checks should validate handler shape, handler frame/scope
  consistency, sane handler PCs, and `current_exception` lifecycle consistency
  across throw, catch, finally, returns, and root exec cleanup. Do not attempt a
  full formal audit of every try/catch/finally control-flow edge.
- **D-05:** Stack and operand coverage should be staged by instruction family.
  Start with stack, scope, variables, control flow, calls, error handling, and
  GIR-critical opcodes. Any remaining opcode families should be explicitly
  reported as unchecked metadata gaps rather than silently treated as covered.

### the agent's Discretion
- Activation mechanism for checked mode remains open for researcher/planner:
  compile-time define, CLI flag, environment variable, test helper, or a small
  combination are all acceptable if optimized default execution remains fast.
- Instruction metadata storage shape remains open for researcher/planner, but
  it must be centralized enough to prevent drift between opcode behavior,
  debug formatting, and checked-mode validation.
- Diagnostics and stress corpus details remain open for researcher/planner, as
  long as checked failures identify the instruction/runtime boundary involved
  and the tests cover representative stable-core values and failure paths.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Phase requirements and status
- `.planning/ROADMAP.md` - Phase 08 goal, dependencies, requirements, and
  success criteria.
- `.planning/REQUIREMENTS.md` - VMCHK-01 through VMCHK-05 acceptance
  requirements.
- `.planning/PROJECT.md` - Milestone goal, package/core/VM stabilization
  constraints, and the decision that VM correctness checks stay debug-oriented.
- `.planning/STATE.md` - Current milestone state and prior decisions affecting
  VM correctness work.
- `docs/feature-status.md` - Stable-core boundary and GIR Beta posture that
  Phase 08 is formalizing.

### VM and compiler architecture
- `docs/architecture.md` - Current VM, frame, scope, inline cache, GIR, and
  observability architecture.
- `docs/compiler.md` - Parser/type checker/compiler/bytecode/GIR pipeline and
  instruction metadata context.
- `.planning/codebase/ARCHITECTURE.md` - Codebase map for parser, compiler, VM,
  type system, stdlib, commands, and GIR flow.
- `.planning/codebase/CONCERNS.md` - Known fragility around monolithic VM
  execution, GIR compatibility, scope lifetime, exception handler control flow,
  and thread/channel lifecycle.
- `.planning/codebase/TESTING.md` - Existing Nim and testsuite patterns to
  extend for checked-mode and stress coverage.

### GIR and serialization
- `docs/gir.md` - Public GIR compile/run/cache behavior and intended validity
  checks.
- `docs/gir-benchmarks.md` - GIR performance posture and cache workflow
  context.
- `spec/15-serialization.md` - Spec section for JSON, GIR, and Gene serdes
  boundaries.
- `src/gene/gir.nim` - Actual GIR version, ABI marker, hash, load, save, and
  cache validation implementation.
- `src/gene/serdes.nim` - Runtime serialization/deserialization implementation
  that stress coverage should exercise.

### VM implementation hot spots
- `src/gene/types/type_defs.nim` - `InstructionKind`, `Instruction`,
  `CompilationUnit`, `ExceptionHandler`, `VirtualMachine`, and `Frame`
  definitions.
- `src/gene/types/instructions.nim` - Current instruction helpers and debug
  formatting.
- `src/gene/vm/exec.nim` - Main computed-goto dispatch loop, stack/scope/call,
  exception, and runtime-state mutation surface.
- `src/gene/types/core/frames.nim` - Frame pool, stack push/pop, call-base
  stack, frame refcount, and stack overflow diagnostics.
- `src/gene/vm/exceptions.nim` - Runtime exception normalization and
  formatting support.

### Existing coverage to extend
- `tests/helpers.nim` - Shared parser, VM, and serdes test helpers.
- `tests/test_parser.nim` and `tests/test_parser_interpolation.nim` - Parser
  stable-core coverage.
- `tests/integration/test_cli_gir.nim` - GIR CLI/load/save/metadata coverage.
- `tests/integration/test_cli_run.nim` - GIR cache invalidation and run-command
  behavior.
- `tests/integration/test_serdes.nim` and
  `tests/integration/test_tree_serdes.nim` - Runtime serdes round-trip and
  failure-path coverage.
- `tests/integration/test_core_semantics.nim` - Stable-core nil/void and
  semantic boundary coverage from Phase 06.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `VM.trace`, `VM.profiling`, and `instruction_profiling` already provide
  non-default VM observability surfaces. Checked mode should follow this
  opt-in posture rather than becoming default hot-path work.
- `InstructionKind` is centralized in `src/gene/types/type_defs.nim`, making it
  the natural source of truth for opcode metadata coverage.
- Existing test helpers in `tests/helpers.nim` already run parser/compiler/VM
  paths directly and should be reused for focused checked-mode tests.

### Established Patterns
- The VM hot loop in `src/gene/vm/exec.nim` currently disables Nim checks for
  speed. Checked mode should be guarded behind debug/test configuration or
  explicit runtime flags so release/optimized execution remains unaffected.
- GIR compatibility currently rejects mismatched `GIR_VERSION`,
  `COMPILER_VERSION`, `VALUE_ABI_VERSION`, `INSTRUCTION_ABI_VERSION`, and
  source hashes. Phase 08 should make these failures clearer and broaden tests,
  not replace the existing model.
- Phase 06/07 established a pattern of documenting stable boundaries while
  marking incomplete edges explicitly; Phase 08 should do the same for opcode
  metadata gaps.

### Integration Points
- Checked-mode hooks connect to `src/gene/vm/exec.nim` around instruction
  dispatch and risky runtime transitions.
- Metadata connects to `src/gene/types/type_defs.nim` and
  `src/gene/types/instructions.nim`.
- GIR compatibility work connects to `src/gene/gir.nim`, `src/commands/run.nim`,
  and CLI integration tests.
- Parser/serdes/GIR stress coverage connects to `tests/test_parser.nim`,
  `tests/integration/test_serdes.nim`, `tests/integration/test_tree_serdes.nim`,
  and `tests/integration/test_cli_gir.nim`.

</code_context>

<specifics>
## Specific Ideas

- User selected the middle boundary for checked mode: structural VM invariants
  plus runtime-state checks.
- User explicitly chose boundary-sanity refcount/lifetime checks rather than
  selected delta checks or broad accounting.
- User explicitly chose exception lifecycle consistency checks but not full
  semantic auditing of every exception/control-flow edge.
- User explicitly chose staged opcode coverage by instruction family, with
  unchecked families called out as metadata gaps.

</specifics>

<deferred>
## Deferred Ideas

None from this discussion. Activation, metadata layout, and diagnostics/stress
details remain within Phase 08 scope but were left to downstream research and
planning discretion.

</deferred>

---

*Phase: 08-vm-correctness-harness*
*Context gathered: 2026-04-24*
