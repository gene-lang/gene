## Gene Language Server Protocol (LSP) Server Implementation

import asyncdispatch, json, strutils, net, asyncnet, tables, os
import ../types
import ./types, ./document

type
  LspConfig* = ref object
    port*: int
    host*: string
    workspace*: string
    trace*: bool
    stdio*: bool

  LspServer* = ref object
    socket*: AsyncSocket
    config*: LspConfig
    state*: LspState
    clients*: seq[AsyncSocket]

var lsp_config*: LspConfig
var lsp_server*: LspServer
var stdio_mode*: bool = false
var shutdown_requested = false
var exit_requested = false

proc trace_log(msg: string) =
  if lsp_config == nil or not lsp_config.trace:
    return

  if stdio_mode:
    stderr.writeLine(msg)
    stderr.flushFile()
  else:
    echo msg

proc sync_capabilities(): JsonNode =
  %*{
    "openClose": true,
    "change": %*1,
    "save": %*{
      "includeText": true
    }
  }

proc newNotification*(methodName: string, params: JsonNode): string =
  let notification = %*{
    "jsonrpc": "2.0",
    "method": methodName,
    "params": params
  }
  $notification

proc newResponse*(id: JsonNode, resultData: JsonNode): string =
  let response = %*{
    "jsonrpc": "2.0",
    "id": id,
    "result": resultData
  }
  $response

proc newErrorResponse*(id: JsonNode, code: int, message: string): string =
  let response = %*{
    "jsonrpc": "2.0",
    "id": id,
    "error": %*{
      "code": code,
      "message": message
    }
  }
  $response

proc sendNotificationToClients*(notification: string) {.async.} =
  if stdio_mode:
    let header = "Content-Length: " & $notification.len & "\r\n\r\n"
    stdout.write(header & notification)
    stdout.flushFile()
  elif lsp_server != nil and lsp_server.clients.len > 0:
    for client in lsp_server.clients:
      try:
        await client.send(notification & "\r\n")
      except CatchableError:
        discard

proc sendDiagnostics*(uri: string, diagnostics: seq[Diagnostic]) {.async.} =
  var diagArray = newJArray()
  for diag in diagnostics:
    diagArray.add(toJson(diag))

  let params = %*{
    "uri": uri,
    "diagnostics": diagArray
  }
  await sendNotificationToClients(newNotification("textDocument/publishDiagnostics", params))

proc parse_and_publish(uri: string, content: string, version: int) {.async.} =
  let doc = updateDocument(uri, content, version)
  trace_log("LSP Parsed " & $doc.ast.len & " forms for " & uri)
  if doc.diagnostics.len > 0:
    trace_log("LSP Diagnostics: " & $doc.diagnostics.len & " for " & uri)
  await sendDiagnostics(uri, doc.diagnostics)

proc handle_initialize*(id: JsonNode, params: JsonNode): Future[string] {.async.} =
  try:
    shutdown_requested = false
    exit_requested = false

    if params != nil:
      if params.hasKey("rootUri") and params["rootUri"].kind == JString:
        lsp_config.workspace = uriToPath(params["rootUri"].getStr())
      elif params.hasKey("rootPath") and params["rootPath"].kind == JString:
        lsp_config.workspace = params["rootPath"].getStr()

    var clientName = "Unknown"
    if params != nil and params.hasKey("clientInfo"):
      let clientInfo = params["clientInfo"]
      if clientInfo != nil and clientInfo.hasKey("name"):
        clientName = clientInfo["name"].getStr("Unknown")

    let capabilities = %*{
      "textDocumentSync": sync_capabilities(),
      "completionProvider": %*{
        "resolveProvider": false,
        "triggerCharacters": @[":", "(", "["]
      },
      "definitionProvider": true,
      "hoverProvider": true,
      "referencesProvider": true,
      "workspaceSymbolProvider": true
    }

    let resultData = %*{
      "capabilities": capabilities,
      "serverInfo": %*{
        "name": "gene-lsp",
        "version": "0.2.0"
      }
    }

    trace_log("LSP initialized with client: " & clientName)
    newResponse(id, resultData)

  except CatchableError as e:
    newErrorResponse(id, -32603, "Initialization failed: " & e.msg)

