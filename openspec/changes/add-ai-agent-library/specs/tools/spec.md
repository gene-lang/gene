# Tool/Function Calling Capability

## ADDED Requirements

### Requirement: Tool Registry
The system SHALL provide a registry for defining and managing tools.

#### Scenario: Create tool registry
When the user calls `(ai/tools/registry)`
Then the system returns an empty ToolRegistry object

#### Scenario: Register a tool
Given a ToolRegistry object
When the user calls:
```gene
(registry .register {
  ^name "get_weather"
  ^description "Get current weather for a location"
  ^parameters [
    {^name "location" ^type "string" ^required true}
  ]
  ^handler (fn [args] {^temp 72 ^condition "sunny"})
})
```
Then the tool is registered and available for execution

#### Scenario: List registered tools
Given a registry with multiple registered tools
When the user calls `(registry .list)`
Then the system returns a list of tool names

### Requirement: Tool Definition Schema
The system SHALL validate tool definitions and generate JSON schemas.

#### Scenario: Define tool with parameters
Given a tool definition with name, description, and parameters
When the tool is registered
Then each parameter must have name and type
And required parameters are validated

#### Scenario: Generate OpenAI tools format
Given a registry with registered tools
When the user calls `(registry .to_openai_format)`
Then the system returns a list of tool definitions in OpenAI function calling format
And each tool has "type": "function" and proper schema

### Requirement: Tool Execution
The system SHALL execute registered tools with provided arguments.

#### Scenario: Execute tool with valid arguments
Given a registered tool "get_weather" expecting a "location" parameter
When the user calls `(registry .execute "get_weather" {^location "San Francisco"})`
Then the tool handler is invoked with the arguments
And the handler's return value is returned

#### Scenario: Handle missing required argument
Given a tool requiring a "location" parameter
When the user calls `(registry .execute "get_weather" {})`
Then the system raises an exception indicating the missing required parameter

#### Scenario: Handle unknown tool
When the user calls `(registry .execute "unknown_tool" {})`
Then the system raises an exception indicating the tool is not registered

#### Scenario: Handle tool execution error
Given a tool handler that raises an exception
When the tool is executed
Then the exception is caught and formatted as a tool error result

### Requirement: LLM Tool Call Integration
The system SHALL parse and execute tool calls from LLM responses.

#### Scenario: Parse tool calls from assistant message
Given an assistant message containing tool_calls
When the user calls `(ai/tools/parse_tool_calls message)`
Then the system returns a list of ToolCall objects with id, name, and arguments

#### Scenario: Execute multiple tool calls
Given multiple tool calls from an LLM response
When the user calls `(registry .execute_all tool_calls)`
Then each tool is executed in sequence
And a list of tool results is returned

#### Scenario: Format tool results for follow-up
Given tool execution results
When the user calls `(ai/tools/format_results results)`
Then the system returns messages suitable for sending back to the LLM
