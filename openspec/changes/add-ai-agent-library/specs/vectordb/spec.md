# Vector Database Client Capability

## ADDED Requirements

### Requirement: Qdrant Client Connection
The system SHALL provide a client for connecting to Qdrant vector database.

#### Scenario: Connect to local Qdrant
Given a Qdrant server is running at "http://localhost:6333"
When the user calls `(ai/vectordb/connect "http://localhost:6333")`
Then the system returns a QdrantClient object
And the client is ready for operations

#### Scenario: Connect to Qdrant Cloud with API key
Given QDRANT_API_KEY environment variable is set
When the user calls `(ai/vectordb/connect "https://xyz.qdrant.io" {^api_key $env/QDRANT_API_KEY})`
Then the system returns a QdrantClient configured with authentication

#### Scenario: Handle connection failure
Given no Qdrant server is running at the specified URL
When the user calls `(ai/vectordb/connect "http://localhost:6333")`
Then the client is created but operations will fail with connection errors

### Requirement: Collection Management
The system SHALL support creating, listing, and deleting collections.

#### Scenario: Create a collection
Given a connected QdrantClient
When the user calls `(client .create_collection "documents" {^dimension 1536 ^distance :cosine})`
Then a new collection named "documents" is created
And the collection is configured for 1536-dimensional vectors with cosine distance

#### Scenario: List collections
Given a QdrantClient with existing collections
When the user calls `(client .list_collections)`
Then the system returns a list of collection names

#### Scenario: Delete a collection
Given a collection named "old_docs" exists
When the user calls `(client .delete_collection "old_docs")`
Then the collection is deleted from Qdrant

### Requirement: Vector Operations
The system SHALL support upserting, searching, and deleting vectors.

#### Scenario: Upsert vectors
Given a QdrantClient and a collection "documents"
And a list of points with id, vector, and payload
When the user calls `(client .upsert "documents" points)`
Then the points are stored in the collection

#### Scenario: Search by vector
Given a collection "documents" with stored vectors
And a query vector of the same dimension
When the user calls `(client .search "documents" query_vector {^limit 5})`
Then the system returns up to 5 SearchResult objects
And results are ordered by similarity score descending

#### Scenario: Search with filter
Given a collection with vectors and metadata payloads
When the user calls `(client .search "documents" query_vector {^limit 5 ^filter {^source "manual.pdf"}})`
Then only results matching the filter are returned

#### Scenario: Delete points by ID
Given a collection with points having known IDs
When the user calls `(client .delete_points "documents" ["id1" "id2"])`
Then the specified points are removed from the collection

### Requirement: Error Handling
The system SHALL handle Qdrant API errors gracefully.

#### Scenario: Handle collection not found
Given no collection named "nonexistent" exists
When the user calls `(client .search "nonexistent" query_vector)`
Then the system raises an exception with the Qdrant error message

#### Scenario: Handle dimension mismatch
Given a collection configured for 1536 dimensions
When the user tries to upsert a point with 768-dimensional vector
Then the system raises an exception indicating dimension mismatch
