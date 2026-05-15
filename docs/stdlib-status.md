# Standard Library Status

Reader: Gene contributors deciding whether the current library surface is enough
for a concrete project.

Post-read action: choose whether to build with the current libraries, or pick the
next library gap to close.

## Summary

Gene can now support useful backend and tooling programs: scripts, file
processors, HTTP services behind a proxy, database-backed services, raw TCP/UDP
tools, JSON workflows, and small cryptographic utilities.

The largest remaining gaps are not "can it run code?" gaps. They are ecosystem
gaps: TLS sockets, richer binary data handling, production auth/security helpers,
common data formats, file watching, richer date/time APIs, and cross-platform
process parity.

## Status Labels

- Ready: usable for ordinary programs with tests and documented behavior.
- Beta: usable, but the API or platform coverage may still change.
- Partial: useful pieces exist, but important workflows still need custom code.
- Missing: no first-class Gene library surface yet.

## Current Status

| Area | Status | Current Surface | Main Gaps |
| --- | --- | --- | --- |
| Core data and control | Ready | Strings, arrays, maps, assertions, regex, basic math, JSON values, functions, classes, enums, tuples, async, and actors. | Naming consistency and convenience coverage are uneven across strings, maps, arrays, and functional helpers. |
| Files, directories, and paths | Ready | File read/write/append/existence/delete/copy/move/size/metadata, directory create/list/entry/walk/delete, and path join/split/normalize/relative/base helpers. | Globbing, permissions, symlink mutation, temp file helpers, lock files, and file watching. |
| Console and basic I/O | Ready | Print, println, stderr output, stdin reading, flush, and signal-aware console behavior. | Higher-level terminal UI helpers, ANSI styling, progress bars, and interactive prompts. |
| System and processes | Beta | Command execution, shell execution, one-shot process run with stdout/stderr/input/env/cwd/timeout, executable lookup, managed child processes, stdin/stdout/stderr reads, signals, shutdown, cwd, OS, and architecture. | Windows parity, process groups, PTY support, shell pipeline helpers, richer signal model, and resource limits. |
| Environment and CLI context | Partial | Environment reads/writes/checks and command argument access. | Dotenv loading, typed config, config precedence, and argument parsing helpers. |
| Date and time | Partial | Today/yesterday/tomorrow/now constructors, date/datetime accessors, display, and epoch conversion. | Parsing, formatting templates, arithmetic, durations, monotonic clocks, timezone conversion, and calendar helpers. |
| Bytes and binary data | Partial | Runtime bytes values exist, strings expose byte helpers, and base64 helpers exist. | First-class Bytes construction, mutation, slicing, comparison, binary I/O, endian helpers, and buffer APIs. |
| JSON and Gene serialization | Ready | JSON parse/stringify plus Gene-aware JSON serialize/deserialize. | Streaming JSON, JSON schema helpers, canonicalization, and broader format support such as CSV, TOML, YAML, MessagePack, and CBOR. |
| HTTP client and server | Beta | Basic HTTP client verbs, simple HTTP server, and actor-backed server mode for bounded concurrent request handling. | Router/middleware helpers, request validation, response helpers, cookie/session utilities, multipart support, SSE/WebSocket public story, and direct edge hardening. |
| Databases | Beta | SQLite, PostgreSQL, and MySQL/MariaDB clients with query, exec, and transaction operations. | Connection pooling, prepared statement lifecycle, typed rows, migrations, schema introspection, named parameters, and consistent error taxonomy. |
| Raw networking | Beta | TCP client/server sockets and UDP datagrams. | TLS sockets, DNS helpers, proxy support, backpressure controls, and higher-level protocols. |
| Crypto | Beta | Hashing, HMAC, random bytes/hex, and constant-time comparison. | Password hashing, key derivation, asymmetric signing/encryption, certificates, JWT/JWS/JWE, and streaming digest APIs. |
| HTML and web helpers | Partial | HTML tag generation. | Templates, escaping policy documentation, sanitization, static asset helpers, forms, and CSS integration. |
| Logging and observability | Partial | Structured logging exists as an extension. | Core prelude integration, log configuration, metrics, traces, health checks, and OpenTelemetry export. |
| AI and LLM integrations | Experimental | Provider-facing AI extension modules and example chat integration. | Stable public API, provider compatibility matrix, streaming guarantees, tool-call lifecycle, retries, rate limiting, and eval harnesses. |
| Testing helpers | Partial | Internal and extension testing support exists. | User-facing test runner ergonomics, assertions library polish, fixtures, mocks, temp resources, and coverage reporting. |

