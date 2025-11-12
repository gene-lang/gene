## ADDED Requirements

### Requirement: Load Local LLM Models
Gene MUST expose a `genex/llm/load_model` function that loads a local GGUF (llama.cpp-compatible) model and returns an opaque Model handle.

#### Scenario: Successful load
- **GIVEN** `genex/llm` is imported and the GGUF path exists
- **WHEN** `(genex/llm/load_model "./phi-2.q4.gguf" {^context 2048 ^threads 4})` is called
- **THEN** it returns a Model handle that can be passed to other `genex/llm` APIs
- **AND** the handle retains the model in memory until released by the GC/finalizer

#### Scenario: Missing file
- **WHEN** `load_model` receives a non-existent path
- **THEN** it raises a Gene exception that includes the failing path

### Requirement: Create Sessions from Models
Gene MUST provide `(Model .new_session opts)` that establishes an inference context (kv cache) derived from a loaded Model.

#### Scenario: Default session
- **GIVEN** a Model handle
- **WHEN** `.new_session` is called without options
- **THEN** it returns a Session handle ready for inference with default context length and sampling params

#### Scenario: Explicit context length
- **WHEN** `.new_session` receives `{^context 1024}`
- **THEN** the resulting session enforces that context length or throws if unsupported by the model

### Requirement: Run LLM Inference
Gene MUST provide `(Session .infer prompt [^max_tokens .. ^temperature .. ^timeout ..])` that produces a completion map synchronously.

#### Scenario: Basic completion
- **WHEN** `.infer` is called with a string prompt
- **THEN** it blocks until inference finishes and returns `{^text <string> ^tokens [..] ^finish_reason :stop}`

#### Scenario: Timeout / cancellation
- **WHEN** `.infer` is invoked with `^timeout` or `^max_tokens 0`
- **THEN** inference stops early and the return map sets `^finish_reason :cancelled`
