# Sandbox considerations (pragmatic, opt-in)

This document reframes sandboxing toward small, shippable steps that align with the current codebase. Default posture stays unchanged: no sandbox unless explicitly enabled.

## Goals
- Keep sandboxing **optional and off by default**; zero overhead when disabled.
- Start with **extension loading**: decide which libraries may load and what they’re allowed to do.
- Make enforcement points explicit and minimal; defer filesystem/network mediation until we have a concrete plan and instrumentation.

## Scope (initial)
- **In-scope**: native extension loading (`src/gene/vm/extension.nim`) with capability hints and allowlists.
- **Out of scope for v1**: OS-level sandboxes (seccomp/App Sandbox/job objects), per-op fs/net wrappers, hot reload/version negotiation.

## Baseline defaults
- Compile-time gate: `-d:GENE_EXT_CAPS` (or similar) to include the checks. Without it, everything compiles away.
- Runtime mode (when compiled in): env `GENE_EXT_CAPS=off|log|enforce`.
  - `off`: no checks.
  - `log`: record violations but allow.
  - `enforce`: deny loads that violate policy.

## Minimal capability model (extensions)
- Capabilities: `file`, `network`, `process`, `memory`, `ffi` (call back into host), `unsafe` (full trust). Extend as needed.
- Declaration: extension exports a small metadata symbol (name/version/cap set). Loader reads it.
- Policy: allowlist of library paths/names plus allowed caps. Default (when enabled) allows `file` and `ffi`; denies `network`, `process`; denies `unsafe`.
- Enforcement: if `enforce` and requested caps exceed policy, refuse to load; if `log`, allow but emit a log entry.
- Storage: track granted caps per loaded handle for future per-call guards if we add them.

## Loader touchpoints
- **Before dlopen**: check path/name against allowlist (env `GENE_EXT_ALLOW=/path1:/path2`).
- **After load**: read capability metadata symbol if present; compare to policy/mode.
- **Symbol cache**: cache resolved symbols per handle (perf win, independent of sandbox).

## Suggested implementation steps
1) Add the compile flag + runtime mode plumbing; default remains off.
2) Add allowlist + capability metadata read + policy compare (log-only first).
3) Add symbol cache in the loader.
4) Flip to enforcement when telemetry looks sane.

## Future hooks (when ready)
- Per-call guards using stored caps (e.g., block extension-initiated network if cap missing).
- Optional signature/hash validation for binaries.
- Resource limits per handle (memory/file descriptors).
- Broader fs/net mediation once we choose enforcement points in stdlib/VM.

## Open questions
- Where to store policy long term (env vs config file vs package metadata)?
- Minimal metadata shape for extensions (name, version, caps, optional hash?).
- Default allowlist when `enforce` is on (none vs curated core libs)?
