import os, strutils, tables
when defined(macosx):
  import posix

import ../types/type_defs

const
  DEFAULT_HOT_THRESHOLD = 100
  DEFAULT_VERY_HOT_THRESHOLD = 1000

proc default_jit_state*(): JitState =
  ## Build-time defaults; gated by -d:geneJit.
  result.enabled = defined(geneJit)
  result.log_enabled = false
  result.hot_threshold = DEFAULT_HOT_THRESHOLD
  result.very_hot_threshold = DEFAULT_VERY_HOT_THRESHOLD
  result.call_counts = initTable[pointer, int64]()

proc apply_env_overrides*(state: var JitState) =
  ## Override JIT configuration using environment variables.
  let env_enabled = getEnv("GENE_JIT", "")
  if env_enabled.len > 0:
    state.enabled = env_enabled != "0"

  let env_hot = getEnv("GENE_JIT_THRESHOLD", "")
  if env_hot.len > 0:
    try:
      state.hot_threshold = parseInt(env_hot)
    except ValueError:
      discard

  let env_very_hot = getEnv("GENE_JIT_VERY_HOT", "")
  if env_very_hot.len > 0:
    try:
      state.very_hot_threshold = parseInt(env_very_hot)
    except ValueError:
      discard

  let env_log = getEnv("GENE_JIT_LOG", "")
  if env_log.len > 0:
    state.log_enabled = env_log != "0"

  # Guardrails for bad inputs
  if state.hot_threshold <= 0:
    state.hot_threshold = DEFAULT_HOT_THRESHOLD
  if state.very_hot_threshold <= 0:
    state.very_hot_threshold = DEFAULT_VERY_HOT_THRESHOLD

proc init_jit_state*(): JitState =
  ## Initialize JIT state with build defaults and environment overrides.
  result = default_jit_state()
  result.apply_env_overrides()

  when defined(macosx) and defined(amd64):
    # Rosetta (x86_64 translated on Apple Silicon) cannot safely run our raw
    # x86 JIT pages; detect and disable to avoid SIGILL.
    var translated: cint
    var size = sizeof(cint)
    if sysctlbyname("sysctl.proc_translated", addr translated, addr size, nil, 0) == 0:
      if translated == 1:
        result.enabled = false
