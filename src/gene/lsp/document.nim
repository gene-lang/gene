## LSP Document Parser and Analysis Module
## Parses Gene documents and maintains AST cache for language services

import tables, json, strutils
import ../types, ../parser
import ./types

type
  SymbolReference* = object
    name*: string
    location*: Location
    isDefinition*: bool  # True if this is the definition, false if usage

  TypedVariableInfo* = object
    name*: string
    typeText*: string
    location*: Location

  ParsedDocument* = ref object
    uri*: string
    version*: int
    content*: string
    ast*: seq[Value]  # Parsed AST nodes
    symbols*: seq[SymbolInfo]  # Extracted symbols (definitions)
    references*: seq[SymbolReference]  # Symbol definition references
    typedVariables*: seq[TypedVariableInfo]  # Variables with explicit type annotations
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

proc contentLines(content: string): seq[string] =
  result = content.splitLines()
  if result.len == 0:
    result = @[""]

proc rangeContains(rng: Range, line: int, character: int): bool =
  if line < rng.start.line or line > rng.finish.line:
    return false

  if rng.start.line == rng.finish.line:
    return line == rng.start.line and character >= rng.start.character and character < rng.finish.character

  if line == rng.start.line:
    return character >= rng.start.character
  if line == rng.finish.line:
    return character < rng.finish.character
  return true

proc isDigitAscii(ch: char): bool {.inline.} =
  ch >= '0' and ch <= '9'

proc readNumber(message: string, index: var int): int =
  let start = index
  while index < message.len and isDigitAscii(message[index]):
    index.inc()

  if index == start:
    return -1

  try:
    result = parseInt(message[start ..< index])
  except ValueError:
    result = -1

proc extractLineCol(message: string): tuple[found: bool, line: int, col: int] =
  # Pattern 1: "(line, col)"
  for i in 0 ..< message.len:
    if message[i] != '(':
      continue

    var j = i + 1
    while j < message.len and message[j].isSpaceAscii():
      j.inc()

    let line = readNumber(message, j)
    if line < 0:
      continue

    while j < message.len and message[j].isSpaceAscii():
      j.inc()
    if j >= message.len or message[j] != ',':
      continue
    j.inc()
    while j < message.len and message[j].isSpaceAscii():
      j.inc()

    let col = readNumber(message, j)
    if col < 0:
      continue

    return (true, line, col)

  # Pattern 2: "...line:col..." (take right-most pair)
  var foundColon = false
  var bestLine = 0
  var bestCol = 0
  var i = 0
  while i < message.len:
    if not isDigitAscii(message[i]):
      i.inc()
      continue

    var j = i
    let line = readNumber(message, j)
    if line >= 0 and j < message.len and message[j] == ':':
      j.inc()
      let col = readNumber(message, j)
      if col >= 0:
        foundColon = true
        bestLine = line
        bestCol = col
        i = j
        continue

    i.inc()

  if foundColon:
    return (true, bestLine, bestCol)

  # Pattern 3: trailing line number only, e.g. "... <input> 12"
  var endPos = message.len - 1
  while endPos >= 0 and message[endPos].isSpaceAscii():
    endPos.dec()

  if endPos >= 0:
    var startPos = endPos
    while startPos >= 0 and isDigitAscii(message[startPos]):
      startPos.dec()

    if startPos < endPos:
      try:
        let line = parseInt(message[startPos + 1 .. endPos])
        return (true, line, 1)
      except ValueError:
        discard

  (false, 0, 0)

proc rangeFromLineCol(lines: seq[string], lineOneBased: int, colOneBased: int): Range =
  if lines.len == 0:
    return newRange(0, 0, 0, 0)

  var line = max(1, lineOneBased) - 1
  if line >= lines.len:
    line = lines.len - 1

  let lineText = lines[line]
  if lineText.len == 0:
    return newRange(line, 0, line, 0)

  var col = max(1, colOneBased) - 1
  if col >= lineText.len:
    col = lineText.len - 1

  newRange(line, col, line, min(lineText.len, col + 1))

proc fallbackErrorRange(lines: seq[string]): Range =
  if lines.len == 0:
    return newRange(0, 0, 0, 0)

  let line = lines.len - 1
  let lineLen = lines[line].len
  if lineLen == 0:
    return newRange(line, 0, line, 0)

  newRange(line, lineLen - 1, line, lineLen)

proc parseErrorRange(content: string, message: string): Range =
  let lines = contentLines(content)
  let (found, line, col) = extractLineCol(message)
  if found:
    return rangeFromLineCol(lines, line, col)
  fallbackErrorRange(lines)

