## Gene Language Server Protocol (LSP) Server Implementation

import asyncdispatch, json, strutils, net, asyncnet, tables, os, sequtils
import ../types
import ./types, ./document

# LSP Server Configuration
type
  LspConfig* = ref object
    port*: int
    host*: string
    workspace*: string
    trace*: bool

  LspServer* = ref object
    socket*: AsyncSocket
    config*: LspConfig
    state*: LspState
    clients*: seq[AsyncSocket]  # Connected clients

var lsp_config*: LspConfig
var lsp_server*: LspServer

# Helper functions for LSP responses
proc newNotification*(methodName: string, params: JsonNode): string =
  let notification = %*{
    "jsonrpc": "2.0",
    "method": methodName,
    "params": params
  }
  return $notification

# Helper to send notification to all clients
proc sendNotificationToClients*(notification: string) {.async.} =
  if lsp_server != nil and lsp_server.clients.len > 0:
    for client in lsp_server.clients:
      try:
        await client.send(notification & "\r\n")
      except:
        discard  # Client disconnected

# Helper to send diagnostics for a document
proc sendDiagnostics*(uri: string, diagnostics: seq[Diagnostic]) {.async.} =
  var diagArray = newJArray()
  for diag in diagnostics:
    diagArray.add(toJson(diag))

  let params = %*{
    "uri": uri,
    "diagnostics": diagArray
  }

  let notification = newNotification("textDocument/publishDiagnostics", params)
  await sendNotificationToClients(notification)
proc newResponse*(id: JsonNode, resultData: JsonNode): string =
  let response = %*{
    "jsonrpc": "2.0",
    "id": id,
    "result": resultData
  }
  return $response

proc newErrorResponse*(id: JsonNode, code: int, message: string): string =
  let response = %*{
    "jsonrpc": "2.0",
    "id": id,
    "error": %*{
      "code": code,
      "message": message
    }
  }
  return $response

# Basic LSP Request Handlers
proc handle_initialize*(id: JsonNode, params: JsonNode): Future[string] {.async.} =
  try:
    # Extract client capabilities
    let client_info = params.getOrDefault("clientInfo")
    let client_name = if client_info != nil: client_info.getOrDefault("name").getStr("Unknown") else: "Unknown"

    # Define server capabilities
    let capabilities = %*{
      "textDocumentSync": %*{
        "openClose": true,
        "change": %*1  # Full document sync
      },
      "completionProvider": %*{
        "resolveProvider": true,
        "triggerCharacters": @[":", "(", "["]
      },
      "definitionProvider": true,
      "hoverProvider": true,
      "workspaceSymbolProvider": true
    }

    let resultData = %*{
      "capabilities": capabilities,
      "serverInfo": %*{
        "name": "gene-lsp",
        "version": "0.1.0",
        "geneVersion": "1.0.0"  # TODO: Get from gene version
      }
    }

    if lsp_config.trace:
      echo "LSP Initialized with client: ", client_name

    return newResponse(id, resultData)

  except CatchableError as e:
    return newErrorResponse(id, -32603, "Initialization failed: " & e.msg)

proc handle_shutdown*(id: JsonNode, params: JsonNode): Future[string] {.async.} =
  if lsp_config.trace:
    echo "LSP Shutdown requested"

  return newResponse(id, newJNull())

proc handle_text_document_did_open*(id: JsonNode, params: JsonNode): Future[string] {.async.} =
  try:
    let text_doc = params["textDocument"]
    let uri = text_doc["uri"].getStr()
    let content = text_doc["text"].getStr()
    let version = text_doc.getOrDefault("version").getInt(0)

    if lsp_config.trace:
      echo "LSP Document opened: ", uri, " (version ", version, ")"

    # Parse the document and cache it
    let doc = updateDocument(uri, content, version)

    if lsp_config.trace:
      echo "  Parsed ", doc.ast.len, " top-level forms"
      if doc.diagnostics.len > 0:
        echo "  Found ", doc.diagnostics.len, " diagnostics"

    # Send diagnostics to client
    await sendDiagnostics(uri, doc.diagnostics)

    return newResponse(id, newJNull())

  except CatchableError as e:
    return newErrorResponse(id, -32603, "Document open failed: " & e.msg)

proc handle_text_document_did_close*(id: JsonNode, params: JsonNode): Future[string] {.async.} =
  try:
    let text_doc = params["textDocument"]
    let uri = text_doc["uri"].getStr()

    if lsp_config.trace:
      echo "LSP Document closed: ", uri

    # Remove document from cache
    removeDocument(uri)

    return newResponse(id, newJNull())

  except CatchableError as e:
    return newErrorResponse(id, -32603, "Document close failed: " & e.msg)

