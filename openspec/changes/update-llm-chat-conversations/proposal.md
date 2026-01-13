## Why

The chat demo is currently stateless, so each request loses prior context. Conversation-scoped endpoints enable multi-turn history and align the API with session-based chat behavior.

## What Changes

- Add conversation-scoped endpoints: POST /api/chat/new and POST /api/chat/{id}
- Store conversation history in memory and include it in prompts for each turn
- Update the frontend to start a conversation and send messages to /api/chat/{id}
- Update documentation to reflect the new endpoints

## Impact

- Affected specs: llm-chat
- Affected code:
  - example-projects/llm_app/backend/src/main.gene
  - example-projects/llm_app/frontend/src/App.jsx
  - example-projects/llm_app/frontend/src/App.css (if UI tweaks are needed)