proc isSymbolChar(ch: char): bool {.inline.} =
  ch notin {' ', '\t', '\r', '\n', '(', ')', '[', ']', '{', '}', '"', '\'', ',', ';'}

proc trimVarName(raw: string): string =
  if raw.endsWith(":") and raw.len > 1:
    return raw[0 .. ^2]
  raw

proc tokenAtPosition(doc: ParsedDocument, line: int, character: int): string =
  let lines = contentLines(doc.content)
  if line < 0 or line >= lines.len:
    return ""

  let lineText = lines[line]
  if lineText.len == 0:
    return ""

  var idx = character
  if idx >= lineText.len:
    idx = lineText.len - 1
  if idx < 0:
    idx = 0

  if not isSymbolChar(lineText[idx]):
    if idx > 0 and isSymbolChar(lineText[idx - 1]):
      idx.dec()
    else:
      return ""

  var left = idx
  var right = idx
  while left > 0 and isSymbolChar(lineText[left - 1]):
    left.dec()
  while right + 1 < lineText.len and isSymbolChar(lineText[right + 1]):
    right.inc()

  result = lineText[left .. right]
  if result.startsWith("^") and result.len > 1:
    result = result[1 .. ^1]
  result = trimVarName(result)

proc makeLocation(uri: string, rng: Range): Location =
  Location(uri: uri, range: rng)

proc findTokenRange(lines: seq[string], token: string, preferredLineOneBased: int, preferredColOneBased: int,
                   highlightLen: int): Range =
  if lines.len == 0:
    return newRange(0, 0, 0, 0)

  if token.len == 0:
    return rangeFromLineCol(lines, preferredLineOneBased, preferredColOneBased)

  let highlightLength = max(1, highlightLen)
  let preferredLine = max(0, min(lines.len - 1, preferredLineOneBased - 1))
  let preferredCol = max(0, preferredColOneBased - 1)
  let offsets = @[0, 1, -1, 2, -2, 3, -3]

  for offset in offsets:
    let lineIdx = preferredLine + offset
    if lineIdx < 0 or lineIdx >= lines.len:
      continue

    let lineText = lines[lineIdx]
    if lineText.len == 0:
      continue

    var idx = lineText.find(token)
    if lineIdx == preferredLine and preferredCol < lineText.len:
      let preferredIdx = lineText.find(token, preferredCol)
      if preferredIdx >= 0:
        idx = preferredIdx
    if idx < 0:
      continue

    let endChar = min(lineText.len, idx + highlightLength)
    return newRange(lineIdx, idx, lineIdx, endChar)

  for lineIdx, lineText in lines:
    let idx = lineText.find(token)
    if idx >= 0:
      let endChar = min(lineText.len, idx + highlightLength)
      return newRange(lineIdx, idx, lineIdx, endChar)

  rangeFromLineCol(lines, preferredLineOneBased, preferredColOneBased)

proc valueDisplay(v: Value): string =
  $v

proc symbolName(v: Value): string =
  case v.kind:
  of VkSymbol:
    v.str
  of VkComplexSymbol:
    v.ref.csymbol.join("/")
  else:
    ""

proc extractSymbolsFromValue(value: Value, doc: ParsedDocument, lines: seq[string], depth: int = 0)

proc addDefinition(doc: ParsedDocument, name: string, kind: SymbolKind, details: string, rng: Range) =
  doc.symbols.add(SymbolInfo(
    name: name,
    kind: kind,
    location: makeLocation(doc.uri, rng),
    details: details
  ))
  doc.references.add(SymbolReference(
    name: name,
    location: makeLocation(doc.uri, rng),
    isDefinition: true
  ))