proc handle_text_document_did_change*(id: JsonNode, params: JsonNode): Future[string] {.async.} =
  try:
    let text_doc = params["textDocument"]
    let uri = text_doc["uri"].getStr()
    let version = text_doc.getOrDefault("version").getInt(0)
    let content_changes = params["contentChanges"]

    if lsp_config.trace:
      echo "LSP Document changed: ", uri, " (version ", version, "), changes: ", content_changes.len

    # For full document sync (change = 1), we get the full text
    if content_changes.len > 0:
      let change = content_changes[0]
      if change.hasKey("text"):
        let new_content = change["text"].getStr()

        # Reparse the document
        let doc = updateDocument(uri, new_content, version)

        if lsp_config.trace:
          echo "  Reparsed ", doc.ast.len, " top-level forms"
          if doc.diagnostics.len > 0:
            echo "  Found ", doc.diagnostics.len, " diagnostics"

        # Send updated diagnostics
        await sendDiagnostics(uri, doc.diagnostics)

    return newResponse(id, newJNull())

  except CatchableError as e:
    return newErrorResponse(id, -32603, "Document change failed: " & e.msg)

proc handle_text_document_completion*(id: JsonNode, params: JsonNode): Future[string] {.async.} =
  try:
    let text_doc = params["textDocument"]
    let position = params["position"]
    let uri = text_doc["uri"].getStr()
    let line = position["line"].getInt()
    let character = position["character"].getInt()

    if lsp_config.trace:
      echo "LSP Completion requested for: ", uri, " at ", line, ":", character

    # Get completions from document parser
    let completions = getCompletionsAtPosition(uri, line, character)

    # Convert to LSP completion items
    var items = newJArray()
    for comp in completions:
      items.add(%*{
        "label": comp.label,
        "kind": comp.kind.int,
        "detail": comp.detail,
        "documentation": comp.documentation
      })

    let resultData = %*{
      "isIncomplete": false,
      "items": items
    }

    return newResponse(id, resultData)

  except CatchableError as e:
    return newErrorResponse(id, -32603, "Completion failed: " & e.msg)

proc handle_text_document_definition*(id: JsonNode, params: JsonNode): Future[string] {.async.} =
  try:
    let text_doc = params["textDocument"]
    let position = params["position"]
    let uri = text_doc["uri"].getStr()
    let line = position["line"].getInt()
    let character = position["character"].getInt()

    if lsp_config.trace:
      echo "LSP Definition requested for: ", uri, " at ", line, ":", character

    # Find symbol at cursor position
    let symbol = findSymbolAtPosition(uri, line, character)

    var resultData: JsonNode
    if symbol != nil:
      # Return the location of the symbol definition
      resultData = %*{
        "uri": symbol.location.uri,
        "range": %*{
          "start": %*{
            "line": symbol.location.range.start.line,
            "character": symbol.location.range.start.character
          },
          "end": %*{
            "line": symbol.location.range.finish.line,
            "character": symbol.location.range.finish.character
          }
        }
      }
    else:
      resultData = newJNull()

    return newResponse(id, resultData)

  except CatchableError as e:
    return newErrorResponse(id, -32603, "Definition failed: " & e.msg)

proc handle_text_document_hover*(id: JsonNode, params: JsonNode): Future[string] {.async.} =
  try:
    let text_doc = params["textDocument"]
    let position = params["position"]
    let uri = text_doc["uri"].getStr()
    let line = position["line"].getInt()
    let character = position["character"].getInt()

    if lsp_config.trace:
      echo "LSP Hover requested for: ", uri, " at ", line, ":", character

    # Get hover information
    let (found, content, kind) = getHoverInfo(uri, line, character)

    var resultData: JsonNode
    if found:
      resultData = %*{
        "contents": %*{
          "kind": kind,
          "value": content
        }
      }
    else:
      resultData = newJNull()

    return newResponse(id, resultData)

  except CatchableError as e:
    return newErrorResponse(id, -32603, "Hover failed: " & e.msg)

proc handle_text_document_references*(id: JsonNode, params: JsonNode): Future[string] {.async.} =
  try:
    let text_doc = params["textDocument"]
    let position = params["position"]
    let context = params.getOrDefault("context")
    let uri = text_doc["uri"].getStr()
    let line = position["line"].getInt()
    let character = position["character"].getInt()

    # Check if we should include declaration
    var includeDeclaration = true
    if context != nil and context.hasKey("includeDeclaration"):
      includeDeclaration = context["includeDeclaration"].getBool()

    if lsp_config.trace:
      echo "LSP References requested for: ", uri, " at ", line, ":", character

    # Find all references to the symbol at cursor
    let references = findReferencesAtPosition(uri, line, character, includeDeclaration)

    # Convert to LSP Location array
    var resultArray = newJArray()
    for loc in references:
      resultArray.add(%*{
        "uri": loc.uri,
        "range": %*{
          "start": %*{
            "line": loc.range.start.line,
            "character": loc.range.start.character
          },
          "end": %*{
            "line": loc.range.finish.line,
            "character": loc.range.finish.character
          }
        }
      })

    return newResponse(id, resultArray)

  except CatchableError as e:
    return newErrorResponse(id, -32603, "References failed: " & e.msg)

