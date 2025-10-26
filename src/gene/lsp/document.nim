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
    source: "gene-lsp",
    code: ""
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
  result = %*{
    "range": toJson(diag.range),
    "severity": diag.severity.int,
    "message": diag.message,
    "source": diag.source
  }
  if diag.code.len > 0:
    result["code"] = %diag.code

# Forward declaration
proc extractSymbols*(doc: ParsedDocument)

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
    extractSymbols(result)
    
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

proc extractSymbolsFromValue(value: Value, uri: string, symbols: var seq[SymbolInfo], depth: int = 0) =
  ## Recursively extract symbols from a Value
  if value.is_nil or depth > 10:  # Prevent infinite recursion
    return

  case value.kind:
  of VkGene:
    let gene = value.gene
    if gene.type.kind == VkSymbol:
      let type_name = gene.type.str

      case type_name:
      of "var", "let", "const":
        # Variable declaration: (var name value)
        if gene.children.len >= 1:
          let name_val = gene.children[0]
          if name_val.kind == VkSymbol:
            symbols.add(SymbolInfo(
              name: name_val.str,
              kind: skVariable,
              location: Location(
                uri: uri,
                range: Range(
                  start: Position(line: 0, character: 0),  # TODO: Get actual position
                  finish: Position(line: 0, character: 0)
                )
              ),
              details: "variable"
            ))

      of "fn", "fnx":
        # Function declaration: (fn name [args] body...)
        if gene.children.len >= 2:
          let name_val = gene.children[0]
          if name_val.kind == VkSymbol:
            var signature = name_val.str & " "
            # Try to get argument list
            if gene.children.len >= 2 and gene.children[1].kind == VkVector:
              signature &= "["
              let args = gene.children[1].ref.arr
              for i, arg in args:
                if i > 0:
                  signature &= " "
                signature &= $arg
              signature &= "]"

            symbols.add(SymbolInfo(
              name: name_val.str,
              kind: skFunction,
              location: Location(
                uri: uri,
                range: Range(
                  start: Position(line: 0, character: 0),
                  finish: Position(line: 0, character: 0)
                )
              ),
              details: signature
            ))

      of "class":
        # Class declaration: (class Name ...)
        if gene.children.len >= 1:
          let name_val = gene.children[0]
          if name_val.kind == VkSymbol:
            symbols.add(SymbolInfo(
              name: name_val.str,
              kind: skClass,
              location: Location(
                uri: uri,
                range: Range(
                  start: Position(line: 0, character: 0),
                  finish: Position(line: 0, character: 0)
                )
              ),
              details: "class"
            ))

            # Extract methods from class body
            for i in 1..<gene.children.len:
              extractSymbolsFromValue(gene.children[i], uri, symbols, depth + 1)

      of "module", "ns", "namespace":
        # Module/namespace declaration
        if gene.children.len >= 1:
          let name_val = gene.children[0]
          if name_val.kind == VkSymbol:
            symbols.add(SymbolInfo(
              name: name_val.str,
              kind: skModule,
              location: Location(
                uri: uri,
                range: Range(
                  start: Position(line: 0, character: 0),
                  finish: Position(line: 0, character: 0)
                )
              ),
              details: "module"
            ))
      else:
        # Recursively process children for other gene types
        for child in gene.children:
          extractSymbolsFromValue(child, uri, symbols, depth + 1)

  of VkVector:
    # Process vector elements
    for elem in value.ref.arr:
      extractSymbolsFromValue(elem, uri, symbols, depth + 1)

  else:
    # Other value types don't contain symbols
    discard

proc extractSymbols*(doc: ParsedDocument) =
  ## Extract symbols from parsed AST
  doc.symbols = @[]
  for node in doc.ast:
    extractSymbolsFromValue(node, doc.uri, doc.symbols)

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
  result = @[]

  # Add Gene keywords
  let keywords = @["var", "fn", "if", "do", "class", "new", "import", "export",
                   "try", "catch", "throw", "async", "await", "for", "while",
                   "return", "break", "continue", "let", "const", "fnx", "module",
                   "ns", "namespace"]

  for keyword in keywords:
    result.add(CompletionItem(
      label: keyword,
      kind: ckKeyword,
      detail: "Gene keyword",
      documentation: "",
      insertText: "",
      insertTextFormat: "",
      sortText: "0_" & keyword  # Sort keywords first
    ))

  # Add symbols from the current document
  let doc = getDocument(uri)
  if doc != nil:
    for symbol in doc.symbols:
      var kind: CompletionItemKind
      case symbol.kind:
      of skFunction:
        kind = ckFunction
      of skVariable:
        kind = ckVariable
      of skClass:
        kind = ckClass
      of skModule:
        kind = ckModule
      of skConstant:
        kind = ckVariable  # Use variable kind for constants
      of skProperty:
        kind = ckProperty

      result.add(CompletionItem(
        label: symbol.name,
        kind: kind,
        detail: symbol.details,
        documentation: "",
        insertText: "",
        insertTextFormat: "",
        sortText: "1_" & symbol.name  # Sort symbols after keywords
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
