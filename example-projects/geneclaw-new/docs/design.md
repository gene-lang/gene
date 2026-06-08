# GeneClaw Design

Status: draft design

Reader: future Gene maintainers and contributors.

Post-read action: turn this design into milestones, module contracts, and
implementation slices for a Gene-native agent runtime.

## Thesis

GeneClaw should be the best agent runtime for Gene, not a port of an existing
agent framework.

Its core advantage should be that agent systems are expressed as ordinary Gene
values:

- skills are Gene values
- tool schemas are Gene values
- workflows are Gene values
- run traces are Gene values
- memory records are Gene values
- evaluations are Gene values
- configuration is Gene values

The runtime should make those values executable, inspectable, serializable,
queryable, testable, and replayable.

The target product is a local-first agent daemon for a trusted operator. The
first useful version should not block on a multi-user security model or sandbox
backend. It should still have operational guardrails: run budgets, tool
timeouts, output limits, durable event logs, cancellation, and clear failure
states.

## Design Principles

1. Agent state is data first.
   A run should not be hidden in provider-specific message arrays or process
   memory. Every meaningful state transition should be a Gene event.

2. The event log is the source of truth.
   UI, resume, replay, evals, memory extraction, debugging, and observability
   should all derive from the same run event stream.

3. Tool boundaries are typed.
   Internal workflow code can stay dynamic, but tool inputs, outputs, and error
   contracts should be explicit. This gives gradual typing a concrete job.

4. Skills are packages, not prompt files.
   A skill should contain metadata, tool definitions, workflows, examples,
   tests, and optional implementation code.

5. The runtime is actor-shaped.
   Agents, tool calls, streams, schedulers, and background jobs are naturally
   concurrent. Use Gene actors for isolation of control flow and failure
   boundaries, even when all work stays in one trusted local process.

6. Keep provider details at the edge.
   OpenAI, Anthropic, local models, and future providers should see generated
   request payloads. The core runtime should see Gene run events and tool calls.

7. Optimize the hot path after the shape is correct.
   Agent workloads are dominated by model calls, I/O, browser automation, and
   JSON. Start with a persistent daemon, cached tool specs, direct Gene values
   internally, and GIR/cache-friendly module loading.

## Non-Goals For The First Serious Version

- Multi-tenant RBAC
- Shell sandboxing
- Filesystem sandboxing
- Skill marketplace trust
- Remote user isolation
- Distributed agent nodes
- Full self-improving skill generation

Those can be added later as plugins or hardening layers. The core design should
leave extension points for them, but not depend on them.

## Core Architecture

```text
geneclaw/
  kernel/
    runs          # run state machine and event append logic
    events        # event model, validation, replay
    limits        # budgets, deadlines, cancellation, output bounds
  models/
    gateway       # provider-neutral model interface
    adapters      # OpenAI, Anthropic, local, future providers
  tools/
    registry      # tool definitions and invocation
    codecs        # schema validation, result normalization
    builtin       # shell, file, http, browser, search, db
  skills/
    loader        # load skill packages
    compiler      # compile Gene skill DSL into runtime definitions
    tests         # skill examples and eval hooks
  workflows/
    engine        # graph/step execution
    planner       # optional planning pass
    patterns      # common agent loops
  memory/
    store         # append/recent/search/summarize
    extractors    # turn runs into durable facts
    retrieval     # query-time context assembly
  scheduler/
    jobs          # durable jobs and recurrence
    dispatcher    # launch runs from schedules
  channels/
    cli
    tui
    rest
    slack
  observability/
    trace
    metrics
    evals
```

The important boundary is this:

```text
channel -> command envelope -> run kernel -> model gateway
                                      -> tool runtime
                                      -> workflow engine
                                      -> memory service
                                      -> event store
```

Channels do not execute tools. Models do not mutate state. Tools do not talk to
providers. Memory extraction is derived from events, not hand-written into every
feature.

## Canonical Runtime Objects

### Command Envelope

Every channel normalizes input into one command shape.

```gene
(command
  ^id "cmd-2026-0001"
  ^channel "slack"
  ^session "slack:C123:T456"
  ^user "local-operator"
  ^text "review the latest diff and run tests"
  ^attachments []
  ^received_at "2026-06-07T12:00:00Z")
```

### Run

A run is a durable state machine plus an append-only event stream.

