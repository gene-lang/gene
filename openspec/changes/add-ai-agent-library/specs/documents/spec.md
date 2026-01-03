# Document Processing Capability

## ADDED Requirements

### Requirement: PDF Text Extraction
The system SHALL extract text content from PDF files using a configured external extractor (CLI or API).

#### Scenario: Extract text from a valid PDF
Given a PDF file exists at "test.pdf"
When the user calls `(ai/documents/extract_pdf "test.pdf")`
Then the system returns a list of strings, one per page
And each string contains the extracted text content

#### Scenario: Handle missing pdftotext tool
Given the configured PDF extractor is not available
When the user calls `(ai/documents/extract_pdf "test.pdf")`
Then the system raises an exception with message "PDF extractor not available."

#### Scenario: Handle non-existent PDF file
Given no file exists at "missing.pdf"
When the user calls `(ai/documents/extract_pdf "missing.pdf")`
Then the system raises an exception indicating the file was not found

### Requirement: Image OCR Extraction
The system SHALL extract text from images using a configured external OCR extractor (CLI or API).

#### Scenario: Extract text from a valid image
Given an image file exists at "document.png"
When the user calls `(ai/documents/extract_image "document.png")`
Then the system returns a string containing the OCR-extracted text

#### Scenario: Handle missing tesseract tool
Given the configured OCR extractor is not available
When the user calls `(ai/documents/extract_image "document.png")`
Then the system raises an exception with message "OCR extractor not available."

### Requirement: Text Chunking
The system SHALL split text into chunks using configurable strategies.

#### Scenario: Fixed-size chunking
Given a text string of 1000 characters
When the user calls `(ai/documents/chunk text {^strategy :fixed ^size 200 ^overlap 20})`
Then the system returns a list of DocumentChunk objects
And each chunk has approximately 200 characters
And consecutive chunks overlap by 20 characters

#### Scenario: Sentence-based chunking
Given a text string with multiple sentences
When the user calls `(ai/documents/chunk text {^strategy :sentence ^size 3})`
Then the system returns chunks where each contains up to 3 complete sentences

#### Scenario: Recursive chunking
Given a text string with paragraphs and sections
When the user calls `(ai/documents/chunk text {^strategy :recursive ^size 500})`
Then the system splits on paragraph boundaries first, then sentence boundaries
And no chunk exceeds 500 characters

### Requirement: Combined Extract and Chunk
The system SHALL provide a convenience function to extract and chunk in one call.

#### Scenario: Extract and chunk PDF
Given a PDF file exists at "document.pdf"
When the user calls `(ai/documents/extract_and_chunk "document.pdf" {^strategy :recursive ^size 500})`
Then the system extracts text from the PDF
And chunks the text using the recursive strategy
And returns a list of DocumentChunk objects with source metadata

### Requirement: File Upload Handling
The system SHALL provide helpers for handling file uploads from HTTP requests.

#### Scenario: Save uploaded file
Given an HTTP request with multipart form data containing a PDF file
When the user calls `(ai/documents/save_upload req "uploads/")`
Then the file is saved to the uploads directory
And the function returns the saved file path

#### Scenario: Validate file type
Given an HTTP request with an uploaded file
When the user calls `(ai/documents/validate_upload req {^allowed_types ["pdf" "png" "jpg"]})`
Then the system checks the file extension and MIME type
And raises an exception if the file type is not allowed

#### Scenario: Extract from upload directly
Given an HTTP request with an uploaded PDF
When the user calls `(ai/documents/extract_upload req)`
Then the system saves the file temporarily
And extracts text from the PDF
And returns the extracted text
