## Context

Gene has existing HTTP server capabilities (genex/http.nim) and llama.cpp bindings (genex/llm.nim). This change combines them into a functional chat application to demonstrate Gene's capabilities as a backend language.

## Goals / Non-Goals

**Goals:**
- Basic chat functionality with local LLM
- Clean separation between frontend and backend
- Simple, understandable example code

**Non-Goals:**
- Production-ready deployment
- Multi-user session management
- Streaming token-by-token responses (can be added later)
- Authentication/authorization

## Decisions

### Frontend: React with Vite
- **Why**: Industry standard, fast development, familiar to most developers
- **Alternatives**: Vanilla JS (simpler but less maintainable), Vue/Svelte (less familiar)

### API Design: REST JSON
- **Why**: Simple, stateless, works with Gene's HTTP primitives
- **Alternatives**: WebSockets (better for streaming, more complex), GraphQL (overkill)

### Model Loading: On startup
- **Why**: Simpler than lazy loading, predictable memory usage
- **Alternatives**: Lazy load on first request (slower first response)

## API Specification

### POST /api/chat
Request:
```json
{
  "message": "Hello, how are you?"
}
```

Response:
```json
{
  "response": "I'm doing well, thank you for asking!",
  "tokens_used": 42
}
```

### GET /api/health
Response:
```json
{
  "status": "ok",
  "model_loaded": true
}
```

## Risks / Trade-offs

- **Memory usage**: LLM models require significant RAM; document minimum requirements
- **Response latency**: Local inference can be slow on CPU; recommend GPU for better UX
- **CORS handling**: Must be configured correctly for local development

## Migration Plan

N/A - New capability, no existing code to migrate.

## Open Questions

- Should we support multiple model backends (e.g., Ollama API as alternative)?
- Should conversation history be maintained server-side or client-side?
