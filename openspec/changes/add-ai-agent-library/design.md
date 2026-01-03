# add-ai-agent-library Design

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                      Gene AI Agent Library                       │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────────────┐  │
│  │   Frontend   │  │  Gene HTTP   │  │   SSE Streaming      │  │
│  │  (React/Vue) │◄─┤   Server     │◄─┤   Response Handler   │  │
│  └──────────────┘  └──────────────┘  └──────────────────────┘  │
│                           │                     ▲               │
│                           ▼                     │               │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                    Agent Controller                      │   │
│  │  - Orchestrates conversation flow                        │   │
│  │  - Manages tool execution                                │   │
│  │  - Handles RAG retrieval                                 │   │
│  └─────────────────────────────────────────────────────────┘   │
│         │              │              │              │          │
│         ▼              ▼              ▼              ▼          │
│  ┌───────────┐  ┌───────────┐  ┌───────────┐  ┌───────────┐   │
│  │Conversation│  │   Tool    │  │    RAG    │  │ Streaming │   │
│  │  Manager   │  │ Registry  │  │  Pipeline │  │  Handler  │   │
│  └───────────┘  └───────────┘  └───────────┘  └───────────┘   │
│         │              │              │                         │
│         │              │              ▼                         │
│         │              │       ┌───────────┐                   │
│         │              │       │  Vector   │                   │
│         │              │       │    DB     │◄──── Qdrant       │
│         │              │       │  Client   │                   │
│         │              │       └───────────┘                   │
│         │              │              ▲                         │
│         │              │              │                         │
│         │              │       ┌───────────┐                   │
│         │              │       │ Embedding │                   │
│         │              │       │  Service  │◄──── OpenAI/Local │
│         │              │       └───────────┘                   │
│         │              │              ▲                         │
│         ▼              ▼              │                         │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                   LLM Provider                           │   │
│  │          (genex/ai OpenAI | genex/llm Local)            │   │
│  └─────────────────────────────────────────────────────────┘   │
│                           │                                     │
│                           ▼                                     │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                 Document Processor                       │   │
│  │  ┌──────────┐  ┌──────────┐  ┌──────────┐              │   │
│  │  │   PDF    │  │  Image   │  │  Text    │              │   │
│  │  │ Extractor│  │   OCR    │  │ Chunker  │              │   │
│  │  └──────────┘  └──────────┘  └──────────┘              │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

## Module Structure

```
src/genex/ai/
├── ai.nim              # Main module, exports all submodules
├── documents.nim       # PDF/image processing, chunking
├── vectordb.nim        # Qdrant client, abstract interface
├── conversation.nim    # Message history, context management
├── tools.nim           # Tool registry, function calling
├── streaming.nim       # SSE support, token streaming (optional)
├── rag.nim             # RAG pipeline orchestration
└── utils.nim           # Token counting, helpers
```

## Component Details

### 1. Document Processor (`documents.nim`)

**PDF Extraction:**
- Use a configured external extractor (CLI or API); no internal parsing
- Fallback error handling when the extractor is unavailable
- Page-by-page extraction with metadata

```nim
type
  DocumentChunk* = object
    text*: string
    metadata*: Table[string, Value]  # page_num, source, chunk_index

  ChunkStrategy* = enum
    csFixedSize      # Fixed character/token count
    csSentence       # Sentence boundaries
    csParagraph      # Paragraph boundaries
    csRecursive      # Recursive splitting (LangChain-style)

proc extract_pdf*(path: string): seq[string]
proc extract_image*(path: string): string  # OCR via external tool or API
proc chunk_text*(text: string, strategy: ChunkStrategy, size: int, overlap: int): seq[DocumentChunk]
```

**Gene API:**
```gene
(var chunks (ai/documents/extract_and_chunk
  "document.pdf"
  {^strategy :recursive ^chunk_size 500 ^overlap 50}))
```

### 2. Vector Database Client (`vectordb.nim`)

**Qdrant REST API Client:**
- HTTP client using Nim's `httpclient`
- JSON serialization for requests/responses
- Connection configuration via env vars or explicit config

```nim
type
  QdrantClient* = ref object
    base_url*: string
    api_key*: string  # Optional, for Qdrant Cloud

  VectorPoint* = object
    id*: string
    vector*: seq[float32]
    payload*: Table[string, Value]

  SearchResult* = object
    id*: string
    score*: float32
    payload*: Table[string, Value]

proc new_qdrant_client*(url: string, api_key = ""): QdrantClient
proc create_collection*(client: QdrantClient, name: string, dim: int)
proc upsert*(client: QdrantClient, collection: string, points: seq[VectorPoint])
proc search*(client: QdrantClient, collection: string, vector: seq[float32], limit: int): seq[SearchResult]
proc delete_collection*(client: QdrantClient, name: string)
```

**Gene API:**
```gene
(var qdrant (ai/vectordb/connect "http://localhost:6333"))
(qdrant .create_collection "documents" {^dimension 1536})
(qdrant .upsert "documents" points)
(var results (qdrant .search "documents" query_vector {^limit 5}))
```

### 3. Conversation Manager (`conversation.nim`)

