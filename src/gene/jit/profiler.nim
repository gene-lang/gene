import tables

import ../types/type_defs

proc ensure_counts(state: var JitState) {.inline.} =
  if state.call_counts.len == 0:
    state.call_counts = initTable[pointer, int64]()

proc record_call*(state: var JitState, fn: Function) {.inline.} =
  ## Increment hotness counter for a function when JIT is enabled.
  if not state.enabled:
    return
  state.ensure_counts()
  let key = cast[pointer](fn)
  state.call_counts.mgetOrPut(key, 0).inc()
  state.stats.executions.inc()

proc is_hot*(state: var JitState, fn: Function): bool {.inline.} =
  if not state.enabled:
    return false
  let key = cast[pointer](fn)
  state.call_counts.getOrDefault(key) >= state.hot_threshold

proc is_very_hot*(state: var JitState, fn: Function): bool {.inline.} =
  if not state.enabled:
    return false
  let key = cast[pointer](fn)
  state.call_counts.getOrDefault(key) >= state.very_hot_threshold

proc reset_call_counts*(state: var JitState) =
  ## Clear hotness counters (used when invalidating caches).
  if state.call_counts.len > 0:
    state.call_counts.clear()
