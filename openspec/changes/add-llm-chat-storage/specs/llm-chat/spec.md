## MODIFIED Requirements

### Requirement: LLM Chat Backend
The system SHALL persist conversation history in SQLite and restore it when a conversation is resumed.

#### Scenario: Resume conversation after restart
- **WHEN** a client sends POST /api/chat/{id} after the server restarts
- **THEN** the server loads prior messages for {id} from SQLite and includes them in the prompt context

## ADDED Requirements

### Requirement: Conversation Persistence
The system SHALL store conversations and messages in SQLite.

#### Scenario: Create conversation
- **WHEN** a client sends POST /api/chat/new
- **THEN** the server creates a conversation record and returns its id

#### Scenario: Append message
- **WHEN** a client sends POST /api/chat/{id} with a message
- **THEN** the server stores the user message and assistant response in SQLite

### Requirement: Frontend Local History
The frontend SHALL store full conversation history in local storage and restore the last conversation on load.

#### Scenario: Restore last conversation
- **WHEN** the user reloads the page
- **THEN** the UI restores the last conversation and its full message history from local storage

#### Scenario: Start new conversation
- **WHEN** the user clicks the New Conversation button
- **THEN** the UI clears the active chat and starts a new conversation with the backend
