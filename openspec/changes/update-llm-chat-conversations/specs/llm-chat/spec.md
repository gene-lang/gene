## MODIFIED Requirements

### Requirement: LLM Chat Backend
The system SHALL provide conversation-scoped chat endpoints.

#### Scenario: Start a conversation
- **WHEN** a client sends POST /api/chat/new
- **THEN** the server responds with JSON containing a conversation_id string

#### Scenario: Send chat message with conversation id
- **WHEN** a client sends POST /api/chat/{id} with a JSON body containing a "message" field
- **THEN** the server responds with JSON containing the assistant response and the same conversation_id

#### Scenario: Send document message with conversation id
- **WHEN** a client sends POST /api/chat/{id} with multipart/form-data containing a file
- **THEN** the server responds with JSON containing the assistant response and document metadata

## ADDED Requirements

### Requirement: Conversation History Context
The system SHALL store conversation history in memory and include prior user and assistant messages in prompt context for each new turn.

#### Scenario: Multi-turn context
- **WHEN** a second message is sent to the same conversation id
- **THEN** the prompt includes earlier user and assistant messages in chronological order
