## ADDED Requirements

### Requirement: LLM Chat Backend
The system SHALL provide HTTP endpoints for chat interactions with a locally-running LLM.

#### Scenario: Health check endpoint
- **WHEN** a GET request is made to `/api/health`
- **THEN** the server responds with JSON containing status and model_loaded fields

#### Scenario: Chat message endpoint
- **WHEN** a POST request is made to `/api/chat` with a JSON body containing a "message" field
- **THEN** the server responds with JSON containing the LLM's response

#### Scenario: CORS support
- **WHEN** a request includes Origin header from localhost
- **THEN** the server responds with appropriate CORS headers allowing the request

### Requirement: LLM Chat Frontend
The system SHALL provide a React-based web interface for interacting with the chat backend.

#### Scenario: Send message
- **WHEN** the user types a message and clicks send (or presses Enter)
- **THEN** the message is sent to the backend and the response is displayed in the chat history

#### Scenario: Display conversation history
- **WHEN** the chat interface is active
- **THEN** all messages (user and assistant) are displayed in chronological order

#### Scenario: Loading state
- **WHEN** a message is sent and awaiting response
- **THEN** a loading indicator is displayed until the response arrives

### Requirement: Model Configuration
The system SHALL allow configuration of the LLM model path via environment variable or configuration file.

#### Scenario: Model path from environment
- **WHEN** the `GENE_LLM_MODEL` environment variable is set
- **THEN** the server loads the model from that path on startup

#### Scenario: Missing model gracefully handled
- **WHEN** the configured model path does not exist
- **THEN** the server starts but reports model_loaded: false in health check
