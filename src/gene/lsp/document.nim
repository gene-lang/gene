## LSP Document Parser and Analysis Module
## Parses Gene documents and maintains AST cache for language services

import tables, json, strutils
import ../types, ../parser
import ./types

type
  ParsedDocument* = ref object
    uri*: string
    version*: int
    content*: string
    ast*: seq[Value]  # Parsed AST nodes
    symbols*: seq[SymbolInfo]  # Extracted symbols
    diagnostics*: seq[Diagnostic]  # Parse errors and warnings
    parseError*: bool  # Whether parsing failed

  Diagnostic* = object
    range*: Range
    severity*: DiagnosticSeverity
    message*: string
    source*: string

  DiagnosticSeverity* = enum
    dsError = 1
    dsWarning = 2
    dsInformation = 3
    dsHint = 4

# Document cache
var document_cache* = initTable[string, ParsedDocument]()

proc newRange*(startLine, startChar, endLine, endChar: int): Range =
  Range(
    start: Position(line: startLine, character: startChar),
    finish: Position(line: endLine, character: endChar)
  )

proc newDiagnostic*(range: Range, severity: DiagnosticSeverity, message: string): Diagnostic =
  Diagnostic(
    range: range,
    severity: severity,
    message: message,
    source: "gene-lsp"
  )

proc toJson*(pos: Position): JsonNode =
  %*{
    "line": pos.line,
    "character": pos.character
  }

proc toJson*(rng: Range): JsonNode =
  %*{
    "start": toJson(rng.start),
    "end": toJson(rng.finish)
  }

proc toJson*(diag: Diagnostic): JsonNode =
  %*{
    "range": toJson(diag.range),
    "severity": diag.severity.int,
    "message": diag.message,
    "source": diag.source
  }

proc parseDocument*(uri: string, content: string, version: int): ParsedDocument =
  ## Parse a Gene document and extract symbols
  result = ParsedDocument(
    uri: uri,
    version: version,
    content: content,
    ast: @[],
    symbols: @[],
    diagnostics: @[],
    parseError: false
  )

  # Try to parse the document
  try:
    var parser = new_parser()
    result.ast = parser.read_all(content)
    
    # If parsing succeeded, extract symbols
    # TODO: Implement symbol extraction
    
  except ParseError as e:
    # Parse error - create diagnostic
    result.parseError = true
    let diag = newDiagnostic(
      newRange(0, 0, 0, 0),  # TODO: Get actual position from error
      dsError,
      "Parse error: " & e.msg
    )
    result.diagnostics.add(diag)

  except ParseEofError as e:
    # EOF error - might be incomplete document
    result.parseError = true
    let diag = newDiagnostic(
      newRange(0, 0, 0, 0),
      dsError,
      "Unexpected end of file: " & e.msg
    )
    result.diagnostics.add(diag)

  except CatchableError as e:
    # Other errors
    result.parseError = true
    let diag = newDiagnostic(
      newRange(0, 0, 0, 0),
      dsError,
      "Error parsing document: " & e.msg
    )
    result.diagnostics.add(diag)

proc extractSymbols*(doc: ParsedDocument) =
  ## Extract symbols from parsed AST
  ## This will be implemented in the next phase
  discard

proc getDocument*(uri: string): ParsedDocument =
  ## Get a document from cache
  if document_cache.hasKey(uri):
    return document_cache[uri]
  return nil

proc updateDocument*(uri: string, content: string, version: int): ParsedDocument =
  ## Update or create a document in the cache
  result = parseDocument(uri, content, version)
  document_cache[uri] = result

proc removeDocument*(uri: string) =
  ## Remove a document from cache
  if document_cache.hasKey(uri):
    document_cache.del(uri)

proc getSymbolsInDocument*(uri: string): seq[SymbolInfo] =
  ## Get all symbols in a document
  let doc = getDocument(uri)
  if doc != nil:
    return doc.symbols
  return @[]

proc getDiagnostics*(uri: string): seq[Diagnostic] =
  ## Get diagnostics for a document
  let doc = getDocument(uri)
  if doc != nil:
    return doc.diagnostics
  return @[]

proc findSymbolAtPosition*(uri: string, line: int, character: int): SymbolInfo =
  ## Find symbol at a specific position
  ## This will be implemented when we add position tracking to symbols
  result = SymbolInfo(
    name: "",
    kind: skVariable,
    location: Location(
      uri: uri,
      range: Range(
        start: Position(line: 0, character: 0),
        finish: Position(line: 0, character: 0)
      )
    ),
    details: ""
  )

proc getCompletionsAtPosition*(uri: string, line: int, character: int): seq[CompletionItem] =
  ## Get completion items at a specific position
  ## This will be implemented when we add scope tracking
  result = @[]
  
  # For now, return some basic Gene keywords as completions
  let keywords = @["var", "fn", "if", "do", "class", "new", "import", "export", 
                   "try", "catch", "throw", "async", "await", "for", "while", 
                   "return", "break", "continue"]
  
  for keyword in keywords:
    result.add(CompletionItem(
      label: keyword,
      kind: ckKeyword,
      detail: "Gene keyword",
      documentation: "",
      insertText: "",
      insertTextFormat: "",
      sortText: ""
    ))

proc getHoverInfo*(uri: string, line: int, character: int): string =
  ## Get hover information at a specific position
  ## This will be implemented when we add type information
  return ""

# Helper to convert URI to file path
proc uriToPath*(uri: string): string =
  ## Convert file:// URI to file path
  if uri.startsWith("file://"):
    result = uri[7..^1]
    # Handle Windows paths
    when defined(windows):
      if result.len > 2 and result[0] == '/' and result[2] == ':':
        result = result[1..^1]
  else:
    result = uri

proc pathToUri*(path: string): string =
  ## Convert file path to file:// URI
  when defined(windows):
    result = "file:///" & path.replace("\\", "/")
  else:
    result = "file://" & path
