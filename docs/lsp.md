# Gene Language Server Protocol (LSP) Implementation

## Overview

Gene now includes a Language Server Protocol (LSP) implementation that provides modern IDE features for Gene code. The LSP server is integrated directly into the `gene` CLI and enables syntax highlighting, error checking, code completion, and other language services in any LSP-compatible editor.

**Current Status**: Phase 1 (Core Infrastructure) is complete. The server handles LSP protocol messages and document lifecycle, but language analysis features are currently stub implementations.

## Features

### Phase 1: Core Infrastructure ✅ COMPLETED
- ✅ **LSP Protocol Compliance**: Full JSON-RPC message handling
- ✅ **Server Lifecycle**: Initialize, shutdown, and capability negotiation
- ✅ **Document Synchronization**: Open, close, and change notifications
- ✅ **CLI Integration**: `gene lsp` command with configuration options
- ✅ **Async I/O**: Non-blocking request handling with TCP sockets
- ✅ **Capability Negotiation**: Server advertises supported features to clients

### Phase 2: Language Analysis ⚠️ IN PROGRESS
- ⚠️ **Stub Handlers**: Completion, definition, hover, and workspace symbol handlers (return placeholder responses)
- ❌ **Gene Parser Integration**: Connect to existing parser for syntax analysis
- ❌ **Symbol Resolution**: Build symbol tables and scope tracking
- ❌ **Error Diagnostics**: Real-time syntax and type error detection
- ❌ **Incremental Parsing**: Efficient re-parsing of changed documents

### Phase 3: Advanced Features 📋 PLANNED
- ❌ **Code Completion**: Context-aware symbol completion with ranking
- ❌ **Go to Definition**: Navigate to symbol definitions across files
- ❌ **Find References**: Locate all symbol usages in workspace
- ❌ **Hover Information**: Display type information and documentation
- ❌ **Workspace Symbols**: Project-wide symbol search
- ❌ **Document Formatting**: Automatic S-expression formatting
- ❌ **Rename Symbol**: Safe refactoring with scope awareness

## Usage

### Starting the LSP Server

```bash
# Start with default settings (localhost:8080)
gene lsp

# Start with custom port and tracing
gene lsp --port 9000 --trace

# Start with workspace directory
gene lsp --workspace /path/to/project --trace

# Show help
gene lsp --help
```

### Command Line Options

- `-p, --port <port>`: Server port (default: 8080)
- `-h, --host <host>`: Server host (default: localhost)
- `-w, --workspace <dir>`: Workspace directory
- `-t, --trace`: Enable request tracing for debugging
- `--help`: Show help message

### Building

```bash
# Build the main Gene CLI (includes LSP server)
nimble build
```

The LSP server is integrated directly into the `gene` CLI, so no separate build step is needed.

## Editor Integration

### VS Code

To use the Gene LSP server with VS Code, you can create a simple client configuration:

1. Install the "Generic LSP Client" extension
2. Configure it to connect to `localhost:8080`
3. Associate `.gene` files with the LSP client

Example VS Code settings.json:
```json
{
  "genericLspClient.languageServers": [
    {
      "name": "Gene",
      "command": ["gene", "lsp"],
      "languageId": "gene",
      "fileExtensions": [".gene"]
    }
  ]
}
```

### Other Editors

The LSP server works with any LSP-compatible editor:

- **Emacs**: Use `lsp-mode` with custom server configuration
- **Vim/Neovim**: Use `vim-lsp` or `nvim-lspconfig`
- **Sublime Text**: Use LSP package
- **IntelliJ**: Use LSP Support plugin

## Architecture

### Components

1. **LSP Server** (`src/gene/lsp/server.nim`): Main server implementation
2. **LSP Types** (`src/gene/lsp/types.nim`): Protocol data structures
3. **LSP Command** (`src/commands/lsp.nim`): CLI integration

### Protocol Implementation

The server implements the LSP specification using:
- **JSON-RPC 2.0**: Message protocol
- **TCP Sockets**: Communication transport
- **Async I/O**: Non-blocking request handling

### Message Flow

1. Client connects to server socket
2. Client sends `initialize` request with capabilities
3. Server responds with supported features
4. Client sends document lifecycle notifications
5. Client requests language services (completion, hover, etc.)
6. Server processes requests and returns responses

## Development

### Current Implementation

**Phase 1 (Core Infrastructure)** is complete and functional:

```
gene lsp
  ↓
src/commands/lsp.nim (CLI integration)
  ↓
src/gene/lsp/server.nim (LSP server implementation)
  ↓
src/gene/lsp/types.nim (Protocol data structures)
```

**What Works:**
- ✅ Server starts and listens on configurable port/host
- ✅ Handles LSP initialize/shutdown lifecycle
- ✅ Processes document open/close/change notifications
- ✅ Responds to completion/definition/hover requests (with placeholder data)
- ✅ Integrated into main `gene` CLI (no separate binary needed)

**What's Next:**
- Connect Gene parser for actual syntax analysis
- Build symbol table from parsed AST
- Implement real completion based on scope
- Add error diagnostics from compiler
- Implement go-to-definition using symbol resolution

### Next Steps

1. **Parser Integration**: Connect Gene parser for syntax analysis
2. **Symbol Analysis**: Implement symbol table and scope resolution
3. **Diagnostics**: Add real-time error detection
4. **Completion**: Implement context-aware code completion
5. **Navigation**: Add go-to-definition and find-references
6. **VS Code Extension**: Create official Gene extension

### Testing

```bash
# Test LSP server compilation
nim check src/gene.nim

# Test CLI integration
./bin/gene lsp --help

# Test server startup
./bin/gene lsp --trace
```

## Troubleshooting

### Common Issues

1. **Port Already in Use**: Change port with `--port` option
2. **Connection Refused**: Ensure server is running and port is correct
3. **No Language Features**: Current implementation has stub handlers only

### Debug Mode

Enable tracing to see LSP message flow:
```bash
gene lsp --trace
```

This will log all incoming LSP requests and responses to the console.

## Contributing

The LSP implementation follows the existing Gene codebase patterns:

1. **Protocol Handling**: Add new LSP methods to `gene/lsp/server.nim`
2. **Type Definitions**: Extend `gene/lsp/types.nim` for new data structures
3. **Language Analysis**: Integrate with existing parser and compiler modules
4. **Testing**: Add tests for new LSP features

See the [LSP specification](https://microsoft.github.io/language-server-protocol/) for protocol details.
