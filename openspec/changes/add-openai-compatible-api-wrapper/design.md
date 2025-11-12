# Design: OpenAI-Compatible API Wrapper (add-openai-compatible-api-wrapper)

## Context
- Gene currently lacks a first-party client for hosted LLM APIs; users must hand-roll HTTP + JSON glue for each provider.
- OpenAI, OpenRouter, Together, and many others intentionally mimic the OpenAI REST schema (v1). A single OpenAI-compatible wrapper unlocks most SaaS LLM endpoints.
- The spec requires shipping the client under the `genex/ai` namespace with an `OpenAIClient` class that supports chat completions, responses, embeddings, streaming, and structured error propagation.
- We must keep CI/network-free by testing against a mock server while allowing real providers via configuration at runtime.

## Goals / Non-Goals
**Goals**
1. Provide an ergonomic `(new OpenAIClient {...})` API whose methods cover chat, responses, embeddings, and streaming, with consistent option names.
2. Support OpenAI and OpenAI-compatible services by making base URL, model, headers, and version configurable without code changes.
3. Integrate streaming (SSE/chunked) via Gene async primitives so callers can consume tokens incrementally, while also offering blocking helpers.
4. Surface actionable errors (status, request id, retry hints) and redact sensitive data in logs/exceptions.
5. Document setup + security guidance and supply examples + offline tests.

**Non-Goals**
1. Managing fine-tuning, file uploads, batch jobs, or other non-core OpenAI endpoints.
2. Persisting API keys or implementing long-term credential storage—keys stay in memory only.
3. Providing provider-specific features beyond OpenAI-compatible schema; those become follow-up deltas.
4. Adding new VM instructions; everything rides through existing native/stdlib plumbing.

## Key Decisions
1. **Module & Class**: Export `OpenAIClient` from `genex/ai`. The constructor accepts a config map; methods live on the class instance so multiple providers/configs can coexist.
2. **Transport**: Use Nim's `httpclient` with keep-alive disabled by default (safer for proxies). For streaming we leverage `newHttpClient().requestStream` and parse SSE/chunked data manually.
3. **JSON Handling**: Reuse `std/json` for serialization/deserialization. Requests are built as Nim `JsonNode`s, keeping optional fields easy to merge and permitting an `extra` map for passthrough.
4. **Configuration Precedence**: Options map > explicit arguments > env vars > defaults. Env vars follow OpenAI conventions (`OPENAI_API_KEY`, `OPENAI_BASE_URL`, `OPENAI_ORG`). Users can supply provider-specific headers via `^headers`.
5. **Streaming API**: `(client .stream opts handler)` returns a future. The handler executes on the VM event loop for each SSE chunk; completion resolves or raises. Under the hood, a background worker reads the stream to avoid blocking the main dispatch loop.
6. **Error Surface**: Define `OpenAIError` (subclass of `Exception`). Attach `{^status ^provider_error ^request_id ^retry_after}` metadata; secrets are redacted via helper that scrubs header values before logging.
7. **Testing**: Add a Nim-powered mock server (simple HTTP handler) plus fixtures under `tests/openai_mock/`. Unit tests run entirely offline and assert serialization, streaming, and error cases. Examples use env vars but default to mock transcripts if unset.
8. **Extensibility**: Keep HTTP client + request builders decoupled so `AnthropicClient` or other wrappers can reuse the plumbing later inside `genex/ai`.

## Architecture Overview
```
Gene code ── calls ──> OpenAIClient (Gene class wrapping Nim native)
                          │
                          ▼
                 Nim bridge (src/genex/ai/openai_client.nim)
        ┌───────────────┬───────────────┬─────────────────┐
        │Config manager │HTTP adapter   │Streaming worker │
        ▼               ▼               ▼                 │
 env vars+opts   std/json payloads   SSE reader thread    │
        │               │               │                 ▼
        └───────────────┴───────────────┴───> Gene async futures/handlers
```

## Client API Surface
- `(new OpenAIClient {^api_key ..., ^base_url ..., ^model ..., ^headers {...}, ^timeout_ms 30000, ^extra {...}})` → returns client instance.
- `(client .chat opts)` → blocking call to `chat/completions`, returns Gene map mirroring provider schema (`choices`, `usage`, etc.).
- `(client .respond opts)` → hits `responses` endpoint; `opts` supports typed fields plus `^extra` for future provider fields.
- `(client .embeddings opts)` → sends text batches; returns `{^data [ {^embedding [...]} ...] ^usage {...}}` with floats.
- `(client .stream opts handler)` → streaming version of chat/responses; `handler` receives `{^delta ... ^done? bool}` maps.