proc handle_shutdown*(id: JsonNode, params: JsonNode): Future[string] {.async.} =
  discard params
  shutdown_requested = true
  trace_log("LSP shutdown requested")
  newResponse(id, newJNull())

proc handle_initialized_notification(params: JsonNode): Future[void] {.async.} =
  discard params
  trace_log("LSP initialized notification received")

proc handle_exit_notification(): Future[void] {.async.} =
  exit_requested = true
  trace_log("LSP exit notification received")

proc handle_text_document_did_open*(params: JsonNode): Future[void] {.async.} =
  try:
    let textDoc = params["textDocument"]
    let uri = textDoc["uri"].getStr()
    let content = textDoc["text"].getStr()
    let version = textDoc.getOrDefault("version").getInt(0)

    trace_log("LSP didOpen: " & uri & " (version " & $version & ")")
    await parse_and_publish(uri, content, version)

  except CatchableError as e:
    trace_log("LSP didOpen error: " & e.msg)

proc handle_text_document_did_change*(params: JsonNode): Future[void] {.async.} =
  try:
    let textDoc = params["textDocument"]
    let uri = textDoc["uri"].getStr()
    let version = textDoc.getOrDefault("version").getInt(0)
    let contentChanges = params["contentChanges"]

    trace_log("LSP didChange: " & uri & " (version " & $version & ")")

    if contentChanges.len > 0:
      let change = contentChanges[0]
      if change.hasKey("text"):
        await parse_and_publish(uri, change["text"].getStr(), version)

  except CatchableError as e:
    trace_log("LSP didChange error: " & e.msg)

proc handle_text_document_did_save*(params: JsonNode): Future[void] {.async.} =
  try:
    let textDoc = params["textDocument"]
    let uri = textDoc["uri"].getStr()
    let cached = getDocument(uri)
    let version = if cached != nil: cached.version + 1 else: 0

    var content = ""
    if params.hasKey("text"):
      content = params["text"].getStr()
    else:
      let path = uriToPath(uri)
      if fileExists(path):
        content = readFile(path)
      elif cached != nil:
        content = cached.content

    trace_log("LSP didSave: " & uri)
    await parse_and_publish(uri, content, version)

  except CatchableError as e:
    trace_log("LSP didSave error: " & e.msg)

proc handle_text_document_did_close*(params: JsonNode): Future[void] {.async.} =
  try:
    let textDoc = params["textDocument"]
    let uri = textDoc["uri"].getStr()
    trace_log("LSP didClose: " & uri)
    removeDocument(uri)
    await sendDiagnostics(uri, @[])
  except CatchableError as e:
    trace_log("LSP didClose error: " & e.msg)

proc handle_text_document_completion*(id: JsonNode, params: JsonNode): Future[string] {.async.} =
  try:
    let textDoc = params["textDocument"]
    let position = params["position"]
    let uri = textDoc["uri"].getStr()
    let line = position["line"].getInt()
    let character = position["character"].getInt()

    trace_log("LSP completion: " & uri & ":" & $line & ":" & $character)
    let completions = getCompletionsAtPosition(uri, line, character)

    var items = newJArray()
    for comp in completions:
      items.add(%*{
        "label": comp.label,
        "kind": comp.kind.int,
        "detail": comp.detail,
        "documentation": comp.documentation
      })

    newResponse(id, %*{
      "isIncomplete": false,
      "items": items
    })
  except CatchableError as e:
    newErrorResponse(id, -32603, "Completion failed: " & e.msg)

proc handle_text_document_definition*(id: JsonNode, params: JsonNode): Future[string] {.async.} =
  try:
    let textDoc = params["textDocument"]
    let position = params["position"]
    let uri = textDoc["uri"].getStr()
    let line = position["line"].getInt()
    let character = position["character"].getInt()

    trace_log("LSP definition: " & uri & ":" & $line & ":" & $character)

    let symbol = findSymbolAtPosition(uri, line, character)
    var resultData: JsonNode
    if symbol != nil:
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

    newResponse(id, resultData)
  except CatchableError as e:
    newErrorResponse(id, -32603, "Definition failed: " & e.msg)

