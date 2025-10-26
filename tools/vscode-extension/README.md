# Gene Language Support for VS Code

This extension provides language support for the Gene programming language in Visual Studio Code.

## Features

- Syntax highlighting for `.gene` files
- Language Server Protocol (LSP) integration
- Basic language configuration (brackets, comments, etc.)

## Requirements

- Gene language runtime with LSP server support
- The `gene` command must be available in your PATH

## Installation

1. Install the Gene language runtime
2. Build the Gene LSP server: `nimble build`
3. Install this VS Code extension
4. Open a `.gene` file to activate language support

## Configuration

The extension can be configured through VS Code settings:

- `gene.lsp.enabled`: Enable/disable the Language Server (default: true)
- `gene.lsp.port`: LSP server port (default: 8080)
- `gene.lsp.host`: LSP server host (default: localhost)
- `gene.lsp.trace`: Enable LSP tracing for debugging (default: false)

## Usage

1. Create a file with `.gene` extension
2. The extension will automatically start the Gene LSP server
3. Enjoy syntax highlighting and language features

## Development

This extension is part of the Gene language project. To contribute:

1. Clone the Gene repository
2. Navigate to `tools/vscode-extension/`
3. Run `npm install` to install dependencies
4. Open in VS Code and press F5 to launch extension development host

## Known Issues

- Language analysis features are currently in development
- Some LSP features may return placeholder responses

## Release Notes

### 0.1.0

- Initial release
- Basic syntax highlighting
- LSP server integration
- Language configuration

## More Information

- [Gene Language Documentation](https://github.com/gcao/gene)
- [Language Server Protocol](https://microsoft.github.io/language-server-protocol/)
