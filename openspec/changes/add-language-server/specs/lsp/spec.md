# LSP Capability Specification

## Implementation Status

### Phase 1: Core Infrastructure (COMPLETED)
- ✅ LSP server module (`src/gene/lsp/server.nim`)
- ✅ LSP protocol types (`src/gene/lsp/types.nim`)
- ✅ CLI integration (`src/commands/lsp.nim`)
- ✅ JSON-RPC message handling
- ✅ Server lifecycle (initialize, shutdown)
- ✅ Document synchronization (open, close, change)
- ✅ Basic capability negotiation

### Phase 2: Language Analysis (COMPLETED)
- ✅ Gene parser integration with position tracking
- ✅ Symbol extraction with accurate line/column positions
- ✅ Code completion with keywords and symbols
- ✅ Error diagnostics (parse errors in real-time)
- ✅ Position-aware hover information
- ✅ Go-to-definition navigation
- ⚠️ Incremental parsing (full reparse on changes)

### Phase 3: Advanced Features (PLANNED)
- ❌ Code completion with context awareness
- ❌ Go to definition
- ❌ Find references
- ❌ Hover information
- ❌ Workspace symbols
- ❌ Document formatting

## ADDED Requirements

### Requirement: LSP Protocol Implementation
Gene SHALL implement a Language Server Protocol (LSP) server that provides standard language services to LSP-compatible clients.

#### Scenario: LSP server initialization
- **WHEN** client connects to Gene LSP server
- **THEN** server SHALL respond to `initialize` request with capabilities
- **AND** server SHALL negotiate supported features with client
- **AND** server SHALL establish communication channel for JSON-RPC messages

#### Scenario: Workspace management
- **WHEN** client opens a folder containing Gene files
- **THEN** server SHALL discover and monitor Gene files (.gene)
- **AND** server SHALL send workspace notifications for file changes
- **AND** server SHALL maintain symbol index across all workspace files

### Requirement: Real-time Syntax Analysis
The LSP server SHALL provide real-time syntax checking and error detection for Gene code.

#### Scenario: Incremental parsing
- **WHEN** user edits a Gene file in editor
- **THEN** server SHALL parse only affected portions of the document
- **AND** server SHALL update syntax tree incrementally
- **AND** server SHALL send diagnostic updates for syntax errors
- **AND** updates SHALL be sent within 100ms of user action

#### Scenario: Error detection and reporting
- **WHEN** Gene code contains syntax errors or type mismatches
- **THEN** server SHALL detect errors using existing compiler integration
- **AND** server SHALL send `textDocument/publishDiagnostics` notifications
- **AND** diagnostics SHALL include error location, severity, and message
- **AND** diagnostics SHALL be accurate and actionable

### Requirement: Code Completion
The LSP server SHALL provide intelligent code completion for Gene expressions and symbols.

#### Scenario: Context-aware completion
- **WHEN** user requests completion at a specific position
- **THEN** server SHALL analyze current scope and imports
- **AND** server SHALL suggest relevant functions, variables, and keywords
- **AND** suggestions SHALL be filtered by accessibility and scope
- **AND** server SHALL prioritize frequently used symbols

#### Scenario: Completion ranking and filtering
- **WHEN** multiple completion items are available
- **THEN** server SHALL rank items by relevance and usage frequency
- **AND** server SHALL filter by prefix matching and context
- **AND** server SHALL provide completion item types (function, variable, keyword)
- **AND** response time SHALL be under 50ms for typical completions

### Requirement: Navigation and Symbol Resolution
The LSP server SHALL provide navigation features for Gene codebases.

#### Scenario: Go to definition
- **WHEN** user requests definition of a symbol
- **THEN** server SHALL locate the symbol definition in workspace
- **AND** server SHALL return file location and position
- **AND** server SHALL handle definitions across multiple files
- **AND** server SHALL resolve namespaced and imported symbols

#### Scenario: Find all references
- **WHEN** user requests all references to a symbol
- **THEN** server SHALL search workspace for all symbol occurrences
- **AND** server SHALL return list of locations with context
- **AND** server SHALL include both definitions and usages
- **AND** server SHALL handle symbols in nested scopes and modules

### Requirement: Type Information and Hover
The LSP server SHALL provide type information and documentation on demand.

#### Scenario: Hover information
- **WHEN** user hovers over a Gene expression
- **THEN** server SHALL analyze the expression's type and meaning
- **AND** server SHALL return formatted type information
- **AND** server SHALL include available documentation from comments
- **AND** response SHALL include function signatures for callable items

