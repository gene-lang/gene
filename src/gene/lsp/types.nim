## LSP Types and Protocol Definitions

import json, tables, strutils

# LSP Message Types
type
  LspRequest* = ref object
    id*: JsonNode      # Request ID for correlation
    method_name*: string   # LSP method name
    params*: JsonNode # Request parameters

  LspResponse* = ref object
    id*: JsonNode      # Request ID being responded to
    result*: JsonNode # Response result or error

  LspNotification* = ref object
    method_name*: string   # Notification method name
    params*: JsonNode # Notification parameters

# LSP Position Types
type
  Position* = object
    line*: int     # 0-based line position
    character*: int # 0-based character position

  Range* = object
    start*: Position
    finish*: Position

  Location* = object
    uri*: string     # Document URI
    range*: Range   # Range within document

# LSP Symbol Types
type
  SymbolKind* = enum
    skFunction
    skVariable
    skClass
    skModule
    skConstant
    skProperty

  SymbolInfo* = ref object
    name*: string
    kind*: SymbolKind
    location*: Location
    details*: string # Additional details like signature

# LSP Completion Types
type
  CompletionItemKind* = enum
    ckText
    ckMethod
    ckFunction
    ckConstructor
    ckField
    ckVariable
    ckClass
    ckModule
    ckProperty

  CompletionItem* = ref object
    label*: string
    kind*: CompletionItemKind
    detail*: string
    documentation*: string
    insertText*: string
    insertTextFormat*: string
    sortText*: string

# LSP Document Types
type
  DocumentState* = ref object
    version*: int    # Document version for change tracking
    language*: string # Document language identifier

# LSP Diagnostic Types
type
  DiagnosticSeverity* = enum
    dsError
    dsWarning
    dsInformation
    dsHint

  Diagnostic* = ref object
    range*: Range
    severity*: DiagnosticSeverity
    code*: string
    source*: string
    message*: string

# LSP Workspace Information
type
  WorkspaceFolder* = ref object
    uri*: string
    name*: string

# LSP Server Configuration
type
  ServerCapabilities* = ref object
    textDocumentSync*: JsonNode
    completionProvider*: JsonNode
    hoverProvider*: JsonNode
    definitionProvider*: JsonNode
    referencesProvider*: JsonNode
    documentSymbolProvider*: JsonNode
    workspaceSymbolProvider*: JsonNode

# Gene-specific LSP Extensions
type
  GeneSymbolInfo* = ref object
    symbolInfo*: SymbolInfo
    signature*: string
    documentation*: string
    returnType*: string
    scope*: string

# LSP State Management
type
  LspState* = ref object
    workspaceRoot*: string
    documents*: Table[string, DocumentState]  # URI -> document state
    symbols*: Table[string, seq[SymbolInfo]]  # URI -> symbols in document
    capabilities*: ServerCapabilities