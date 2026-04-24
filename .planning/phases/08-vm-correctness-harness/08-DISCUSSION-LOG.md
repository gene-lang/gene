# Phase 08: VM correctness harness - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md - this log preserves the alternatives considered.

**Date:** 2026-04-24
**Phase:** 08-vm-correctness-harness
**Areas discussed:** Invariant coverage boundary

---

## Gray Area Selection

The phase analysis surfaced four gray areas:

| Area | Description | Selected |
|------|-------------|----------|
| Checked VM activation | How maintainers turn checks on without slowing optimized default execution. | |
| Invariant coverage boundary | Which invariants belong in checked-mode MVP. | yes |
| Instruction metadata contract | Where opcode stack effects, operands, lifetime behavior, and formatting live. | |
| Failure diagnostics and stress coverage | What failures report and how broad parser/serdes/GIR stress coverage should be. | |

**User's choice:** Discuss invariant coverage boundary only.
**Notes:** User asked to create context after completing this area.

---

## Invariant Coverage Boundary

### Question 1: Checked-mode MVP scope

| Option | Description | Selected |
|--------|-------------|----------|
| Structural VM invariants | Stack height/effects, frame validity, scope availability, operand kinds, PC/jump targets, call-base balance. | |
| Structural + runtime state | Structural checks plus exception-handler stack, current exception consistency, frame/scope refcount sanity, and selected lifetime checks. | yes |
| Maximum coverage | Also include async/actor/native boundary checks where practical, even if larger and more invasive. | |

**User's choice:** Structural + runtime state.
**Notes:** This became D-01 and D-02 in CONTEXT.md.

### Question 2: Refcount/lifetime strictness

| Option | Description | Selected |
|--------|-------------|----------|
| Boundary sanity only | Fail on impossible live state: nil frame/scope where required, negative/zero live refcounts, caller-frame mismatch, scope-chain breakage, handler frame mismatch. | yes |
| Selected delta checks | Add exact retain/release delta checks around risky operations where expected counts are deterministic. | |
| Broad accounting | Validate RC balance across many opcodes and execution paths, even if tests need special handling. | |

**User's choice:** Boundary sanity only.
**Notes:** This became D-03 in CONTEXT.md.

### Question 3: Exception/runtime-state strictness

| Option | Description | Selected |
|--------|-------------|----------|
| Handler shape + frame consistency | Verify handler stack entries point to valid frames/scopes and PCs; catch/finally markers are sane. | |
| Exception lifecycle consistency | Handler checks plus `current_exception` rules across throw, catch, finally, returns, and root exec cleanup. | yes |
| Full semantic auditing | Prove every try/catch/finally control-flow edge leaves exactly the expected exception/result state. | |

**User's choice:** Exception lifecycle consistency.
**Notes:** This became D-04 in CONTEXT.md.

### Question 4: Stack/operand coverage breadth

| Option | Description | Selected |
|--------|-------------|----------|
| Stage by instruction family | Start with stack/scope/variables/control/call/error/GIR-critical opcodes, then mark the rest as unchecked metadata gaps. | yes |
| All opcodes before completion | Phase 8 is incomplete until every current `InstructionKind` has metadata and checked-mode validation. | |
| Only hot/risky opcodes | Cover highest-risk execution paths now and leave broad metadata coverage for later. | |

**User's choice:** Stage by instruction family.
**Notes:** This became D-05 in CONTEXT.md.

---

## the agent's Discretion

- Activation mechanism for checked mode.
- Instruction metadata storage/API shape.
- Exact diagnostics and stress corpus details, within the Phase 08 requirements.

## Deferred Ideas

None.
