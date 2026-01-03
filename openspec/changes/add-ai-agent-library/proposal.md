# add-ai-agent-library Proposal

## Why
- Gene has basic LLM capabilities (local inference via `genex/llm`, OpenAI-compatible API via `genex/ai`) but lacks the higher-level primitives needed to build production AI agents.
- Modern AI applications require: document processing (PDF/images), vector storage for retrieval-augmented generation (RAG), conversation management, tool/function calling, and streaming responses.
- Without these capabilities, Gene users must cobble together external tools or write significant boilerplate, limiting Gene's appeal for AI-first applications.
- A unified AI agent library would position Gene as a compelling choice for building ChatGPT-like applications with a clean, Lisp-inspired API.

## What Changes
Introduce a comprehensive `genex/ai` module that provides:

### 1. Document Processing (`genex/ai/documents`)
- PDF text extraction using external tools or APIs (no internal parser)
- Image OCR support via external tools or APIs
- Text chunking with configurable strategies (fixed-size, sentence-based, semantic)
- Metadata extraction and document fingerprinting

### 2. Vector Database Client (`genex/ai/vectordb`)
- Qdrant REST API client as the primary implementation
- Operations: create collection, upsert vectors, search, delete
- Configurable embedding dimensions and distance metrics
- Connection pooling and retry logic
- Abstract interface to allow future backends (Pinecone, Weaviate)

### 3. Conversation Management (`genex/ai/conversation`)
- Message history storage with role tracking (system, user, assistant, tool)
- Context window management with token counting
- Conversation persistence (in-memory and optional file/DB backends)
- Message templating for system prompts

### 4. Tool/Function Calling (`genex/ai/tools`)
- Tool registry for Gene functions with JSON schema generation
- Automatic tool response parsing and execution
- Error handling and retry logic for tool failures
- Integration with OpenAI/Anthropic function calling formats

### 5. Streaming Support (Optional) (`genex/ai/streaming`)
- Server-Sent Events (SSE) support for HTTP responses
- Incremental token delivery to frontends
- Back-pressure handling and buffering
- Integration with existing `genex/http` server

### 6. RAG Pipeline (`genex/ai/rag`)
- High-level API combining documents + embeddings + vector search
- Query expansion and re-ranking options
- Source attribution in responses
- Configurable retrieval strategies

## Scope / Guardrails
- **Qdrant first**: Target Qdrant as the primary vector DB; abstract interface allows future backends but don't over-engineer.
- **External extraction only**: PDF parsing and OCR MUST rely on external tools or APIs (no internal parsing).
- **Reuse existing modules**: Build on `genex/ai` for embeddings, `genex/http` for server support, `genex/llm` for local inference.
- **No credential storage**: API keys and connection strings come from env vars or explicit config; no persistence of secrets.
- **Offline testing**: All tests use mocks or recorded responses; no network calls in CI.

## Success Metrics
- Example `examples/ai/rag_agent.gene` demonstrates: upload PDF → chunk → embed → store in Qdrant → query with RAG → stream response to frontend (if streaming is implemented).
- Example `examples/ai/tool_agent.gene` shows function calling with a calculator tool and weather lookup mock.
- Test coverage for: document chunking, vector operations, conversation windowing, tool execution, SSE streaming (if implemented).
- Documentation covers security best practices (key handling, input validation).
- `openspec validate add-ai-agent-library --strict` passes.

## Risks / Mitigations
- **External tool/API dependencies**: Document requirements clearly; provide fallback error messages when tools or APIs are missing.
- **Qdrant version drift**: Pin to a stable Qdrant REST API version; use OpenAPI spec for client generation if available.
- **Streaming complexity**: Build on existing async shim; limit buffer sizes to prevent memory issues.
- **Scope creep**: Strict adherence to v1 scope; advanced features (agents with memory, multi-agent systems) are future work.
- **Token counting accuracy**: Use tiktoken or approximation; document limitations for non-OpenAI models.

## Dependencies
- Existing: `genex/ai` (OpenAI client, embeddings), `genex/http` (HTTP server), `genex/llm` (local inference)
- External tools/APIs: configurable PDF and OCR extractors (CLI or API)
- Network: Qdrant server (self-hosted or cloud)

**Note**: This proposal depends on `add-openai-compatible-api-wrapper` being completed first, as it provides the embeddings API via `genex/ai`. If that change is not ready, embeddings can be mocked for initial development.

## Technical Constraints
- **Token counting**: Use word-based approximation (words / 0.75 ≈ tokens) rather than tiktoken, which is Python-only. Document limitations for non-English text.

## Open Questions
1. Should we bundle a lightweight embedding model for offline use, or always require an external embedding API?
   A: Start with external API only; local embeddings can be a future enhancement.

2. How should conversation persistence work across process restarts?
   A: In-memory by default; optional file-based persistence as an extension.

3. Should tool definitions be auto-generated from Gene function signatures or manually specified?
   A: Manual JSON schema specification initially; auto-generation is a nice-to-have for v2.
