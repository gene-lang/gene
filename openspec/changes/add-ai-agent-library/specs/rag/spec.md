# RAG Pipeline Capability

## ADDED Requirements

### Requirement: RAG Pipeline Creation
The system SHALL provide a high-level RAG pipeline combining documents, embeddings, and vector search.

#### Scenario: Create RAG pipeline
Given a QdrantClient and embedding configuration
When the user calls:
```gene
(ai/rag/pipeline {
  ^vectordb qdrant
  ^embedding_model "text-embedding-3-small"
  ^collection "documents"
  ^top_k 5
})
```
Then the system returns a RAGPipeline object configured for the specified collection

#### Scenario: Create pipeline with custom embedding endpoint
Given a custom embedding API endpoint
When the user creates a pipeline with `{^embedding_url "http://localhost:8080/embed"}`
Then the pipeline uses the custom endpoint for embeddings

### Requirement: Document Ingestion
The system SHALL support ingesting documents into the vector database.

#### Scenario: Ingest document chunks
Given a RAGPipeline and a list of DocumentChunk objects
When the user calls `(pipeline .ingest chunks)`
Then each chunk is embedded using the configured embedding model
And the vectors with chunk metadata are stored in Qdrant

#### Scenario: Ingest with progress callback
Given a large number of chunks to ingest
When the user calls `(pipeline .ingest chunks {^on_progress (fnx [i total] ...)})`
Then the progress callback is invoked after each batch

#### Scenario: Skip duplicate documents
Given chunks with source metadata matching existing documents
When the user calls `(pipeline .ingest chunks {^skip_existing true})`
Then chunks from already-ingested sources are skipped

### Requirement: Query Processing
The system SHALL support querying with retrieval-augmented context.

#### Scenario: Simple RAG query
Given a RAGPipeline with ingested documents
When the user calls `(pipeline .query "What is the main topic?")`
Then the query is embedded
And similar chunks are retrieved from the vector database
And a RAGResult is returned with answer and sources

#### Scenario: Query with source attribution
Given a RAG query result
When the user accesses `result/sources`
Then each source includes the chunk text and metadata (page, document name)

#### Scenario: Query with custom top_k
Given a RAGPipeline configured with top_k 5
When the user calls `(pipeline .query question {^top_k 10})`
Then 10 chunks are retrieved instead of the default 5

### Requirement: Context Formatting
The system SHALL format retrieved chunks as LLM context.

#### Scenario: Format context for prompt
Given retrieved chunks from a query
When the user calls `(pipeline .format_context chunks)`
Then the system returns a formatted string suitable for LLM context
And each chunk is separated and attributed

#### Scenario: Limit context tokens
Given many retrieved chunks
When the user calls `(pipeline .format_context chunks {^max_tokens 2000})`
Then the context is truncated to fit within the token limit

### Requirement: Advanced Retrieval (Optional)
The system SHALL optionally support advanced retrieval strategies.

#### Scenario: Query expansion
Given a short query
When the user calls `(pipeline .query question {^expand_query true})`
Then the system generates query variations
And searches with multiple embeddings for better recall

#### Scenario: Re-ranking
Given initial retrieval results
When the user calls `(pipeline .query question {^rerank true})`
Then results are re-ranked using a cross-encoder or similar
And the final ranking improves relevance

### Requirement: Pipeline Integration
The system SHALL integrate with conversation and LLM for end-to-end RAG.

#### Scenario: RAG-augmented chat with OpenAI
Given a RAGPipeline, Conversation, and OpenAI client from genex/ai
When the user calls:
```gene
(ai/rag/chat pipeline conv user_message {
  ^llm openai_client
  ^model "gpt-4"
  ^stream true
})
```
Then the system retrieves relevant context
And augments the conversation with retrieved chunks
And generates a streaming response via the OpenAI API

#### Scenario: RAG-augmented chat with local LLM
Given a RAGPipeline, Conversation, and local LLM session from genex/llm
When the user calls:
```gene
(ai/rag/chat pipeline conv user_message {
  ^llm local_session
  ^stream false
})
```
Then the system retrieves relevant context
And generates a response using the local LLM

#### Scenario: RAG query without LLM
Given a RAGPipeline with ingested documents
When the user calls `(pipeline .retrieve "search query" {^top_k 5})`
Then the system returns matching chunks without generating an LLM response
And the caller can use the chunks as context for their own LLM call
