# GeneClaw

A tool-using AI agent platform built entirely in Gene.

## What it does

GeneClaw receives commands (via REST API or Slack webhook), runs a bounded agent loop that can call tools, and returns the result. All tool calls go through a policy gate and are audit-logged to SQLite.

## Architecture

```
Slack/REST → Router → Agent Orchestrator → LLM (OpenAI)
                              ↓
                      Tool Registry ← Policy Gate
                        ↓      ↓       ↓       ↓
                     shell  read_file  http   get_time
                              ↓
                      SQLite (memory + audit)
```

## Files

- `src/main.gene` - HTTP server, routing, Slack webhook handler
- `src/agent.gene` - Agent run loop with step/tool-call budget
- `src/tools.gene` - Tool registry, policy engine, built-in tools
- `src/config.gene` - Environment variable configuration
- `src/db.gene` - SQLite schema, memory, audit log, run tracking

## Quick start

```bash
# Build Gene (from repo root)
cd gene && nimble build

# Run GeneClaw
cd example-projects/geneclaw
../../gene/bin/gene run src/main.gene
```

## Configuration

| Variable | Default | Description |
|---|---|---|
| `OPENAI_API_KEY` | (empty = mock mode) | OpenAI API key |
| `OPENAI_MODEL` | `gpt-4o-mini` | Model to use |
| `SLACK_SIGNING_SECRET` | | Slack app signing secret |
| `SLACK_BOT_TOKEN` | | Slack bot OAuth token |
| `GENECLAW_WORKSPACE` | `/tmp/geneclaw` | Filesystem tool root |

## API

**Health check:**
```
GET /health
```

**Send message:**
```
POST /api/chat
{"workspace_id": "ws1", "user_id": "u1", "channel_id": "general", "text": "what time is it?"}
```

**Slack webhook:**
```
POST /slack/events
(Slack Events API payload)
```

## Built-in tools

- `get_time` - Current date/time
- `shell` - Run allowlisted commands (ls, cat, echo, date, etc.)
- `read_file` - Read files within workspace (path-traversal blocked)
- `write_file` - Write files within workspace
- `http_get` - Fetch a URL

## Safety

- Tool calls go through a policy gate before execution
- Shell commands are restricted to an allowlist
- File operations are scoped to the workspace directory
- Path traversal (`..`) is rejected
- All tool invocations are audit-logged with run_id, duration, args, and result
- Agent runs are bounded by `MAX_STEPS` (16) and `MAX_TOOL_CALLS` (8)