proc extractSymbolsFromValue(value: Value, doc: ParsedDocument, lines: seq[string], depth: int = 0) =
  if value.is_nil or depth > 20:
    return

  case value.kind:
  of VkGene:
    let gene = value.gene
    if gene == nil:
      return

    if gene.`type`.kind == VkSymbol:
      let formName = gene.`type`.str

      case formName:
      of "var", "let", "const":
        if gene.children.len >= 1:
          let nameVal = gene.children[0]
          if nameVal.kind == VkSymbol:
            let rawName = nameVal.str
            let name = trimVarName(rawName)
            let hasAnnotation = rawName.endsWith(":") and gene.children.len >= 2
            let typeText = if hasAnnotation: valueDisplay(gene.children[1]) else: ""
            let searchToken = if hasAnnotation: name & ":" else: name
            let rng = findTokenRange(
              lines,
              searchToken,
              if gene.trace != nil: gene.trace.line else: 1,
              if gene.trace != nil: gene.trace.column else: 1,
              max(1, name.len)
            )
            let details = if typeText.len > 0: "type: " & typeText else: "variable"
            addDefinition(doc, name, skVariable, details, rng)
            if typeText.len > 0:
              doc.typedVariables.add(TypedVariableInfo(
                name: name,
                typeText: typeText,
                location: makeLocation(doc.uri, rng)
              ))

      of "fn":
        if gene.children.len >= 2:
          let name = symbolName(gene.children[0])
          if name.len > 0:
            var signature = name
            if gene.children[1].kind == VkArray:
              signature &= " ["
              let args = array_data(gene.children[1])
              for i, arg in args:
                if i > 0:
                  signature &= " "
                signature &= valueDisplay(arg)
              signature &= "]"
            let rng = findTokenRange(
              lines,
              name,
              if gene.trace != nil: gene.trace.line else: 1,
              if gene.trace != nil: gene.trace.column else: 1,
              max(1, name.len)
            )
            addDefinition(doc, name, skFunction, signature, rng)

      of "class":
        if gene.children.len >= 1:
          let name = symbolName(gene.children[0])
          if name.len > 0:
            let rng = findTokenRange(
              lines,
              name,
              if gene.trace != nil: gene.trace.line else: 1,
              if gene.trace != nil: gene.trace.column else: 1,
              max(1, name.len)
            )
            addDefinition(doc, name, skClass, "class", rng)

      of "module", "ns", "namespace":
        if gene.children.len >= 1:
          let name = symbolName(gene.children[0])
          if name.len > 0:
            let rng = findTokenRange(
              lines,
              name,
              if gene.trace != nil: gene.trace.line else: 1,
              if gene.trace != nil: gene.trace.column else: 1,
              max(1, name.len)
            )
            addDefinition(doc, name, skModule, "module", rng)
      else:
        discard

    for child in gene.children:
      extractSymbolsFromValue(child, doc, lines, depth + 1)

  of VkArray:
    for elem in array_data(value):
      extractSymbolsFromValue(elem, doc, lines, depth + 1)

  else:
    discard

proc extractSymbols*(doc: ParsedDocument) =
  ## Extract symbols and typed variables from parsed AST
  doc.symbols = @[]
  doc.references = @[]
  doc.typedVariables = @[]

  let lines = contentLines(doc.content)
  for node in doc.ast:
    extractSymbolsFromValue(node, doc, lines)

proc parseDocument*(uri: string, content: string, version: int): ParsedDocument =
  ## Parse a Gene document and extract symbols
  result = ParsedDocument(
    uri: uri,
    version: version,
    content: content,
    ast: @[],
    symbols: @[],
    references: @[],
    typedVariables: @[],
    diagnostics: @[],
    parseError: false
  )

  try:
    var parser = new_parser()
    result.ast = parser.read_all(content)
    extractSymbols(result)

  except ParseEofError as e:
    result.parseError = true
    result.diagnostics.add(newDiagnostic(
      parseErrorRange(content, e.msg),
      dsError,
      "Unexpected end of file: " & e.msg
    ))

  except ParseError as e:
    result.parseError = true
    result.diagnostics.add(newDiagnostic(
      parseErrorRange(content, e.msg),
      dsError,
      "Parse error: " & e.msg
    ))

  except CatchableError as e:
    result.parseError = true
    result.diagnostics.add(newDiagnostic(
      fallbackErrorRange(contentLines(content)),
      dsError,
      "Error parsing document: " & e.msg
    ))

proc getDocument*(uri: string): ParsedDocument =
  ## Get a document from cache
  if document_cache.hasKey(uri):
    return document_cache[uri]
  nil

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
  @[]

proc getAllSymbols*(): seq[SymbolInfo] =
  ## Get all symbols from all cached documents
  result = @[]
  for _, doc in document_cache:
    for symbol in doc.symbols:
      result.add(symbol)

proc searchSymbols*(query: string): seq[SymbolInfo] =
  ## Search for symbols matching the query across all documents
  result = @[]
  let queryLower = query.toLowerAscii()

  for _, doc in document_cache:
    for symbol in doc.symbols:
      if queryLower.len == 0 or symbol.name.toLowerAscii().contains(queryLower):
        result.add(symbol)

proc getDiagnostics*(uri: string): seq[Diagnostic] =
  ## Get diagnostics for a document
  let doc = getDocument(uri)
  if doc != nil:
    return doc.diagnostics
  @[]

proc findSymbolAtPosition*(uri: string, line: int, character: int): SymbolInfo =
  ## Find symbol at a specific position
  let doc = getDocument(uri)
  if doc == nil:
    return nil

  for symbol in doc.symbols:
    if rangeContains(symbol.location.range, line, character):
      return symbol

  let token = tokenAtPosition(doc, line, character)
  if token.len == 0:
    return nil
  for symbol in doc.symbols:
    if symbol.name == token:
      return symbol

  nil