proc handle_text_document_hover*(id: JsonNode, params: JsonNode): Future[string] {.async.} =
  try:
    let textDoc = params["textDocument"]
    let position = params["position"]
    let uri = textDoc["uri"].getStr()
    let line = position["line"].getInt()
    let character = position["character"].getInt()

    trace_log("LSP hover: " & uri & ":" & $line & ":" & $character)

    let (found, content, kind) = getHoverInfo(uri, line, character)
    if found:
      return newResponse(id, %*{
        "contents": %*{
          "kind": kind,
          "value": content
        }
      })

    newResponse(id, newJNull())
  except CatchableError as e:
    newErrorResponse(id, -32603, "Hover failed: " & e.msg)

proc handle_text_document_references*(id: JsonNode, params: JsonNode): Future[string] {.async.} =
  try:
    let textDoc = params["textDocument"]
    let position = params["position"]
    let context = params.getOrDefault("context")
    let uri = textDoc["uri"].getStr()
    let line = position["line"].getInt()
    let character = position["character"].getInt()

    var includeDeclaration = true
    if context != nil and context.hasKey("includeDeclaration"):
      includeDeclaration = context["includeDeclaration"].getBool()

    trace_log("LSP references: " & uri & ":" & $line & ":" & $character)
    let references = findReferencesAtPosition(uri, line, character, includeDeclaration)

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

    newResponse(id, resultArray)
  except CatchableError as e:
    newErrorResponse(id, -32603, "References failed: " & e.msg)

