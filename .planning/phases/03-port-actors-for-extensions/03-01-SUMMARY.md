---
phase: 03-port-actors-for-extensions
plan: 01
subsystem: runtime
tags: [nim, extensions, actors, ports, abi]
requires:
  - phase: 02
    provides: Actor handles, send tiers, reply futures, and stop semantics
provides:
  - Extension host ABI support for singleton, pool, and factory port registration
  - Runtime-backed port registration/materialization helpers
  - Integration coverage for the ABI path and actor-backed handle materialization
affects: [03-02, 03-03, extension-runtime, actor-runtime]
key-files:
  created:
    - tests/integration/test_extension_ports.nim
  modified:
    - src/gene/types/type_defs.nim
    - src/gene/vm/actor.nim
    - src/gene/vm/extension_abi.nim
    - src/gene/vm/extension.nim
completed: 2026-04-20T19:24:46Z
---

# Phase 3 Plan 1 Summary

**The extension host ABI can now register actor-backed singleton, pool, and factory ports**

## Accomplishments

- Added `ExtensionPortKind` to the shared type layer so the runtime and extension ABI speak the same port-shape language.
- Extended `GeneHostAbi` with a port-registration callback and added extension-side wrappers for singleton, pool, and factory registration.
- Added runtime-backed registration/materialization helpers in `src/gene/vm/extension.nim` that create singleton and pool actor handles immediately and can spawn factory-backed handles on demand.
- Added [test_extension_ports.nim](/Users/gcao/gene-workspace/gene-old/tests/integration/test_extension_ports.nim) to prove:
  - registration fails until the actor runtime is enabled
  - singleton ports materialize as `VkActor`
  - pool ports materialize as arrays of independent `VkActor` handles
  - factory registrations can spawn fresh actor-backed handles later

## Decisions Made

- Kept factory ports as registered definitions plus an explicit runtime materializer instead of inventing a first user-facing factory surface in the substrate wave.
- Required an active actor runtime for actual port materialization instead of auto-enabling actors inside the ABI bridge.
- Reused `prepare_actor_payload_for_send` for cloned pool state so mutable init-state graphs are duplicated consistently with the existing actor transport rules.

## Verification

- `nim c -r tests/integration/test_extension_ports.nim`

## Follow-up for 03-02

- `genex/llm` can now migrate onto the singleton-port substrate without inventing its own port API.
- Actor-runtime enablement expectations for port-backed extensions remain a migration concern for the extension waves, not for the substrate itself.
