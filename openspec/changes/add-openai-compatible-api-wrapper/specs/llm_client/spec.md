## ADDED Requirements

### Requirement: `genex/ai` Namespace and Client Class
Gene SHALL provide an `OpenAIClient` class exported from the `genex/ai` module so programs have a stable entry point for OpenAI-compatible APIs.

#### Scenario: Client instantiation
- **WHEN** a Gene program imports `genex/ai` and calls `(new OpenAIClient opts)`
- **THEN** it receives a configured client instance (respecting opts/env precedence) whose methods cover chat, responses, embeddings, and streaming helpers

### Requirement: Configurable OpenAI-Compatible Client
Gene SHALL expose a first-class client module that targets OpenAI-style REST APIs and can be configured entirely from Gene code or environment variables.

#### Scenario: Environment + override precedence
- **WHEN** a program sets `OPENAI_API_KEY` and `OPENAI_BASE_URL` env vars and optionally supplies overrides via an opts map
- **THEN** the client uses explicit opts first, falls back to env vars second, and throws a descriptive exception if no API key is available before attempting any network call

#### Scenario: Provider compatibility toggle
- **WHEN** a caller points the client at an OpenRouter-compatible endpoint by changing only the base URL and model name
- **THEN** the request succeeds without additional code changes and the response structure matches the OpenAI schema the wrapper returns

### Requirement: Chat Completions and Responses
The client SHALL provide helpers to invoke `chat.completions` and `responses` endpoints with typed arguments plus pass-through extras for advanced options.

#### Scenario: Chat completion request
- **WHEN** a Gene program calls `(openai/chat {^model "gpt-4o" ^messages [...]})`
- **THEN** the wrapper serializes the payload to JSON, attaches auth headers, performs the HTTP POST, and returns a Gene map whose choices list mirrors the provider response

#### Scenario: Responses endpoint parity
- **WHEN** a Gene program calls `(openai/respond opts)` with tool-calling fields (passed via an `extra` map)
- **THEN** the wrapper merges built-in arguments with `extra`, preserving unknown fields so future-compatible providers operate without updates

### Requirement: Embeddings Support
The client SHALL expose an embeddings helper that accepts multiple inputs and returns typed numeric arrays ready for downstream math.

#### Scenario: Batch embeddings
- **WHEN** a Gene program submits an array of 2+ strings to `(openai/embeddings ...)`
- **THEN** the wrapper sends a single request, enforces max input length (per config), and returns an array of float arrays in the same order as provided

### Requirement: Streaming Token Delivery
The client SHALL support streaming responses via Server-Sent Events (SSE) or chunked transfer and surface tokens through Gene async primitives.

#### Scenario: Async streaming consumer
- **WHEN** a program calls `(openai/stream opts handler)`
- **THEN** the wrapper consumes the SSE stream, invokes `handler` for each delta chunk on the VM event loop, and resolves/throws when the stream completes or errors

### Requirement: Error Propagation and Observability
The client SHALL provide actionable errors and structured metadata useful for retries and analytics.

#### Scenario: HTTP failure surfacing
- **WHEN** the provider returns a non-2xx status with an error payload
- **THEN** the wrapper raises a Gene exception that includes status code, provider error type/message, request id, and redacts any secrets from logs or exception text

#### Scenario: Retry guidance metrics
- **WHEN** a request fails due to rate limits or network errors
- **THEN** the exception exposes retry-after duration (if present) and an error code (e.g., `rate_limit_exceeded` vs `network_timeout`) so callers can implement backoff logic
