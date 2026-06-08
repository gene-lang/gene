# GeneClaw New

`geneclaw-new` is a clean implementation prototype for the Gene-native agent
runtime design in `design.md`.

This version starts with the smallest useful vertical slice:

- event-sourced run kernel
- lightweight actor registry and actor-pool message runtime
- append-only event store with in-memory cache
- SQLite-backed query index for run events and memory facts
- shared kernel limit normalization for budgets, deadlines, and output bounds
- typed tool registry shape
- bounded fake tool execution
- typed tool argument validation
- trusted-local shell/read/search/patch built-in tools
- enforced shell command timeouts through Gene `system/run`
- large tool output references
- provider-neutral model gateway
- runtime model profile resolution for fast/standard/frontier/local/vision/code
- fake model adapter through the gateway
- OpenAI/Anthropic payload builders, response normalizers, and opt-in live adapters
- model stream delta normalization
- `skill.gene` package loader
- skill compiler manifests with validation, provider schemas, docs snippets, eval fixtures, and cache keys
- `repo-review` skill with tool/workflow/example declarations
- workflow graph/checkpoint engine with conditional edges and run-level step events
- provider tool-spec generation from skill-allowed tools
- durable run-summary memory facts
- memory retrieval events for follow-up runs
- CLI memory search
- REST-style run/events/cancel/memory route functions
- host-agnostic REST daemon lifecycle and request-history wrapper
- Slack command/status/final payload adapters
- TUI dashboard/run view-model and text rendering helpers
- durable scheduled jobs with one-shot, interval, and dead-letter states
- scheduler dispatcher that launches runs through the agent kernel
- Gene-data eval fixtures
- eval assertion replay and performance summaries
- release checklist commands
- CLI entrypoint for run/status/events/cancel/reset
- smoke tests for replayable runs

The first target is a trusted single-user local daemon/runtime. Security policy,
multi-user isolation, and sandbox backends are deferred hardening work; run
budgets, tool limits, event logs, and cancellation-oriented state are part of
the core runtime.

Run the smoke tests from this directory:

```sh
../../bin/gene run tests/test_run_kernel.gene
../../bin/gene run tests/test_agent_slice.gene
../../bin/gene run tests/test_event_replay.gene
../../bin/gene run tests/test_tool_codecs.gene
../../bin/gene run tests/test_tool_runtime.gene
../../bin/gene run tests/test_limits.gene
../../bin/gene run tests/test_storage_index.gene
../../bin/gene run tests/test_model_gateway.gene
../../bin/gene run tests/test_workflows.gene
../../bin/gene run tests/test_skills.gene
../../bin/gene run tests/test_skill_compiler.gene
../../bin/gene run tests/test_actor_runtime.gene
../../bin/gene run tests/test_memory.gene
../../bin/gene run tests/test_channels.gene
../../bin/gene run tests/test_rest_daemon.gene
../../bin/gene run tests/test_tui.gene
../../bin/gene run tests/test_scheduler.gene
../../bin/gene run tests/test_evals.gene
```

Run the demo:

```sh
../../bin/gene run src/main.gene reset
../../bin/gene run src/main.gene run "review the current diff"
../../bin/gene run src/main.gene run --skill repo-review "review the current diff"
../../bin/gene run src/main.gene run --skill repo-review --workflow default "review the current diff"
../../bin/gene run src/main.gene run --profile fake "review the current diff"
../../bin/gene run src/main.gene run --provider openai --model gpt-5-mini "review the current diff"
../../bin/gene run src/main.gene status run-1
../../bin/gene run src/main.gene events run-1
../../bin/gene run src/main.gene memory search diff
../../bin/gene run src/main.gene schedule add "review the repo"
../../bin/gene run src/main.gene schedule run-due
```

Events are stored under `$GENECLAW_NEW_HOME` or `/tmp/geneclaw-new` by default.

Live model calls are disabled by default so local tests and demos stay offline.
Enable them explicitly with `GENECLAW_MODEL_LIVE=true` plus provider credentials:

- OpenAI: `OPENAI_API_KEY` or `OPENAI_AUTH_TOKEN`, optional `OPENAI_MODEL`,
  `OPENAI_BASE_URL`, `OPENAI_ACCOUNT_ID`, `OPENAI_TIMEOUT_MS`
- Anthropic: `ANTHROPIC_API_KEY` or `ANTHROPIC_AUTH_TOKEN`, optional
  `ANTHROPIC_MODEL`, `ANTHROPIC_BASE_URL`, `ANTHROPIC_TIMEOUT_MS`

Profile defaults can be overridden with `GENECLAW_FAST_MODEL`,
`GENECLAW_STANDARD_MODEL`, `GENECLAW_FRONTIER_MODEL`,
`GENECLAW_VISION_MODEL`, `GENECLAW_CODE_MODEL`, and matching
`GENECLAW_*_PROVIDER` variables.