Each method delegates to shared helpers:
1. `buildPayload(endpoint, optsMap)` – merges required fields, optional typed params, and `extra` map.
2. `performRequest(kind, payload, streaming?)` – configures HTTP headers, handles retries (optional exponential backoff for transient errors), and decodes responses.
3. `normalizeResponse(endpoint, JsonNode)` – converts JSON to Gene `Value`, ensuring sequences remain arrays and numbers remain floats.

## Configuration & Security
- Constructor resolves config once and stores it in a Nim `OpenAIConfig` record. Per-call overrides can be supplied via `opts` map fields (`^model`, `^api_key`, etc.) and merged on the fly.
- Env vars read during instantiation (cached) to avoid repeated syscalls; we expose `(client .reload_config)` for long-running processes.
- Sensitive data (API key, Authorization header) never printed. We add `redact_secret(value)` used by logging/error helpers; it keeps prefix/suffix for debugging (e.g., `sk-****c123`).
- Users can inject custom headers for provider-specific knobs (e.g., `HTTP-Referer` for OpenRouter) via `^headers` map; we whitelist a short list of overrideable headers and merge them with defaults.

## Streaming Implementation
1. `client.stream(opts, handler)` spawns a future using the existing async helpers (`asyncFuture` shim).
2. The future launches a background Nim worker (new thread) that opens the HTTP stream (SSE or chunked depending on provider). We parse `data:` lines, accumulate JSON per message, and send them through a `Channel[GeneValue]` to the VM thread.
3. The VM-side async future polls the channel; each chunk invokes `handler` synchronously on the VM thread to keep user callbacks single-threaded. Errors close the channel and propagate via the future.
4. Completion semantics: we send `{^event :done}` before resolving so handlers can finalize UI/logging. Timeouts cancel the stream and raise `OpenAIError(kind = :timeout)`.

## Error Handling & Observability
- Wrap all failures in `OpenAIError`; attach metadata map accessible from Gene via `(-> $ex metadata)`. Metadata fields include `status`, `type`, `message`, `request_id`, `provider`, `retry_after_ms`, `is_retryable?`.
- HTTP adapter categorizes errors: `4xx` => client errors (no retry unless 429), `5xx` => server errors (retryable), network exceptions => retryable with exponential backoff (configurable via `^max_retries`).
- Optional debug logging (enabled via `GENE_OPENAI_DEBUG=1`) prints request summaries minus sensitive data, plus timing metrics per endpoint.

## Testing Strategy
1. **Mock server**: Implemented with Nim’s `asynchttpserver`, serving deterministic JSON/SSE fixtures loaded from `tests/openai_mock/*.json`. Tests spin it up on localhost and point `OpenAIClient` at it.
2. **Unit tests**: Cover serialization (ensuring opts→payload mapping), env precedence, streaming chunk ordering, embeddings float parsing, and error metadata. Run via `nim c -r tests/test_openai_client.nim` inside CI.
3. **Gene examples**: `examples/llm/openai_chat.gene` and `examples/llm/openai_stream.gene` default to the mock server unless `OPENAI_API_KEY` is set. Docs instruct devs to run `MOCK_OPENAI=true bin/gene run examples/...` for offline testing.
4. **Regression fixtures**: Store sample responses (chat, responses, embeddings) under `openspec/fixtures/openai/*.json` so changes to normalization logic are easy to diff.

## Security & Compliance Notes
- API keys only live in process memory; no file writes. Encourage use of per-session keys in docs.
- Ensure TLS is enforced by default. If users opt into HTTP (e.g., hitting localhost mock), we warn via log.
- Rate-limit guidance: include retry metadata so callers can implement their own backoff; we do not auto-retry indefinitely.
- Streaming handler errors propagate back to the future so user code can `catch *`—we do not swallow exceptions inside callbacks.

## Future Enhancements
- Shared transport utilities inside `genex/ai` for future providers (Anthropic, Google AIA) to avoid duplication.
- Tool-calling convenience wrappers for the Responses API once Gene’s JSON/dict manipulation ergonomics are improved.
- Built-in request tracing hooks (e.g., `(client .with_tracer tracerFn ...)`) to integrate with observability pipelines.
- Automatic metrics instrumentation (latency histograms, success/failure counters) exported via the upcoming diagnostics module.
