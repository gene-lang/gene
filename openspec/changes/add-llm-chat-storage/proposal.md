## Why

The chat demo currently keeps conversations only in memory, which loses history on restart and prevents resuming conversations across sessions. Persisting history in SQLite and mirroring it in the frontend enables durable, resumable conversations and a better demo experience.

## What Changes

- Store conversations and messages in SQLite on the backend
- Load conversation history from SQLite when handling POST /api/chat/{id}
- Keep full conversation history in frontend local storage, open the last conversation on load, and add a "New Conversation" button
- Update documentation to describe persistence behavior

## Impact

- Affected specs: llm-chat
- Affected code:
  - example-projects/llm_app/backend/src/main.gene
  - example-projects/llm_app/frontend/src/App.jsx
  - example-projects/llm_app/README.md
