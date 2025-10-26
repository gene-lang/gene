## Gene Language Server Protocol (LSP) Server Implementation

import asyncdispatch, json, strutils, net, asyncnet, tables, os
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

var lsp_config*: LspConfig
var lsp_server*: LspServer

# Helper functions for LSP responses
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

    # Send diagnostics to client if any
    if doc.diagnostics.len > 0:
      # TODO: Send diagnostics as a notification
      discard

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

    if lsp_config.trace:
      echo "LSP Definition requested for: ", uri, " at position: ", $position

    # TODO: Implement actual definition lookup
    let resultData = newJNull()

    return newResponse(id, resultData)

  except CatchableError as e:
    return newErrorResponse(id, -32603, "Definition failed: " & e.msg)

proc handle_text_document_hover*(id: JsonNode, params: JsonNode): Future[string] {.async.} =
  try:
    let text_doc = params["textDocument"]
    let position = params["position"]
    let uri = text_doc["uri"].getStr()

    if lsp_config.trace:
      echo "LSP Hover requested for: ", uri, " at position: ", $position

    # TODO: Implement actual hover information
    let resultData = newJNull()

    return newResponse(id, resultData)

  except CatchableError as e:
    return newErrorResponse(id, -32603, "Hover failed: " & e.msg)

proc handle_workspace_symbol*(id: JsonNode, params: JsonNode): Future[string] {.async.} =
  try:
    if lsp_config.trace:
      echo "LSP Workspace symbols requested"

    # TODO: Implement workspace symbol listing
    let resultData = %*(@[])

    return newResponse(id, resultData)

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
        client.close()
    )()
