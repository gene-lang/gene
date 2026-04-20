---
phase: 03
slug: port-actors-for-extensions
status: ready
nyquist_compliant: true
wave_0_complete: true
created: 2026-04-20
---

# Phase 03 — Validation Strategy

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Nim `std/unittest` plus selected example/testsuite smokes |
| **Quick run command** | `nim c -r tests/integration/test_extension_ports.nim && nim c -r tests/integration/test_llm_mock.nim && nim c -r tests/integration/test_http.nim` |
| **Full suite command** | `nimble test && nim c -r tests/integration/test_ai_scheduler.nim && nim c -r tests/integration/test_ai_slack_socket_mode.nim && nim c -r tests/integration/test_thread.nim` |
| **Estimated runtime** | ~240 seconds |

## Sampling Rate

- after every task commit: run the narrowest affected extension regression
- after every wave: run `tests/integration/test_thread.nim` plus touched extension suites
- before phase verification: quick run command + AI scheduler/slack + fresh `nimble build`

## Per-Task Verification Map

| Task ID | Plan | Requirement | Automated Command | File Exists | Status |
|---------|------|-------------|-------------------|-------------|--------|
| 03-01-01 | 01 | ACT-03 | `nim c -r tests/integration/test_extension_ports.nim` | ❌ W0 | ⬜ pending |
| 03-02-01 | 02 | ACT-03 | `nim c -r tests/integration/test_llm_mock.nim` | ✅ | ⬜ pending |
| 03-03-01 | 03 | ACT-03 | `nim c -r tests/integration/test_http.nim` | ✅ | ⬜ pending |
| 03-03-02 | 03 | ACT-03 | `nim c -r tests/integration/test_ai_scheduler.nim && nim c -r tests/integration/test_ai_slack_socket_mode.nim` | ✅ | ⬜ pending |
| 03-04-01 | 04 | ACT-03 | `nimble build && nim c -r tests/integration/test_thread.nim` | ✅ | ⬜ pending |

## Wave 0 Requirements

- [ ] `tests/integration/test_extension_ports.nim`
- [ ] `tests/integration/test_llm_mock.nim` updates
- [ ] `tests/integration/test_http.nim` updates
- [ ] `tests/integration/test_ai_scheduler.nim` / `test_ai_slack_socket_mode.nim` updates

**Approval:** ready for execution planning
