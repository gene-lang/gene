## 1. Implementation
- [x] 1.1 Add an in-memory conversation store and prompt builder in the LLM backend
- [x] 1.2 Add POST /api/chat/new to create a conversation and return conversation_id
- [x] 1.3 Update POST /api/chat/{id} to append history, include it in prompts, and persist assistant replies
- [x] 1.4 Update the frontend to initialize a conversation and send requests to /api/chat/{id}
- [x] 1.5 Update any README/docs in example-projects/llm_app to reflect the new endpoints

## 2. Tests
- [x] 2.1 Add coverage or manual verification notes for multi-turn chat behavior