#### Scenario: Type analysis integration
- **WHEN** analyzing Gene expressions with types
- **THEN** server SHALL integrate with existing Gene compiler
- **AND** server SHALL extract type information from compiler analysis
- **AND** server SHALL provide type inference results
- **AND** server SHALL validate type correctness incrementally

### Requirement: Code Formatting
The LSP server SHALL provide automatic formatting for Gene S-expressions.

#### Scenario: Document formatting
- **WHEN** user requests format of entire document
- **THEN** server SHALL format Gene code according to style rules
- **AND** server SHALL normalize S-expression indentation and spacing
- **AND** server SHALL preserve comments and logical structure
- **AND** server SHALL handle edge cases and malformed input gracefully

#### Scenario: Range formatting
- **WHEN** user requests format of selected code region
- **THEN** server SHALL format only the selected S-expressions
- **AND** server SHALL maintain syntactic validity of selection
- **AND** server SHALL handle partial expressions correctly
- **AND** server SHALL preserve surrounding context when needed

### Requirement: Project Symbols and Outline
The LSP server SHALL provide project-wide symbol information for navigation and overview.

#### Scenario: Workspace symbols
- **WHEN** client requests workspace symbol list
- **THEN** server SHALL return all symbols in project
- **AND** symbols SHALL be categorized (functions, variables, modules)
- **AND** symbols SHALL include file locations and signatures
- **AND** server SHALL support symbol search and filtering

#### Scenario: Document symbols
- **WHEN** client requests outline of current document
- **THEN** server SHALL return symbols defined in current file
- **AND** server SHALL include nested structure and hierarchy
- **AND** server SHALL provide symbol types and visibility
- **AND** server SHALL support incremental updates as document changes

### Requirement: Performance and Scalability
The LSP server SHALL maintain performance characteristics suitable for interactive development.

#### Scenario: Large project handling
- **WHEN** workspace contains 1000+ Gene files
- **THEN** server SHALL initialize within 5 seconds
- **AND** server SHALL maintain response times under 100ms for basic operations
- **AND** memory usage SHALL stay below 100MB for typical projects
- **AND** server SHALL handle concurrent requests efficiently

#### Scenario: Incremental updates
- **WHEN** files change during editing session
- **THEN** server SHALL process only changed portions
- **AND** server SHALL update symbol index incrementally
- **AND** server SHALL avoid full re-analysis when possible
- **AND** server SHALL maintain responsiveness during updates

### Requirement: Error Handling and Robustness
The LSP server SHALL handle errors gracefully and maintain stable operation.

#### Scenario: Protocol errors
- **WHEN** client sends invalid LSP request
- **THEN** server SHALL return appropriate error response
- **AND** server SHALL include error details and suggestions
- **AND** server SHALL continue operating for other requests
- **AND** server SHALL log errors for debugging

#### Scenario: Invalid Gene code
- **WHEN** parsing Gene code with syntax errors
- **THEN** server SHALL handle errors gracefully without crashing
- **AND** server SHALL provide error location and diagnostic information
- **AND** server SHALL attempt recovery and partial analysis
- **AND** server SHALL continue processing other requests

### Requirement: Integration Compatibility
The LSP server SHALL integrate seamlessly with existing Gene development workflow.

#### Scenario: Coexistence with Gene CLI
- **WHEN** LSP server is running alongside Gene CLI tools
- **THEN** CLI tools SHALL continue to function normally
- **AND** LSP server SHALL not interfere with CLI operations
- **AND** both SHALL access same files safely
- **AND** users SHALL choose between CLI and LSP workflows

#### Scenario: Multiple client support
- **WHEN** multiple editors connect to LSP server
- **THEN** server SHALL handle each client independently
- **AND** server SHALL maintain separate workspace states per client
- **AND** server SHALL support concurrent editing sessions
- **AND** server SHALL provide consistent behavior across clients

### Requirement: Configuration and Customization
The LSP server SHALL provide configuration options to adapt to user preferences.

#### Scenario: Formatting configuration
- **WHEN** user specifies custom formatting preferences
- **THEN** server SHALL apply user-defined style rules
- **AND** server SHALL support different indentation styles
- **AND** server SHALL allow configuration per workspace or project
- **AND** server SHALL validate configuration and provide defaults

#### Scenario: Feature enablement
- **WHEN** certain LSP features are resource-intensive
- **THEN** server SHALL allow disabling specific features
- **AND** server SHALL provide capability negotiation
- **AND** server SHALL adapt to client capabilities
- **AND** server SHALL maintain performance with disabled features