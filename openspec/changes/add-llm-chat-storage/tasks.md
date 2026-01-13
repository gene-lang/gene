## 1. Implementation
- [x] 1.1 Add SQLite schema creation for conversations and messages
- [x] 1.2 Persist new conversations on POST /api/chat/new
- [x] 1.3 Load history from SQLite and append messages on POST /api/chat/{id}
- [x] 1.4 Persist assistant responses and any document metadata
- [x] 1.5 Update frontend to store full history in local storage, open last conversation, and add a new conversation button
- [x] 1.6 Update docs to describe persistence and local storage behavior

## 2. Tests
- [x] 2.1 Add manual verification notes for conversation persistence across backend restarts and frontend reloads
