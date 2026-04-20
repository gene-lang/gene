# Phase 03: Port Actors for Extensions - Pattern Map

**Mapped:** 2026-04-20  
**Files analyzed:** 11  
**Analogs found:** 11 / 11

## File Classification

| New/Modified File | Role | Closest Analog | Match Quality |
|---|---|---|---|
| `src/gene/vm/extension_abi.nim` | interface | itself | exact |
| `src/gene/vm/extension.nim` | service | itself | exact |
| `src/gene/vm/actor.nim` | service | itself | exact |
| `src/genex/llm.nim` | singleton-state service | itself | exact |
| `src/genex/http.nim` | pool / request-routing service | itself | exact |
| `src/genex/ai/bindings.nim` | queued callback ingress | itself | exact |
| `tests/integration/test_llm_mock.nim` | integration test | itself | exact |
| `tests/integration/test_http.nim` | integration test | itself | exact |
| `tests/integration/test_ai_scheduler.nim` | integration test | itself | exact |
| `tests/integration/test_ai_slack_socket_mode.nim` | integration test | itself | exact |
| docs in `docs/http_server_and_client.md` / `docs/handbook/actors.md` | contract docs | themselves | exact |

## Pattern Assignments

### Extension bootstrap pattern

Use `src/gene/vm/extension_abi.nim` and `src/gene/vm/extension.nim` as the only registration path. Port registration belongs here, not in extension-specific globals.

### Actor-backed ownership pattern

Use `src/gene/vm/actor.nim` as the single mailbox/lifecycle substrate. Port actors should be ordinary actor-backed handles with native handlers.

### Singleton proof pattern

Use `src/genex/llm.nim` as the singleton migration proof. Its current global locks/registry are exactly the concurrency debt Phase 3 is supposed to remove.

### Pool/factory proof pattern

Use `src/genex/http.nim` as the first pool/factory migration. It already has an extension-local worker pool and request-routing logic.

### Global ingress cleanup pattern

Use `src/genex/ai/bindings.nim` as the AI ingress cleanup target. It already owns process-global callback/client state and a scheduler-drained queue.

## Testing Patterns

- extend `tests/integration/test_llm_mock.nim` for singleton-port proof
- extend `tests/integration/test_http.nim` for HTTP migration proof
- extend `tests/integration/test_ai_scheduler.nim` and `tests/integration/test_ai_slack_socket_mode.nim` for AI ingress proof
- add `tests/integration/test_extension_ports.nim` for the generic runtime registration contract

## Anti-Patterns

- New extension concurrency machinery outside `extension_abi` / `extension.nim`
- Keeping global locks/globals as the real ownership model
- Treating thread-API retirement as part of Phase 3