proc handle_workspace_symbol*(id: JsonNode, params: JsonNode): Future[string] {.async.} =
  try:
    var query = ""
    if params != nil and params.hasKey("query"):
      query = params["query"].getStr()

    trace_log("LSP workspace/symbol query: '" & query & "'")
    let symbols = searchSymbols(query)

    var resultArray = newJArray()
    for symbol in symbols:
      var kindInt = 0
      case symbol.kind:
      of skFunction:
        kindInt = 12
      of skVariable:
        kindInt = 13
      of skClass:
        kindInt = 5
      of skModule:
        kindInt = 2
      of skConstant:
        kindInt = 14
      of skProperty:
        kindInt = 7

      resultArray.add(%*{
        "name": symbol.name,
        "kind": kindInt,
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

    newResponse(id, resultArray)
  except CatchableError as e:
    newErrorResponse(id, -32603, "Workspace symbol failed: " & e.msg)

proc handle_lsp_request*(request_text: string): Future[string] {.async.} =
  if request_text.len == 0:
    return ""

  try:
    let jsonData = parseJson(request_text)

    if not jsonData.hasKey("method"):
      return ""

    let methodName = jsonData["method"].getStr()
    let hasId = jsonData.hasKey("id") and jsonData["id"].kind != JNull
    let id = if hasId: jsonData["id"] else: newJNull()
    let params = jsonData.getOrDefault("params")

    trace_log("LSP request: " & methodName)

    case methodName:
    of "initialize":
      if hasId:
        return await handle_initialize(id, params)
      return ""
    of "initialized":
      await handle_initialized_notification(params)
      return ""
    of "shutdown":
      if hasId:
        return await handle_shutdown(id, params)
      shutdown_requested = true
      return ""
    of "exit":
      await handle_exit_notification()
      return ""
    of "textDocument/didOpen":
      await handle_text_document_did_open(params)
      return ""
    of "textDocument/didClose":
      await handle_text_document_did_close(params)
      return ""
    of "textDocument/didChange":
      await handle_text_document_did_change(params)
      return ""
    of "textDocument/didSave":
      await handle_text_document_did_save(params)
      return ""
    of "textDocument/completion":
      if hasId:
        return await handle_text_document_completion(id, params)
      return ""
    of "textDocument/definition":
      if hasId:
        return await handle_text_document_definition(id, params)
      return ""
    of "textDocument/hover":
      if hasId:
        return await handle_text_document_hover(id, params)
      return ""
    of "textDocument/references":
      if hasId:
        return await handle_text_document_references(id, params)
      return ""
    of "workspace/symbol":
      if hasId:
        return await handle_workspace_symbol(id, params)
      return ""
    else:
      if hasId:
        return newErrorResponse(id, -32601, "Method not found: " & methodName)
      return ""

  except JsonParsingError as e:
    newErrorResponse(newJNull(), -32700, "Parse error: " & e.msg)
  except CatchableError as e:
    newErrorResponse(newJNull(), -32603, "Internal error: " & e.msg)

proc start_lsp_server*(config: LspConfig): Future[void] {.async.} =
  lsp_config = config
  stdio_mode = false
  shutdown_requested = false
  exit_requested = false

  lsp_server = LspServer(
    socket: newAsyncSocket(),
    config: lsp_config,
    clients: @[],
    state: LspState(
      workspaceRoot: lsp_config.workspace,
      documents: initTable[string, DocumentState](),
      symbols: initTable[string, seq[SymbolInfo]](),
      capabilities: ServerCapabilities(
        textDocumentSync: sync_capabilities(),
        completionProvider: %*{
          "resolveProvider": false,
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
    trace_log("LSP workspace: " & lsp_config.workspace)
    setCurrentDir(lsp_config.workspace)

  echo "LSP Server listening on ", lsp_config.host, ":", lsp_config.port
  lsp_server.socket.bindAddr(Port(lsp_config.port), lsp_config.host)
  lsp_server.socket.listen()

  while not exit_requested:
    let client = await lsp_server.socket.accept()
    lsp_server.clients.add(client)

    asyncCheck (proc() {.async.} =
      try:
        while not exit_requested:
          let line = await client.recvLine()
          if line.len == 0:
            break

          let response = await handle_lsp_request(line)
          if response.len > 0:
            await client.send(response & "\r\n")
      except CatchableError:
        discard
      finally:
        let idx = lsp_server.clients.find(client)
        if idx >= 0:
          lsp_server.clients.delete(idx)
        client.close()
    )()

proc read_stdio_message(): string =
  ## Read a JSON-RPC message from stdin with Content-Length header.
  var contentLength = -1

  while true:
    if endOfFile(stdin):
      return ""

    var rawLine = ""
    try:
      rawLine = stdin.readLine()
    except IOError:
      return ""

    let line = rawLine.strip()
    if line.len == 0:
      break

    let sep = line.find(':')
    if sep <= 0:
      continue

    let headerName = line[0 ..< sep].toLowerAscii()
    let headerValue = line[sep + 1 .. ^1].strip()
    if headerName == "content-length":
      try:
        contentLength = parseInt(headerValue)
      except ValueError:
        return ""

  if contentLength <= 0:
    return ""

  result = newString(contentLength)
  let bytesRead = stdin.readBuffer(addr result[0], contentLength)
  if bytesRead != contentLength:
    result = ""

proc write_stdio_message(message: string) =
  let header = "Content-Length: " & $message.len & "\r\n\r\n"
  stdout.write(header & message)
  stdout.flushFile()

proc start_lsp_stdio_server*(config: LspConfig) =
  lsp_config = config
  stdio_mode = true
  shutdown_requested = false
  exit_requested = false

  if lsp_config.workspace.len > 0:
    trace_log("LSP workspace: " & lsp_config.workspace)
    setCurrentDir(lsp_config.workspace)

  trace_log("LSP server started in stdio mode")

  while not exit_requested:
    try:
      let message = read_stdio_message()
      if message.len == 0:
        trace_log("LSP EOF received, shutting down")
        break

      trace_log("LSP raw request: " & message)
      let response = waitFor handle_lsp_request(message)
      if response.len > 0:
        trace_log("LSP raw response: " & response)
        write_stdio_message(response)
    except IOError as e:
      trace_log("LSP IO error: " & e.msg)
      break
    except CatchableError as e:
      trace_log("LSP error: " & e.msg)
      continue
