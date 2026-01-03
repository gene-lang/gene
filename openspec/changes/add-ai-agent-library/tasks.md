# add-ai-agent-library Tasks

## Phase 1: Foundation & Document Processing

### 1.1 Module Scaffolding
- [x] Create new `src/genex/ai/` submodules for agent features
- [x] Update `genex/ai.nim` and `genex/ai/ai.nim` to export agent-library modules
- [x] Ensure `genex/ai` submodules are included in the build configuration

### 1.2 Document Processing - PDF
- [x] Implement `extract_pdf` using a configured external tool or API
- [x] Add graceful error handling when the configured extractor is unavailable
- [ ] Implement page-by-page extraction with metadata
- [x] Create `DocumentChunk` type with metadata fields
- [ ] Write unit tests with sample PDF fixtures

### 1.3 Document Processing - Images (Optional)
- [x] Implement `extract_image` using a configured external tool or API
- [x] Add graceful error handling when the configured extractor is unavailable
- [ ] Write unit tests with sample image fixtures

### 1.4 Text Chunking
- [x] Implement `ChunkStrategy` enum (fixed, sentence, paragraph, recursive)
- [x] Implement fixed-size chunking with overlap
- [x] Implement sentence-based chunking
- [x] Implement recursive character splitter (LangChain-style)
- [x] Add chunk metadata (index, source, position)
- [x] Write unit tests for each chunking strategy

### 1.5 File Upload Handling
- [x] Implement `save_upload` for HTTP multipart file handling
- [x] Implement `validate_upload` for file type validation
- [x] Implement `extract_upload` for direct extraction from uploads
- [x] Add file size limits and security checks

### 1.6 Gene Bindings - Documents
- [x] Register `ai/documents/extract_pdf` native function
- [x] Register `ai/documents/extract_image` native function
- [x] Register `ai/documents/chunk` native function
- [x] Register `ai/documents/extract_and_chunk` convenience function
- [x] Register `ai/documents/save_upload` native function
- [x] Register `ai/documents/validate_upload` native function
- [x] Register `ai/documents/extract_upload` native function
- [x] Create `testsuite/ai/documents/` test files

## Phase 2: Vector Database Client

### 2.1 Qdrant Client Core
- [ ] Create `QdrantClient` type with base_url, api_key
- [ ] Implement HTTP client wrapper with JSON handling
- [ ] Implement `new_qdrant_client` constructor
- [ ] Add connection validation / health check

### 2.2 Collection Operations
- [ ] Implement `create_collection` with dimension and distance metric
- [ ] Implement `delete_collection`
- [ ] Implement `list_collections`
- [ ] Implement `get_collection_info`

### 2.3 Vector Operations
- [ ] Create `VectorPoint` type with id, vector, payload
- [ ] Implement `upsert` for single and batch points
- [ ] Implement `search` with vector and filter support
- [ ] Implement `delete_points` by id or filter
- [ ] Create `SearchResult` type with score and payload

### 2.4 Error Handling
- [ ] Define Qdrant-specific exception types
- [ ] Implement retry logic with exponential backoff
- [ ] Handle connection errors gracefully
- [ ] Parse and surface Qdrant error responses

### 2.5 Gene Bindings - Vector DB
- [ ] Register `ai/vectordb/connect` native function
- [ ] Register collection methods on QdrantClient class
- [ ] Register vector operation methods
- [ ] Create `testsuite/ai/vectordb/` test files with mock server

## Phase 3: Conversation Management

### 3.1 Message Types
- [ ] Create `MessageRole` enum (system, user, assistant, tool)
- [ ] Create `Message` type with role, content, tool_call fields
- [ ] Create `ToolCall` type for function calling
- [ ] Implement JSON serialization for OpenAI format

### 3.2 Conversation Object
- [ ] Create `Conversation` type with message list
- [ ] Implement `add_message` method
- [ ] Implement `get_messages` with optional filters
- [ ] Implement `clear` and `reset` methods

### 3.3 Context Window Management
- [ ] Implement approximate token counting (word-based)
- [ ] Implement `get_context` with token limit
- [ ] Implement sliding window truncation
- [ ] Preserve system message during truncation

### 3.4 Persistence (Optional)
- [ ] Implement in-memory storage (default)
- [ ] Implement file-based JSON persistence
- [ ] Add conversation serialization/deserialization

### 3.5 Gene Bindings - Conversation
- [ ] Register `ai/conversation/new` constructor
- [ ] Register message manipulation methods
- [ ] Register context retrieval methods
- [ ] Create `testsuite/ai/conversation/` test files

## Phase 4: Tool/Function Calling