```gene
(run
  ^id "run-2026-0001"
  ^state "running"
  ^session "slack:C123:T456"
  ^goal "review the latest diff and run tests"
  ^budgets {^steps 24 ^tool_calls 16 ^tokens 100000}
  ^deadline_ms 600000
  ^events [])
```

Run states:

```text
queued
running
waiting_tool
waiting_model
waiting_user
completed
failed
cancelled
timed_out
```

`waiting_user` is useful for confirmations and missing information, but it is
not a security requirement. It is a product state.

### Event

Every state change is an event.

```gene
(run_event
  ^run_id "run-2026-0001"
  ^index 7
  ^type "tool.result"
  ^at "2026-06-07T12:00:05Z"
  ^data {
    ^tool "shell"
    ^status "ok"
    ^duration_ms 8214
    ^output_ref "runs/run-2026-0001/tool-003.out"
  })
```

Core event types:

```text
run.started
user.message
model.request
model.response
model.error
tool.call
tool.stdout
tool.stderr
tool.result
workflow.step.started
workflow.step.completed
memory.retrieved
memory.written
run.completed
run.failed
run.cancelled
```

The event log should be compact enough for frequent writes and rich enough for
debugging without reconstructing hidden process state.

### Tool Definition

Tools are typed runtime contracts.

```gene
(tool
  ^name "shell.run"
  ^description "Run a local shell command and capture bounded output."
  ^input {
    ^cmd String
    ^cwd String?
    ^timeout_ms Int?
    ^max_output_bytes Int?
  }
  ^output {
    ^exit_code Int
    ^stdout_ref String?
    ^stderr_ref String?
    ^summary String?
  })
```

The trusted-local v1 can expose powerful tools. The runtime still enforces
deadlines and output limits so the agent remains debuggable and cancellable.

### Tool Call

```gene
(tool_call
  ^run_id "run-2026-0001"
  ^tool "shell.run"
  ^args {
    ^cmd "nim c -r tests/test_dynamic_binding.nim"
    ^cwd "."
    ^timeout_ms 30000
    ^max_output_bytes 65536
  })
```

Tool execution should return structured results even on failure:

```gene
(tool_result
  ^status "failed"
  ^exit_code 1
  ^summary "test_dynamic_binding failed in Bool return case"
  ^stdout_ref "runs/run-2026-0001/tool-004.stdout"
  ^stderr_ref "runs/run-2026-0001/tool-004.stderr")
```

### Skill

A skill is a Gene package that can define tools, workflows, prompts, examples,
and tests.

```gene
(skill
  ^name "repo-review"
  ^version "0.1.0"
  ^description "Review a source tree, identify risks, patch defects, and verify."

  (tools
    (use "shell.run")
    (use "fs.read")
    (use "fs.patch")
    (use "search.rg"))

  (workflow ^name "review-diff"
    (step ^name "inspect"  ^uses ["search.rg" "fs.read"])
    (step ^name "reason"   ^model "frontier")
    (step ^name "patch"    ^uses ["fs.patch"])
    (step ^name "verify"   ^uses ["shell.run"])
    (step ^name "summarize")))

  (examples
    (example
      ^input "review the current diff"
      ^expect_events ["tool.call" "tool.result" "run.completed"])))
```

The skill compiler should generate:

- provider tool schemas
- runtime validators
- docs snippets
- eval fixtures
- workflow graph metadata
- cache keys for invalidation

This is where Gene should feel different from YAML-plus-prompts systems.

## Agent Loop

The default loop should be simple and event-sourced.

```text
1. Append run.started.
2. Retrieve relevant memory and append memory.retrieved.
3. Build a model request from run state, events, skill context, and tools.
4. Append model.request.
5. Receive model response and append model.response.
6. If the response asks for tool calls:
   - validate tool args
   - append tool.call
   - execute tools with limits
   - append tool.result
   - continue
7. If the response is final:
   - append run.completed
   - return final message to the channel
8. If budgets or deadlines are exceeded:
   - append run.failed or run.timed_out
```

This loop should be a runtime primitive, not one giant function. Different
skills should be able to replace or extend the strategy for request building,
tool-call batching, summarization, and verification.

## Workflow Engine

The workflow engine should support more than free-form ReAct loops without
turning into a heavyweight BPM system.

Minimum workflow model:

```gene
(workflow ^name "implement-and-verify"
  (step ^name "understand" ^kind "model")
  (step ^name "edit"       ^kind "tools")
  (step ^name "test"       ^kind "tools")
  (step ^name "review"     ^kind "model")
  (edge "understand" "edit")
  (edge "edit" "test")
  (edge "test" "review")
  (edge "review" "edit" ^when "needs_changes")
  (edge "review" "done" ^when "accepted"))
```

The engine should provide:

- ordered steps
- conditional edges
- loop limits
- per-step model/tool budgets
- checkpoint events
- resume from last completed step
- human-readable status

Do not put every task into a workflow. The open-ended agent loop should remain
the default. Workflows are for repeated tasks where the structure has proven
useful.

## Memory Design

Memory should be derived from runs and made queryable.

Layers:

| Layer | Purpose |
|---|---|
| Recent context | Last N user/model/tool events for the current session |
| Run event log | Complete trace for replay and audit |
| Summaries | Compacted session/project summaries |
| Facts | Small durable observations about user, repo, tools, failures |
| Artifacts | Files, reports, generated docs, screenshots |
| Skill memory | Lessons associated with a skill |
| Retrieval index | Search over summaries, facts, artifacts, and selected events |

Memory write should be explicit:

```gene
(memory_fact
  ^scope "project"
  ^key "test.dynamic_binding.command"
  ^value "nim c -r tests/test_dynamic_binding.nim"
  ^source_run "run-2026-0001"
  ^confidence "high")
```

Memory retrieval should produce context objects, not raw text blobs:

```gene
(memory_context
  ^query "how do we test dynamic FFI?"
  ^items [
    (fact ^key "test.dynamic_binding.command" ...)
    (summary ^session "repo-maintenance" ...)
  ])
```

Start with SQLite plus FTS. Add embeddings only when keyword and structured
retrieval stop being enough.

## Model Gateway

The model gateway should hide provider-specific request formats from the core.

Core contract:

```gene
(model_request
  ^run_id "run-2026-0001"
  ^profile "frontier"
  ^messages [...]
  ^tools [...]
  ^response_format "agent_step")
```

```gene
(model_response
  ^provider "openai"
  ^model "frontier-current"
  ^stop_reason "tool_calls"
  ^content [...]
  ^tool_calls [...])
```

Provider adapters should handle:

- tool schema encoding
- streaming event conversion
- retryable error classification
- token usage normalization
- model capability mapping
- provider-specific response quirks

The core should reason in terms of model profiles:

```text
fast
standard
frontier
local
vision
code
```

Profiles are runtime configuration. They should not leak into skill logic as
provider names.

## Actor Runtime Shape

GeneClaw should use actors for runtime boundaries:

```text
run actor
  owns one run state machine

tool actor pool
  executes bounded local tools

model actor pool
  handles provider calls and streaming

scheduler actor
  wakes durable jobs and creates runs

memory actor
  serializes writes and retrieval index updates

channel actors
  translate external events into command envelopes
```

This maps naturally onto Gene's actor model and avoids one giant event loop.

Important rule: actor boundaries should pass serializable Gene values, not
provider-specific objects or raw host handles.

## Interfaces

### CLI

The CLI should be the fastest feedback surface:

```text
geneclaw ask "review the current diff"
geneclaw run repo-review.review-diff
geneclaw status run-2026-0001
geneclaw events run-2026-0001
geneclaw cancel run-2026-0001
geneclaw memory search "dynamic FFI tests"
```

### TUI

The TUI should expose:

- active runs
- event stream
- tool output
- memory hits
- scheduled jobs
- skill list
- model/provider status

### REST

REST should expose:

```text
POST /runs
GET  /runs/:id
GET  /runs/:id/events
POST /runs/:id/cancel
GET  /skills
GET  /memory/search
POST /schedules
```

### Slack

Slack should be a channel adapter, not a core dependency. It should:

- verify request signatures
- dedupe events
- create command envelopes
- stream concise status updates
- post final summaries

Signature verification remains useful even in single-user mode because Slack is
an external ingress point.

## Storage

Use local-first durable storage.

Minimum stores:

```text
runs
run_events
tool_outputs
sessions
memory_facts
memory_summaries
skills
scheduled_jobs
artifacts
```

SQLite is the right first store:

- simple deployment
- transactions
- FTS
- enough concurrency for local daemon use
- easy backup

Large tool outputs and artifacts can live as files referenced by the database.

## Observability And Evals

GeneClaw should treat observability as product infrastructure.

Every run should answer:

- What was the user trying to do?
- Which model was called?
- Which tools were called?
- What changed?
- What failed?
- What did the agent learn?
- Which step consumed the most time?

Evaluation should be a first-class skill/test concern:

```gene
(eval
  ^name "repo-review-basic"
  ^skill "repo-review"
  ^input "review this diff"
  ^fixture "fixtures/simple-bug"
  ^assertions [
    (event_exists "tool.call")
    (event_exists "tool.result")
    (final_contains "tests")
  ])
```

This gives Gene a durable way to improve agent quality without relying only on
manual demos.

## Performance Strategy

The app should optimize for warm daemon latency and I/O throughput.

Immediate decisions:

- persistent daemon, not per-command process startup
- cached skill and tool specs
- GIR-loaded runtime modules where practical
- direct Gene values internally, JSON only at provider/channel boundaries
- bounded output files instead of giant strings in memory
- actor pools for independent tool and model calls
- SQLite prepared statements for event writes
- string/key interning for event types, tool names, roles, and schema keys

Do not make JIT a prerequisite. Build the app, measure real agent workloads,
then optimize the specific hot paths.

## Build Sequence

### Milestone 1: Run Kernel

Deliver:

- run state machine
- append-only event store
- CLI to create/status/cancel runs
- in-process fake model adapter
- one fake tool

Exit:

- a run can start, emit events, call a fake tool, complete, and replay

### Milestone 2: Tool Runtime

Deliver:

- tool registry
- schema validation
- bounded execution
- shell, file read, file patch, search tools
- output references

Exit:

- a run can inspect a repo, patch a file, run a command, and show full events

### Milestone 3: Model Gateway

Deliver:

- provider-neutral request/response model
- OpenAI and Anthropic adapters
- streaming model events
- retry/error normalization

Exit:

- a real model can drive tool calls through the run kernel

### Milestone 4: Skills

Deliver:

- `skill.gene` loader
- tool and workflow declarations
- examples/tests
- generated provider tool specs

Exit:

- repo-review is implemented as a skill, not hard-coded agent behavior

### Milestone 5: Memory

Deliver:

- recent session context
- run summaries
- durable facts
- FTS retrieval
- memory extraction from completed runs

Exit:

- a follow-up run can use retrieved facts from a prior run

### Milestone 6: Streaming Interfaces

Deliver:

- REST run/events endpoints
- TUI event view
- Slack command adapter
- Slack status/final updates

Exit:

- the same run can be launched from CLI or Slack and observed live

### Milestone 7: Scheduler

Deliver:

- durable scheduled jobs
- interval recurrence
- retry/dead-letter behavior
- run creation from jobs

Exit:

- a scheduled repo-health skill runs after restart and reports results

### Milestone 8: Quality Loop

Deliver:

- eval DSL
- replay harness
- regression fixtures
- performance counters
- release checklist

Exit:

- changes to skills/runtime can be evaluated before release

## Deferred Hardening

These should not block the first strong local version:

- multi-user accounts
- role-based permissions
- shell command allowlists
- filesystem scopes
- Docker or process sandbox backends
- signed skill packages
- remote skill marketplace
- remote agent nodes

The design should keep extension points for those layers:

- tool calls already flow through one registry
- run events already record all tool activity
- skills already declare tools and workflows
- channels already normalize users/sessions
- storage already records scope fields

That is enough to add hardening later without distorting v1.

## Open Design Questions

1. Should workflow execution be interpreted directly from Gene values, compiled
   into bytecode, or both?
2. Should skill packages be ordinary Gene packages with a convention, or a
   separate package type?
3. How much of the event model belongs in stable Gene docs versus GeneClaw docs?
4. Should run replay be exact, or should it allow model calls to be replaced by
   recorded responses for deterministic testing?
5. Should memory extraction be model-driven, rule-driven, or hybrid?
6. How should large artifacts be addressed: content hash, run-local path, or
   logical artifact id?

## The Design In One Sentence

GeneClaw is an event-sourced, actor-backed, local-first agent daemon where
skills, tools, workflows, memory, evaluations, and traces are all executable
Gene data.