proc handle_workspace_symbol*(id: JsonNode, params: JsonNode): Future[string] {.async.} =
  try:
    # Get search query (optional)
    var query = ""
    if params != nil and params.hasKey("query"):
      query = params["query"].getStr()

    if lsp_config.trace:
      echo "LSP Workspace symbols requested with query: '", query, "'"

    # Search for symbols matching the query
    let symbols = searchSymbols(query)

    # Convert to LSP SymbolInformation array
    var resultArray = newJArray()
    for symbol in symbols:
      var kind_int = 0
      case symbol.kind:
      of skFunction:
        kind_int = 12  # LSP SymbolKind.Function
      of skVariable:
        kind_int = 13  # LSP SymbolKind.Variable
      of skClass:
        kind_int = 5   # LSP SymbolKind.Class
      of skModule:
        kind_int = 2   # LSP SymbolKind.Module
      of skConstant:
        kind_int = 14  # LSP SymbolKind.Constant
      of skProperty:
        kind_int = 7   # LSP SymbolKind.Property

      resultArray.add(%*{
        "name": symbol.name,
        "kind": kind_int,
        "location": %*{
          "uri": symbol.location.uri,
          "range": %*{
            "start": %*{
              "line": symbol.location.range.start.line,
              "character": symbol.location.range.start.character
            },
            "end": %*{
              "line": symbol.location.range.finish.line,
              "character": symbol.location.range.finish.character
            }
          }
        },
        "containerName": ""
      })

    return newResponse(id, resultArray)

  except CatchableError as e:
    return newErrorResponse(id, -32603, "Workspace symbol failed: " & e.msg)

# LSP JSON-RPC Message Handling
proc handle_lsp_request*(request_text: string): Future[string] {.async.} =
  if request_text.len == 0:
    return newErrorResponse(newJNull(), -32700, "Empty request body")

  try:
    let json_data = parseJson(request_text)
    let method_name = json_data["method"].getStr()
    let id = json_data.getOrDefault("id")
    let params = json_data.getOrDefault("params")

    if lsp_config.trace:
      echo "LSP Request: ", method_name, " ", $params

    case method_name:
      of "initialize":
        return await handle_initialize(id, params)
      of "shutdown":
        return await handle_shutdown(id, params)
      of "textDocument/didOpen":
        return await handle_text_document_did_open(id, params)
      of "textDocument/didClose":
        return await handle_text_document_did_close(id, params)
      of "textDocument/didChange":
        return await handle_text_document_did_change(id, params)
      of "textDocument/completion":
        return await handle_text_document_completion(id, params)
      of "textDocument/definition":
        return await handle_text_document_definition(id, params)
      of "textDocument/hover":
        return await handle_text_document_hover(id, params)
      of "textDocument/references":
        return await handle_text_document_references(id, params)
      of "workspace/symbol":
        return await handle_workspace_symbol(id, params)
      else:
        return newErrorResponse(id, -32601, "Method not found: " & method_name)

  except JsonParsingError as e:
    return newErrorResponse(newJNull(), -32700, "Parse error: " & e.msg)
  except CatchableError as e:
    return newErrorResponse(newJNull(), -32603, "Internal error: " & e.msg)

# Main LSP Server Loop
proc start_lsp_server*(config: LspConfig): Future[void] {.async.} =
  lsp_config = config
  
  lsp_server = LspServer(
    socket: newAsyncSocket(),
    config: lsp_config,
    clients: @[],
    state: LspState(
      workspaceRoot: lsp_config.workspace,
      documents: initTable[string, DocumentState](),
      symbols: initTable[string, seq[SymbolInfo]](),
      capabilities: ServerCapabilities(
        textDocumentSync: %*{
          "openClose": true,
          "change": %*1
        },
        completionProvider: %*{
          "resolveProvider": true,
          "triggerCharacters": @[":", "(", "["]
        },
        definitionProvider: %*true,
        hoverProvider: %*true,
        referencesProvider: %*true,
        workspaceSymbolProvider: %*true
      )
    )
  )

  if lsp_config.workspace.len > 0:
    echo "LSP Server starting in workspace: ", lsp_config.workspace
    setCurrentDir(lsp_config.workspace)

  echo "LSP Server listening on ", lsp_config.host, ":", lsp_config.port
  
  lsp_server.socket.bindAddr(Port(lsp_config.port), lsp_config.host)
  lsp_server.socket.listen()

  while true:
    let client = await lsp_server.socket.accept()

    # Add client to list
    lsp_server.clients.add(client)

    # Handle client connection in background
    asyncCheck (proc() {.async.} =
      try:
        while true:
          let line = await client.recvLine()
          if line.len == 0:
            break

          let response = await handle_lsp_request(line)
          await client.send(response & "\r\n")
      except:
        discard
      finally:
        # Remove client from list
        let idx = lsp_server.clients.find(client)
        if idx >= 0:
          lsp_server.clients.delete(idx)
        client.close()
    )()
