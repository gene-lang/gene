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
- trusted-local shell/read/search/patch and web search/fetch/read built-in tools
- enforced shell command timeouts through Gene `system/run`
- large tool output references
- provider-neutral model gateway
- runtime model profile resolution for fast/standard/frontier/local/vision/code
- fake model adapter through the gateway
- OpenAI/Anthropic payload builders, response normalizers, and opt-in live adapters
- model stream delta normalization
- `skill.gene` package loader
- skill compiler manifests with validation, provider schemas, docs snippets, and cache keys
- `repo-review` and `gene-coding` skills with tool/workflow/example declarations
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
- inline Gene-data eval definitions
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
../../bin/gene run tests/test_code_eval.gene
../../bin/gene run tests/test_shell_eval.gene
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
../../bin/gene run tests/test_cli.gene
../../bin/gene run tests/test_evals.gene
```

Run the demo:

```sh
../../bin/gene run src/main.gene reset
../../bin/gene run src/main.gene run "review the current diff"
../../bin/gene run src/main.gene run --skill repo-review "review the current diff"
../../bin/gene run src/main.gene run --skill repo-review --workflow default "review the current diff"
../../bin/gene run src/main.gene run --skill gene-coding "teach me how to write and run a Gene expression"
../../bin/gene run src/main.gene run --skill gene-coding "run this Gene code: (+ 1 2)"
../../bin/gene run src/main.gene run --profile fake "review the current diff"
../../bin/gene run src/main.gene run --provider openai --model gpt-5-mini "review the current diff"
../../bin/gene run src/main.gene run "(+ 1 2)"
../../bin/gene run src/main.gene run "= (+ 1 2)"
../../bin/gene run src/main.gene run "! printf 'hello\nworld\n' | wc -l"
../../bin/gene run src/main.gene status run-1
../../bin/gene run src/main.gene events run-1
../../bin/gene run src/main.gene memory search diff
../../bin/gene run src/main.gene schedule add "review the repo"
../../bin/gene run src/main.gene schedule run-due
```

Events are stored under `$GENECLAW_NEW_HOME` or `/tmp/geneclaw-new` by default.

Inputs whose trimmed text starts with `(`, or starts with `=` followed by code,
are evaluated as Gene code instead of being sent to the agent loop. The leading
`=` is stripped before evaluation and persistence. Evaluation runs in a
per-session scratch context with persistent vars/functions, GeneClaw metadata in
`geneclaw`, and a `(tool "name" {...})` helper for calling registered tools.
Session state is stored under `$GENECLAW_NEW_HOME/eval/sessions`.

Inside GeneClaw eval code, the `geneclaw` map exposes the current agent context:
`geneclaw/run_id`, `geneclaw/session`, `geneclaw/workspace_root`, and
`geneclaw/store_root`. The helpers `(geneclaw_workspace)` and
`(geneclaw_store)` return the workspace and store roots. Eval code can call
registered tools with `(tool "name" {...})`, for example:

```gene
(geneclaw_workspace)
(tool "shell.run" {^cmd "pwd"})
(tool "file.read" {^path "README.md"})
```

The `gene-coding` skill gives the live model these same rules. It exposes a
`gene.eval` tool for context-aware snippets, so requests that inspect
`geneclaw`, `(geneclaw_workspace)`, `(geneclaw_store)`, or `(tool ...)` do not
fall back to plain `gene eval`, which lacks GeneClaw context. Runtime
configuration comes from environment variables such as `GENECLAW_NEW_HOME`,
`GENECLAW_WORKSPACE_ROOT`, `GENECLAW_GENE_BIN`, `GENECLAW_MODEL_LIVE`,
`GENECLAW_PROVIDER`, `GENECLAW_PROFILE`, and `GENECLAW_MODEL`; change persistent
local config in the shell environment or `.env`.
Plain agent requests that mention Gene code, eval, context, state, config, or
workspace access infer `gene-coding` when no explicit `--skill` is set.

Inputs whose trimmed text starts with `!` run as trusted local shell commands
through `bash -lc` in the GeneClaw workspace root. The leading `!` is stripped
before creating the run, so history and events store the command itself.

The TUI uses a Codex-style scrollback interface with a zero-padded prompt like
`0001›`, muted run status lines, raw command output, and response-colored agent
messages. It
supports slash commands: `/help` lists commands, `/reset` clears runtime session
data while preserving daemon files, `/show-prompt <text>` prints the inferred
model prompt without creating a run, `/clear` clears the screen, and `/exit`
exits.

Web tools are available as normal GeneClaw tools:

- `web.search` returns structured search results. It defaults to Mojeek HTML
  search and can be configured with `GENECLAW_SEARCH_PROVIDER`.
- `web.fetch` returns raw URL content and HTTP metadata.
- `web.read` returns readable page text, title, and links.

Live model calls are disabled by default so local tests and demos stay offline.
Enable them explicitly by sourcing `.env` with `GENECLAW_MODEL_LIVE=true`
plus provider credentials. With live mode on, a plain
`../../bin/gene run src/main.gene run "..."` resolves to the standard live
profile unless overridden by CLI flags.

- OpenAI: `OPENAI_API_KEY` or `OPENAI_AUTH_TOKEN`, optional `OPENAI_MODEL`,
  `OPENAI_BASE_URL`, `OPENAI_ACCOUNT_ID`, `OPENAI_TIMEOUT_MS`
- Anthropic: `ANTHROPIC_API_KEY` or `ANTHROPIC_AUTH_TOKEN`, optional
  `ANTHROPIC_MODEL`, `ANTHROPIC_BASE_URL`, `ANTHROPIC_TIMEOUT_MS`

Default CLI provider/profile/model can be set with `GENECLAW_PROVIDER`,
`GENECLAW_PROFILE`, and `GENECLAW_MODEL`. CLI flags such as `--provider`,
`--profile`, and `--model` still take precedence.

Profile defaults can be overridden with `GENECLAW_FAST_MODEL`,
`GENECLAW_STANDARD_MODEL`, `GENECLAW_FRONTIER_MODEL`,
`GENECLAW_VISION_MODEL`, `GENECLAW_CODE_MODEL`, and matching
`GENECLAW_*_PROVIDER` variables.