## What Is Practical Today

The current library set is enough for:

- CLI tools that read files, call subprocesses, process JSON, and write reports.
- Local automation scripts on Unix/macOS.
- HTTP services deployed behind a production reverse proxy.
- Database-backed prototypes and internal services using SQLite, PostgreSQL, or
  MySQL/MariaDB.
- TCP or UDP protocol experiments and local network tools.
- Basic crypto utilities such as hashing, HMAC signing, random token generation,
  and safe equality checks.
- Actor-backed background work inside HTTP handlers.

The current library set is still awkward for:

- Direct public edge services that need first-class TLS and certificate control.
- Cross-platform system automation that must behave identically on Windows.
- Binary protocol implementations that need buffers, endian operations, and
  binary file APIs.
- Data ingestion pipelines that expect CSV, TOML, YAML, compression, and archive
  formats.
- Production apps that need auth, sessions, cookies, email, queues, cache, and
  observability without writing glue code.

## Recommended Additions

### Highest Leverage

1. TLS sockets and certificate handling.
   This unlocks secure clients, secure servers, database TLS options, and many
   higher-level protocols.

2. First-class Bytes and binary I/O.
   This supports protocol work, compression, checksums, file formats, and
   efficient request/response bodies.

3. Common data formats: CSV, TOML, YAML, and dotenv.
   These are high-frequency scripting and service configuration needs.

4. Date/time parsing, formatting, arithmetic, durations, and timezone conversion.
   Almost every real service and data pipeline needs this.

5. Filesystem globbing, temp resources, permissions, symlink helpers, and file
   watching.
   These make build tools, CLIs, dev servers, and test fixtures much easier.

### Backend Application Stack

6. HTTP routing, middleware, cookies, sessions, multipart forms, and response
   helpers.

7. Auth helpers: JWT/JWS, OAuth client flows, password hashing, secure password
   comparison, and CSRF/session helpers.

8. Cache and queue clients: Redis-compatible cache operations, pub/sub, job
   queues, retry policies, and delayed jobs.

9. Email and notification libraries: SMTP, MIME, templates, and provider-neutral
   send APIs.

10. Observability: metrics, traces, log configuration, health checks, and
    OpenTelemetry export.

### Database Maturity

11. Connection pooling and retry policies.

12. Prepared statement lifecycle helpers and named parameters.

13. Migrations, schema introspection, and fixture loading.

14. Row mapping helpers for maps, tuples, and typed records.

### Network And Protocol Ecosystem

15. Public WebSocket module wiring and documentation.

16. DNS lookup helpers, URL utilities, MIME types, and multipart parsing.

17. Compression and archives: gzip, zstd, zip, and tar.

18. Higher-level service protocols: GraphQL, OpenAPI client generation, gRPC, and
    server-sent events.

### Developer Experience

19. CLI parser with flags, subcommands, help text, env defaults, and config file
    integration.

20. User-facing test runner, fixtures, mocks, temp resources, and coverage
    reporting.

21. Formatter and lint library hooks once the language formatting contract is
    mature enough to expose.

## Suggested Priority Order

Build the next libraries in this order unless a specific product need says
otherwise:

1. Bytes and binary I/O.
2. TLS sockets and certificate handling.
3. CSV/TOML/YAML/dotenv.
4. Date/time parsing and arithmetic.
5. Filesystem glob/temp/watch helpers.
6. HTTP routing/middleware/cookies/sessions.
7. Auth/password/JWT helpers.
8. Metrics/tracing/health checks.
9. Redis/cache/queue.
10. Database pooling and migrations.

This order turns Gene from "useful for internal tools and backend prototypes"
into "reasonable for production service work" with the least wasted surface area.
