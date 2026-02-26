# External Integrations

**Analysis Date:** 2026-02-26

## APIs & External Services

**OpenAI-Compatible API:**
- OpenAI-style HTTP API via `src/genex/ai/openai_client.nim`
  - SDK/Client: Nim `httpclient`
  - Auth: `Authorization: Bearer <OPENAI_API_KEY>` header
  - Endpoints used: `/chat/completions`, `/responses`, `/embeddings` (via `src/genex/ai/bindings.nim`)

**Generic HTTP Services:**
- Arbitrary HTTP endpoints via `genex/http` extension (`src/genex/http.nim`)
  - Integration method: direct GET/POST/PUT/DELETE wrappers over Nim `httpclient`
  - Auth: caller-supplied headers map
  - Supports JSON and SSE-like response handling utilities

**Local LLM Runtime:**
- llama.cpp local inference integration (`src/genex/llm.nim`, `src/genex/llm/shim/gene_llm.cpp`)
  - Integration method: C shim + compiled static libs from `tools/build_llama_runtime.sh`
  - Model location: `GENE_LLM_MODEL` env var (or test fixture fallback in examples)

## Data Storage

**Databases:**
- SQLite through `db_connector/db_sqlite` (`src/genex/sqlite.nim`)
  - Connection: filesystem path passed to `genex/sqlite/open`
  - Client: Nim db_connector prepared statement APIs + sqlite3 stepping
- PostgreSQL through `db_connector/db_postgres` (`src/genex/postgres.nim`)
  - Connection: connection string passed to `genex/postgres/open`
  - Client: Nim db_connector APIs

**File Storage:**
- Local filesystem operations via stdlib IO namespace (`src/gene/stdlib/io.nim`)
  - No cloud object-storage provider wired by default

**Caching:**
- GIR cache on local disk (`build/*.gir`) for compilation reuse (`src/gene/gir.nim`, `src/commands/run.nim`)

## Authentication & Identity

**Auth Provider:**
- No centralized auth/identity provider in core runtime
- API-key auth only for OpenAI-compatible client integration

**OAuth Integrations:**
- None detected in core runtime

## Monitoring & Observability

**Error Tracking:**
- No external SaaS error tracker wired by default
- Errors surfaced via command output and runtime exceptions

**Analytics:**
- None detected

**Logs:**
- Local logger setup in command layer (`src/commands/base.nim`) with debug/info levels
- Optional verbose/debug output in selected modules (including AI streaming/client debug branches)

## CI/CD & Deployment

**Hosting:**
- Not an always-on service by default; this is a CLI/runtime project

**CI Pipeline:**
- GitHub Actions (`.github/workflows/build-and-test.yml`)
  - Runs build (`nimble build`), unit tests (`nimble test`), and testsuite (`testsuite/run_tests.sh`)
  - Uses Ubuntu runner and installs `libpcre3-dev`

## Environment Configuration

**Development:**
- Core vars are process env-based (`OPENAI_*`, `GENE_*` families)
- No project-level `.env.example` found in repo root
- Optional local service dependencies for database tests (`GENE_TEST_POSTGRES_URL`)

**Staging:**
- No dedicated staging profile/configuration files found

**Production:**
- Production posture depends on embedding context (CLI, extension host, or service wrapper)
- Secrets are expected via host environment variables

## Webhooks & Callbacks

**Incoming:**
- No inbound webhook receiver module detected in core CLI/runtime

**Outgoing:**
- Outbound HTTP requests to OpenAI-compatible and arbitrary HTTP endpoints
- Streaming callbacks for token/event delivery in OpenAI binding path (`src/genex/ai/streaming.nim`, `src/genex/ai/bindings.nim`)

---
*Integration audit: 2026-02-26*
*Update when adding/removing external services*
