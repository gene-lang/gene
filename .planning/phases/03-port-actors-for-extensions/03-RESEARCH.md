# Phase 03: Port Actors for Extensions - Research

**Researched:** 2026-04-20  
**Domain:** Extension-side concurrency, process-global native resources, and actor/port migration  
**Confidence:** MEDIUM

## User Constraints

- Phase 2 is complete and verified. [VERIFIED: `.planning/ROADMAP.md`, `.planning/STATE.md`]
- Thread API removal stays in Phase 4. [VERIFIED: `.planning/ROADMAP.md`]
- Phase 3 should move extension concurrency behind actor/port boundaries, especially for HTTP and LLM integrations. [VERIFIED: `.planning/ROADMAP.md`, `.planning/REQUIREMENTS.md`]

## Requirement

| ID | Description | Research Support |
|----|-------------|------------------|
| ACT-03 | Migrate process-global native resources behind port actors. | This research identifies the current extension hotspots and maps them onto the approved singleton / pool / factory port patterns. |

## Summary

Phase 3 should introduce one extension-port registration substrate and then migrate extensions in order of risk. The approved actor design already defines the three target shapes:

1. singleton port
2. port pool
3. port factory

`genex/llm` is the clearest singleton-port proof because it currently relies on:

- `global_model_registry`
- `global_model_lock`
- `global_llm_op_lock`

(`src/genex/llm.nim:9-14`, `src/genex/llm.nim:780-868`) [VERIFIED: codebase grep]

`genex/http` is the clearest pool/factory migration because it still owns:

- a Gene thread worker pool
- a background poller
- global server/handler state

(`src/genex/http.nim:34-38`, `src/genex/http.nim:967-1054`, `src/genex/http.nim:1419-1547`) [VERIFIED: codebase grep]

The AI bindings layer also has clear global ownership debt:

- `slack_vm_global`
- `slack_callback_global`
- `slack_reply_client_global`

(`src/genex/ai/bindings.nim:655-657`, `src/genex/ai/bindings.nim:981-999`) [VERIFIED: codebase grep]

**Primary recommendation:** split Phase 3 into four plans:

1. extension port-registration substrate
2. `genex/llm` singleton-port migration
3. HTTP + AI binding migration to pool/factory or singleton ports
4. docs and verification closeout

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Port registration API | VM / extension ABI | Actor runtime | Extensions already bootstrap through `extension_abi` / `extension.nim`; ports should enter there. |
| Singleton migration | `genex/llm` | Actor runtime | LLM already centralizes backend access behind explicit global locks. |
| Pool/factory migration | `genex/http`, AI bindings | Extension scheduler integration | HTTP already models a worker pool; AI bindings already own queued callback ingress. |
| User-facing migration guidance | docs / examples | tests | Phase 3 must document port boundaries while keeping Phase 4 thread removal separate. |

## Likely Migration Targets

| Module | Current Problem | Port Shape | Why |
|--------|-----------------|------------|-----|
| `src/genex/llm.nim` | process-global locks/registry | Singleton | One serialized mailbox is the right model for a thread-unsafe backend. |
| `src/genex/http.nim` | extension-local Gene thread worker pool | Pool or factory | HTTP already has pooled request work and stateful ownership. |
| `src/genex/ai/bindings.nim` | process-global callback/client state | Singleton or pool | It owns process-level ingress/callback state today. |

## Anti-Patterns

- Reusing the public thread API as the extension concurrency boundary
- Leaving global locks/globals as the real ownership model after ports are introduced
- Pulling Phase 4 thread-removal work into Phase 3
