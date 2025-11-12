## 1. Spec & API Surface
- [ ] 1.1 Document supported OpenAI-compatible endpoints (chat completions, responses, embeddings) and required fields for each request/response in the spec delta.
- [ ] 1.2 Define configuration contract (API key precedence, base URL overrides, default model hierarchy, custom headers) and streaming semantics.

## 2. Runtime Implementation
- [ ] 2.1 Implement Nim HTTP client wrapper that signs requests, injects headers, and exposes sync + streaming helpers with structured errors.
- [ ] 2.2 Add Gene stdlib bindings (e.g., `(openai/chat ...)`, `(openai/stream ...)`, `(openai/embeddings ...)`) plus async integration for streaming chunks.
- [ ] 2.3 Provide configuration helpers/env var loader and ensure secrets are redacted from logs and exceptions.

## 3. Testing, Tooling, and Docs
- [ ] 3.1 Build a mock OpenAI-compatible server / fixture so tests can run offline covering success + failure cases.
- [ ] 3.2 Add Gene examples (chat + embeddings) demonstrating provider swap via base URL.
- [ ] 3.3 Document setup instructions, security considerations, and troubleshooting in `docs/llm/openai.md` (or similar) and link from README.
