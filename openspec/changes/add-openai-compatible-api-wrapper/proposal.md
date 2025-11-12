# add-openai-compatible-api-wrapper Proposal

## Why
- Gene lacks a first-class client for remote large-language-model APIs, forcing users to drop into raw HTTP mappings or external scripts when they want completions or embeddings.
- Many hosted providers (OpenAI, OpenRouter, Together, etc.) expose a near-identical REST interface; adding one well-specified wrapper would instantly unlock multiple providers.
- Examples, tutorials, and automation tooling depend on a predictable API surface so we can write portable Gene code without re-implementing signing, JSON envelopes, or streaming glue.

## What Changes
- Introduce a `genex/ai` runtime capability that exposes an `OpenAIClient` class for OpenAI-compatible endpoints (chat completions, responses, embeddings) to Gene code with a thin, ergonomic wrapper.
- Allow callers to configure API keys, base URLs, default model, and transport options (timeouts, headers) via opts map or env vars so OpenRouter-compatible services just work.
- Support both single-response and streaming token delivery; streaming should integrate with Gene async/futures so programs can `await` incremental chunks.
- Normalize responses into Gene values (maps/arrays) and bubble up HTTP/network errors as Gene exceptions with provider metadata for debugging.
- Document security considerations (key handling) plus provide examples/tests that hit a mock server to keep CI offline.

## Scope / Guardrails
- Target the OpenAI REST schema (v1) as the contract; vendor-specific extras are out of scope unless they conform to the same payload shape.
- Limit v1 to high-level resources: `chat.completions`, `responses`, `embeddings`. File uploads, fine-tuning jobs, and batch APIs are future work.
- No network credential storage beyond in-memory use; users must supply the key per process via env or explicit string.
- Keep JSON parsing/encoding within existing Nim deps (no new heavy runtime libs) and reuse the `httpclient` already used elsewhere where possible.

## Success Metrics
- `examples/openai_chat.gene` can call a mock OpenAI server and stream tokens without code changes between OpenAI and OpenRouter (only base URL changes).
- Unit tests cover: missing API key, non-200 error payload, streaming callback, embeddings request. These run offline via a recorded transcript or local mock.
- Docs explain configuration plus security tips, and `openspec validate` + lint/test suite stay green.

## Risks / Mitigations
- **Credential leakage**: Provide clear docs on env vars and avoid logging secrets; add redaction in debug logging.
- **Streaming complexity**: Build streaming atop existing async/future shim with back-pressure to prevent unbounded buffering.
- **Provider divergence**: Allow custom headers and version overrides so future protobuf/delta changes do not require code changes.
- **Network dependency**: Primary tests use mocks; end-to-end samples are opt-in manual scripts.

## Open Questions
1. Where else inside `genex/ai` should helpers live (e.g., future Anthropic-compatible clients) now that the base `OpenAIClient` location/naming is fixed?
A: deferred
2. Do we expose raw request maps for advanced fields or keep a typed wrapper? (proposal: typed wrapper for the common case plus optional `extra` map pass-through.)
A: agree
3. Where should provider-specific examples live—`examples/llm/` or `docs/guides/`? (leaning `examples/llm/` for parity with local inference work.)
A: examples/ai/
