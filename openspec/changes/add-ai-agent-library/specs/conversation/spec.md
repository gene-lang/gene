# Conversation Management Capability

## ADDED Requirements

### Requirement: Conversation Creation
The system SHALL provide a way to create and manage conversation history.

#### Scenario: Create empty conversation
When the user calls `(ai/conversation/new)`
Then the system returns a Conversation object with empty message history

#### Scenario: Create conversation with system prompt
When the user calls `(ai/conversation/new {^system_prompt "You are a helpful assistant."})`
Then the system returns a Conversation object
And the first message is a system message with the specified prompt

### Requirement: Message Management
The system SHALL support adding and retrieving messages.

#### Scenario: Add user message
Given an existing Conversation object
When the user calls `(conv .add :user "Hello, world!")`
Then a new message with role "user" is added to the conversation

#### Scenario: Add assistant message
Given a Conversation with user messages
When the user calls `(conv .add :assistant "Hello! How can I help you?")`
Then a new message with role "assistant" is added

#### Scenario: Add tool message
Given a Conversation where assistant requested a tool call
When the user calls `(conv .add_tool_result "call_123" "Weather: 72°F sunny")`
Then a new message with role "tool" and the tool_call_id is added

#### Scenario: Get all messages
Given a Conversation with multiple messages
When the user calls `(conv .messages)`
Then the system returns all messages in order

#### Scenario: Clear conversation
Given a Conversation with messages
When the user calls `(conv .clear)`
Then all messages except the system prompt are removed

### Requirement: Context Window Management
The system SHALL manage context window limits with token-based truncation.

#### Scenario: Get context within token limit
Given a Conversation with many messages totaling 10000 tokens
When the user calls `(conv .get_context {^max_tokens 4000})`
Then the system returns messages fitting within 4000 tokens
And the system prompt is always included
And the most recent messages are prioritized

#### Scenario: Token counting
Given a Conversation with messages
When the user calls `(conv .token_count)`
Then the system returns an approximate token count for all messages

### Requirement: OpenAI Format Conversion
The system SHALL convert conversations to OpenAI API message format.

#### Scenario: Convert to OpenAI messages
Given a Conversation with system, user, and assistant messages
When the user calls `(conv .to_openai_format)`
Then the system returns a list of maps with "role" and "content" keys
And the format is compatible with OpenAI chat completion API

### Requirement: Conversation Persistence (Optional)
The system SHALL optionally persist conversations to files.

#### Scenario: Save conversation to file
Given a Conversation with messages
When the user calls `(conv .save "conversation.json")`
Then the conversation is serialized and saved to the file

#### Scenario: Load conversation from file
Given a saved conversation file "conversation.json"
When the user calls `(ai/conversation/load "conversation.json")`
Then the system returns a Conversation with the saved messages