### 4.1 Tool Definition
- [ ] Create `ToolParameter` type with name, type, description
- [ ] Create `ToolDefinition` type with name, description, parameters, handler
- [ ] Implement JSON schema generation for OpenAI tools format
- [ ] Validate tool definitions on registration

### 4.2 Tool Registry
- [ ] Create `ToolRegistry` type with tool storage
- [ ] Implement `register_tool` method
- [ ] Implement `get_tool` method
- [ ] Implement `list_tools` method
- [ ] Implement `to_openai_tools` for API requests

### 4.3 Tool Execution
- [ ] Implement `execute_tool` with argument parsing
- [ ] Handle missing required arguments
- [ ] Handle type coercion for arguments
- [ ] Capture and format execution errors
- [ ] Return results as Gene values

### 4.4 Integration with LLM Response
- [ ] Parse tool_calls from LLM response
- [ ] Execute requested tools
- [ ] Format tool results for follow-up message
- [ ] Handle multiple tool calls in sequence

### 4.5 Gene Bindings - Tools
- [ ] Register `ai/tools/registry` constructor
- [ ] Register `register` method with handler callback
- [ ] Register `execute` method
- [ ] Create `testsuite/ai/tools/` test files

## Phase 5: Streaming Support (Optional)

### 5.1 SSE Writer
- [ ] Create `SSEWriter` type wrapping HTTP response
- [ ] Implement `write_event` with data and event type
- [ ] Implement `write_done` for stream termination
- [ ] Handle connection errors gracefully

### 5.2 LLM Streaming Integration
- [ ] Create `StreamingCallback` type for token handlers
- [ ] Implement streaming wrapper for OpenAI client
- [ ] Handle partial JSON in streaming responses
- [ ] Accumulate and parse tool calls from stream

### 5.3 Gene Bindings - Streaming
- [ ] Register `ai/streaming/sse_writer` constructor
- [ ] Register write methods on SSEWriter
- [ ] Register `ai/stream_chat` with callbacks
- [ ] Create streaming example in `examples/ai/`

## Phase 6: RAG Pipeline

### 6.1 Pipeline Configuration
- [ ] Create `RAGConfig` type with vectordb, embedding, collection
- [ ] Create `RAGPipeline` type with config
- [ ] Implement `new_rag_pipeline` constructor
- [ ] Validate configuration on creation

### 6.2 Document Ingestion
- [ ] Implement `ingest` method accepting chunks
- [ ] Generate embeddings for each chunk
- [ ] Store vectors with chunk metadata in Qdrant
- [ ] Handle batch processing for large document sets
- [ ] Add progress reporting for ingestion

### 6.3 Query Processing
- [ ] Implement `query` method
- [ ] Generate embedding for query
- [ ] Search vector DB for similar chunks
- [ ] Format retrieved chunks as context
- [ ] Return sources with answer

### 6.4 Advanced Features (Optional)
- [ ] Implement query expansion
- [ ] Implement re-ranking of results
- [ ] Add source attribution formatting
- [ ] Add configurable retrieval strategies

### 6.5 Gene Bindings - RAG
- [ ] Register `ai/rag/pipeline` constructor
- [ ] Register `ingest` method
- [ ] Register `query` method
- [ ] Create `testsuite/ai/rag/` test files

## Phase 7: Integration & Examples

### 7.1 Agent Controller
- [ ] Create high-level `Agent` type combining all modules
- [ ] Implement conversation loop with tool calling
- [ ] Implement RAG-augmented responses
- [ ] Add streaming response support

### 7.2 Example Applications
- [ ] Create `examples/ai/simple_chat.gene` - basic conversation
- [ ] Create `examples/ai/tool_agent.gene` - function calling demo
- [ ] Create `examples/ai/rag_agent.gene` - document Q&A
- [ ] Create `examples/ai/streaming_chat.gene` - SSE streaming

### 7.3 Frontend Integration Example
- [ ] Create `example-projects/ai_agent_app/` directory
- [ ] Create React frontend with chat UI
- [ ] Create Gene backend with all agent features
- [ ] Document API endpoints and usage

## Phase 8: Documentation & Polish

### 8.1 API Documentation
- [ ] Document all public types and functions
- [ ] Add doc comments to Nim source
- [ ] Create `docs/agent-library.md` user guide

### 8.2 Security Documentation
- [ ] Document API key handling best practices
- [ ] Document input validation recommendations
- [ ] Add security notes to examples

### 8.3 Testing & CI
- [ ] Ensure all tests pass offline
- [ ] Add mock servers for integration tests
- [ ] Validate with `openspec validate add-ai-agent-library --strict`

### 8.4 Final Review
- [ ] Code review for security issues
- [ ] Performance profiling for hot paths
- [ ] Final documentation review
