import parseopt, asyncdispatch, strutils
import ./base
import ../gene/lsp/server

const DEFAULT_COMMAND = "lsp"
const COMMANDS = @[DEFAULT_COMMAND]

type
  LspOptions = ref object
    port: int
    host: string
    workspace: string
    trace: bool
    stdio: bool
    help: bool

proc handle*(cmd: string, args: seq[string]): CommandResult

proc init*(manager: CommandManager) =
  manager.register(COMMANDS, handle)
  manager.add_help("lsp: Start Language Server Protocol server")

let short_no_val = {'t', 's', 'h'}
let long_no_val = @["trace", "stdio", "help"]

proc parse_options(args: seq[string]): LspOptions =
  result = LspOptions(
    port: 8080,
    host: "localhost",
    workspace: "",
    trace: false,
    stdio: false,
    help: false
  )

  for kind, key, value in get_opt(args, short_no_val, long_no_val):
    case kind
    of cmdArgument:
      discard  # LSP doesn't take positional arguments
    of cmdLongOption, cmdShortOption:
      case key
      of "p", "port":
        try:
          result.port = parseInt(value)
        except ValueError:
          echo "Error: Invalid port number: ", value
          quit(1)
      of "host":
        result.host = value
      of "w", "workspace":
        result.workspace = value
      of "t", "trace":
        result.trace = true
      of "s", "stdio":
        result.stdio = true
      of "h", "help":
        result.help = true
      else:
        echo "Unknown option: ", key
        quit(1)
    of cmdEnd:
      discard

proc run_lsp_server(options: LspOptions): CommandResult =
  try:
    # Create LSP configuration
    let config = LspConfig(
      port: options.port,
      host: options.host,
      workspace: options.workspace,
      trace: options.trace,
      stdio: options.stdio
    )

    if options.stdio:
      # Stdio mode for VS Code integration
      start_lsp_stdio_server(config)
    else:
      # TCP server mode
      echo "Starting Gene LSP server..."
      echo "Port: ", options.port
      echo "Host: ", options.host
      if options.workspace.len > 0:
        echo "Workspace: ", options.workspace
      echo "Trace: ", options.trace
      echo ""
      echo "To stop the server, press Ctrl+C"
      echo ""
      waitFor start_lsp_server(config)

    return success("LSP server terminated normally")

  except CatchableError as e:
    return failure("Failed to start LSP server: " & e.msg)

proc handle*(cmd: string, args: seq[string]): CommandResult =
  let options = parse_options(args)

  if options.help:
    return success("""Gene Language Server Protocol (LSP) Server

Usage: gene lsp [options]

Options:
  -s, --stdio           Use stdio for LSP communication (for VS Code)
  -p, --port <port>     Server port for TCP mode (default: 8080)
  --host <host>         Server host for TCP mode (default: localhost)
  -w, --workspace <dir> Workspace directory
  -t, --trace           Enable request tracing (logs to stderr in stdio mode)
  -h, --help            Show this help message

The LSP server provides language services for Gene code including:
- Syntax highlighting (via TextMate grammar in VS Code extension)
- Error checking and diagnostics
- Code completion
- Go to definition
- Hover information
- Symbol search

For VS Code, the extension automatically uses --stdio mode.
For other editors, connect to localhost:8080 (or specified host:port).
""")

  case cmd:
  of "lsp":
    return run_lsp_server(options)
  else:
    return failure("Unknown command: " & cmd)
