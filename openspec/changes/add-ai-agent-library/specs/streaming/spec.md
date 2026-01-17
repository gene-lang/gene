# Streaming Support Capability

This capability provides **server-side** SSE writing for sending streaming responses to frontends (optional).
Note: Client-side SSE consumption (receiving from LLM providers) is handled by `genex/ai/streaming`.

## ADDED Requirements

### Requirement: SSE Writer
The system SHALL optionally provide Server-Sent Events (SSE) support for HTTP responses.

#### Scenario: Create SSE writer
Given an HTTP request handler context
When the user calls `(ai/streaming/sse_writer req)`
Then the system returns an SSEWriter object
And the response Content-Type is set to "text/event-stream"

#### Scenario: Write event data
Given an SSEWriter object
When the user calls `(sse .write "Hello, world!")`
Then the system writes "data: Hello, world!\n\n" to the response

#### Scenario: Write named event
Given an SSEWriter object
When the user calls `(sse .write_event "token" "Hello")`
Then the system writes "event: token\ndata: Hello\n\n" to the response

#### Scenario: Signal stream completion
Given an SSEWriter object
When the user calls `(sse .done)`
Then the system writes "data: [DONE]\n\n" to the response
And the response stream is closed

### Requirement: LLM Streaming Integration
The system SHALL optionally support streaming responses from LLM providers.

#### Scenario: Stream chat completion
Given a configured LLM client and messages
When the user calls:
```gene
(ai/stream_chat messages {
  ^on_token (fn [token] (sse .write token))
  ^on_done (fn [] (sse .done))
})
```
Then tokens are delivered incrementally via the callback
And the done callback is called when streaming completes

#### Scenario: Handle streaming errors
Given an LLM streaming request
When the stream encounters an error mid-response
Then the error callback is invoked if provided
And the stream is properly terminated

#### Scenario: Accumulate streamed content
Given a streaming response in progress
When the user uses `(ai/streaming/accumulator)`
Then the system collects all tokens into a final string
And returns the complete response when done

### Requirement: Streaming with Tool Calls
The system SHALL optionally handle tool calls in streaming responses.

#### Scenario: Detect tool call in stream
Given a streaming LLM response containing a tool call
When streaming completes
Then the system parses the accumulated tool_calls
And the on_tool_call callback is invoked with parsed ToolCall objects

#### Scenario: Stream after tool execution
Given tool results from executed tool calls
When the user continues the conversation with tool results
Then streaming can resume with the follow-up response

### Requirement: Back-pressure Handling
The system SHALL optionally handle slow consumers gracefully.

#### Scenario: Buffer tokens for slow consumer
Given a streaming response with a slow consumer
When tokens arrive faster than they can be sent
Then the system buffers tokens up to a configurable limit
And applies back-pressure to the upstream source if needed

#### Scenario: Handle client disconnect
Given an SSE stream to a client
When the client disconnects mid-stream
Then the system detects the disconnect
And cleans up resources without error