**Message Storage:**
```nim
type
  MessageRole* = enum
    mrSystem, mrUser, mrAssistant, mrTool

  Message* = object
    role*: MessageRole
    content*: string
    tool_call_id*: string  # For tool responses
    tool_calls*: seq[ToolCall]  # For assistant tool requests

  Conversation* = ref object
    messages*: seq[Message]
    max_tokens*: int  # Context window limit
    system_prompt*: string

proc add_message*(conv: Conversation, role: MessageRole, content: string)
proc get_context*(conv: Conversation, token_limit: int): seq[Message]
proc to_openai_messages*(conv: Conversation): seq[Table[string, string]]
```

**Gene API:**
```gene
(var conv (ai/conversation/new {^system_prompt "You are a helpful assistant."}))
(conv .add :user "What is RAG?")
(conv .add :assistant "RAG stands for Retrieval-Augmented Generation...")
(var messages (conv .get_context {^max_tokens 4000}))
```

### 4. Tool Registry (`tools.nim`)

**Tool Definition:**
```nim
type
  ToolParameter* = object
    name*: string
    type_str*: string  # "string", "number", "boolean", "object", "array"
    description*: string
    required*: bool

  ToolDefinition* = object
    name*: string
    description*: string
    parameters*: seq[ToolParameter]
    handler*: proc(args: Table[string, Value]): Value

  ToolRegistry* = ref object
    tools*: Table[string, ToolDefinition]

proc register_tool*(registry: ToolRegistry, tool: ToolDefinition)
proc execute_tool*(registry: ToolRegistry, name: string, args: Value): Value
proc to_openai_tools*(registry: ToolRegistry): seq[Table[string, Value]]
```

**Gene API:**
```gene
(var tools (ai/tools/registry))

(tools .register {
  ^name "get_weather"
  ^description "Get current weather for a location"
  ^parameters [
    {^name "location" ^type "string" ^description "City name" ^required true}
  ]
  ^handler (fn [args]
    (var location args/location)
    {^temperature 72 ^condition "sunny" ^location location}
  )
})

# When LLM requests tool call:
(var result (tools .execute "get_weather" {^location "San Francisco"}))
```

### 5. Streaming Handler (`streaming.nim`, optional)

**SSE Support:**
```nim
type
  SSEWriter* = ref object
    response*: ptr HttpResponse  # From genex/http

  StreamingCallback* = proc(chunk: string)

proc new_sse_writer*(response: ptr HttpResponse): SSEWriter
proc write_event*(writer: SSEWriter, data: string, event = "message")
proc write_done*(writer: SSEWriter)
proc stream_llm_response*(client: OpenAIClient, messages: seq[Message],
                          callback: StreamingCallback)
```

**Gene API:**
```gene
(fn handle_chat [req]
  (var sse (ai/streaming/sse_writer req))

  (ai/stream_chat messages {
    ^on_token (fn [token]
      (sse .write token)
    )
    ^on_done (fn []
      (sse .done)
    )
  })
)
```

### 6. RAG Pipeline (`rag.nim`)

**High-Level API:**
```nim
type
  RAGConfig* = object
    vectordb*: QdrantClient
    embedding_client*: OpenAIClient
    collection*: string
    top_k*: int

  RAGPipeline* = ref object
    config*: RAGConfig

  RAGResult* = object
    answer*: string
    sources*: seq[SearchResult]

proc new_rag_pipeline*(config: RAGConfig): RAGPipeline
proc ingest*(pipeline: RAGPipeline, documents: seq[string])
proc query*(pipeline: RAGPipeline, question: string): RAGResult
```

**Gene API:**
```gene
(var rag (ai/rag/pipeline {
  ^vectordb qdrant
  ^embedding_model "text-embedding-3-small"
  ^collection "documents"
  ^top_k 5
}))

# Ingest documents
(rag .ingest chunks)

# Query with RAG
(var result (rag .query "What is the main topic?"))
(println "Answer:" result/answer)
(println "Sources:" result/sources)
```

## Data Flow: Complete RAG Agent

```
1. User uploads PDF via HTTP POST
   │
   ▼
2. Document Processor extracts text, chunks
   │
   ▼
3. Embedding Service generates vectors for chunks
   │
   ▼
4. Vector DB stores chunks + vectors
   │
   ▼
5. User sends query via chat
   │
   ▼
6. Embedding Service generates query vector
   │
   ▼
7. Vector DB returns similar chunks
   │
   ▼
8. Conversation Manager builds context with retrieved chunks
   │
   ▼
9. LLM generates response with context
   │
   ▼
10. Streaming Handler sends SSE tokens to frontend (optional)
```

## Error Handling Strategy

- **External tool missing**: Check at startup, provide clear error message
- **Network failures**: Retry with exponential backoff, surface error to user
- **Token limits exceeded**: Truncate conversation history, warn user
- **Tool execution errors**: Catch and format as tool error response to LLM

## Security Considerations

1. **API Keys**: Never log, always from env vars or explicit secure config
2. **Document Uploads**: Validate file types, size limits, sanitize filenames
3. **Tool Execution**: Sandboxed execution, no arbitrary code eval
4. **Vector DB Access**: Support authentication, TLS connections

## Testing Strategy

1. **Unit Tests**: Each module in isolation with mocked dependencies
2. **Integration Tests**: Mock HTTP server for Qdrant, mock LLM responses
3. **Example Scripts**: `examples/ai/` with documented usage patterns
4. **CI/CD**: All tests run offline, no network dependencies
