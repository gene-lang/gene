## ADDED Requirements

### Requirement: Expose `genex/llm` capability
Gene MUST add a `genex/llm` namespace exporting the `load_model` function plus the `Model` and `Session` classes used by the rest of the API.

#### Scenario: Namespace exports
- **GIVEN** `(import genex/llm)` succeeds
- **WHEN** Gene code looks up `genex/llm/load_model`, `genex/llm/Model`, or `genex/llm/Session`
- **THEN** it finds callable handles that can be invoked via `(genex/llm/load_model ...)`, `(new genex/llm/Model ...)` is disallowed, and methods are invoked with `(model .new_session ...)` / `(session .infer ...)`

#### Scenario: Opaque handles
- **WHEN** Gene code inspects a Model or Session instance
- **THEN** it can only interact through the provided methods and read-only props; there is no direct access to llama.cpp pointers or secrets

### Requirement: Load Local LLM Models
Gene MUST expose a `genex/llm/load_model` function that loads a local GGUF (llama.cpp-compatible) model and returns an opaque `Model` handle.

#### Scenario: Successful load with options
- **GIVEN** the GGUF path exists
- **WHEN** `(genex/llm/load_model "./phi-2.q4.gguf" {^context 4096 ^threads 4 ^gpu_layers 2 ^disable_mmap true ^mlock true})` is called
- **THEN** it returns a Model handle configured with those options, clamping `^context` to ≥256 tokens and `^threads` to ≥1, defaulting unspecified keys to `^context 2048`, `^threads cpu_count`, `^gpu_layers 0`, `^disable_mmap false`, and `^mlock false`
- **AND** the Model remains valid until `Model.close` is called

#### Scenario: Missing file
- **WHEN** `load_model` receives a non-existent path without `^allow_missing true`
- **THEN** it raises a Gene exception that includes the failing path

### Requirement: Model lifecycle
Gene MUST let callers close models explicitly and prevent operations on released handles.

#### Scenario: Closing requires idle sessions
- **WHEN** `(model .close)` is called while sessions created from that model are still open
- **THEN** Gene raises an exception explaining that all sessions must be closed before the model can be released

#### Scenario: Closed models reject use
- **WHEN** `(model .close)` succeeds
- **THEN** subsequent `(model .new_session ...)` invocations raise “model has been closed,” ensuring callers cannot reuse freed native state

### Requirement: Create Sessions from Models
Gene MUST provide `(Model .new_session opts)` that establishes an inference context derived from a loaded Model, applying sampling defaults that future inferences can override.

#### Scenario: Default session
- **GIVEN** a Model handle
- **WHEN** `.new_session` is called without options
- **THEN** it returns a Session handle whose context length, batch size (≤ context), thread count, seed, `^temperature 0.7`, `^top_p 0.9`, `^top_k 40`, and `^max_tokens 256` defaults are stored for later inference

#### Scenario: Context validation
- **WHEN** `.new_session` receives `{^context 8192}`
- **THEN** the runtime either creates a session with that context if supported or raises an exception clearly stating that the requested context exceeds the loaded model’s capability

### Requirement: Session lifecycle
Gene MUST let callers close sessions explicitly and reject reuse once the session has been released.

#### Scenario: Closing a session
- **WHEN** `(session .close)` is called
- **THEN** the underlying llama.cpp context is freed
- **AND** any later `(session .infer ...)` call fails with “LLM session has been closed”

### Requirement: Run LLM Inference
Gene MUST provide `(Session .infer prompt opts?)` that produces a completion map synchronously and rejects unsupported options.

#### Scenario: Basic completion
- **WHEN** `.infer` is called with a string prompt
- **THEN** it blocks until inference finishes and returns `{^text <string> ^tokens [<string> ...] ^finish_reason <symbol> ^latency_ms <int>}`
- **AND** `^finish_reason` MUST be one of `:stop`, `:length`, `:cancelled`, or `:error`

#### Scenario: Per-call overrides
- **WHEN** `.infer` receives `{^max_tokens 64 ^temperature 0.5 ^top_p 0.8 ^top_k 20 ^seed 1337}`
- **THEN** those values override the session defaults for that call while other sampling parameters continue to use the session-level configuration

#### Scenario: Unsupported timeout/streaming
- **WHEN** `.infer` is invoked with `^timeout`, `^timeout_ms`, or any streaming callback argument
- **THEN** the function raises “timeout/streaming not supported for local inference yet” so callers know the option is intentionally unavailable in v1