proc isIdentifierChar(ch: char): bool {.inline.} =
  ch.isAlphaNumeric() or ch in {'_', '$', '?', '!', ':'}

proc sameRange(a: Range, b: Range): bool =
  a.start.line == b.start.line and
  a.start.character == b.start.character and
  a.finish.line == b.finish.line and
  a.finish.character == b.finish.character

proc findReferencesAtPosition*(uri: string, line: int, character: int, includeDeclaration: bool = true): seq[Location] =
  ## Find all references to the symbol at the given position (text-based fallback)
  result = @[]

  let doc = getDocument(uri)
  if doc == nil:
    return

  var targetName = ""
  let symbol = findSymbolAtPosition(uri, line, character)
  if symbol != nil:
    targetName = symbol.name
  else:
    targetName = tokenAtPosition(doc, line, character)

  if targetName.len == 0:
    return

  let lines = contentLines(doc.content)
  for lineIdx, lineText in lines:
    var startPos = 0
    while startPos < lineText.len:
      let idx = lineText.find(targetName, startPos)
      if idx < 0:
        break

      let leftOk = idx == 0 or not isIdentifierChar(lineText[idx - 1])
      let rightPos = idx + targetName.len
      let rightOk = rightPos >= lineText.len or not isIdentifierChar(lineText[rightPos])

      if leftOk and rightOk:
        let rng = newRange(lineIdx, idx, lineIdx, rightPos)

        var isDecl = false
        for defRef in doc.references:
          if defRef.name == targetName and sameRange(defRef.location.range, rng):
            isDecl = true
            break

        if includeDeclaration or not isDecl:
          result.add(makeLocation(uri, rng))

      startPos = idx + max(1, targetName.len)

proc getCompletionsAtPosition*(uri: string, line: int, character: int): seq[CompletionItem] =
  ## Get completion items at a specific position
  result = @[]

  # Keep parameters for future context-sensitive completion.
  discard line
  discard character

  let keywords = @[
    "var", "fn", "if", "do", "class", "new", "import", "export",
    "try", "catch", "throw", "async", "await", "for", "while",
    "return", "break", "continue", "let", "const", "module",
    "ns", "namespace", "comptime"
  ]

  for keyword in keywords:
    result.add(CompletionItem(
      label: keyword,
      kind: ckKeyword,
      detail: "Gene keyword",
      documentation: "",
      insertText: "",
      insertTextFormat: "",
      sortText: "0_" & keyword
    ))

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
        kind = ckVariable
      of skProperty:
        kind = ckProperty

      result.add(CompletionItem(
        label: symbol.name,
        kind: kind,
        detail: symbol.details,
        documentation: "",
        insertText: "",
        insertTextFormat: "",
        sortText: "1_" & symbol.name
      ))

proc getHoverInfo*(uri: string, line: int, character: int): tuple[found: bool, content: string, kind: string] =
  ## Get hover information at a specific position
  result = (found: false, content: "", kind: "markdown")

  let doc = getDocument(uri)
  if doc == nil:
    return

  for tv in doc.typedVariables:
    if rangeContains(tv.location.range, line, character):
      let content = "### Variable: `" & tv.name & "`\n\n**Type:** `" & tv.typeText & "`"
      return (true, content, "markdown")

  let token = tokenAtPosition(doc, line, character)
  if token.len > 0:
    for tv in doc.typedVariables:
      if tv.name == token:
        let content = "### Variable: `" & tv.name & "`\n\n**Type:** `" & tv.typeText & "`"
        return (true, content, "markdown")

  let symbol = findSymbolAtPosition(uri, line, character)
  if symbol != nil:
    var content = ""
    case symbol.kind:
    of skFunction:
      content = "### Function: `" & symbol.name & "`"
      if symbol.details.len > 0:
        content &= "\n\n**Signature:** `" & symbol.details & "`"
    of skVariable:
      content = "### Variable: `" & symbol.name & "`"
      if symbol.details.startsWith("type: "):
        content &= "\n\n**Type:** `" & symbol.details[6 .. ^1] & "`"
    of skClass:
      content = "### Class: `" & symbol.name & "`"
    of skModule:
      content = "### Module: `" & symbol.name & "`"
    of skConstant:
      content = "### Constant: `" & symbol.name & "`"
    of skProperty:
      content = "### Property: `" & symbol.name & "`"
    return (true, content, "markdown")

proc uriToPath*(uri: string): string =
  ## Convert file:// URI to file path
  if uri.startsWith("file://"):
    result = uri[7..^1]
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
