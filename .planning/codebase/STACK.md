# Technology Stack

**Analysis Date:** 2026-02-26

## Languages

**Primary:**
- Nim (project targets Nim 2.x in CI, minimum `nim >= 1.4.0`) - VM, compiler, parser, CLI, stdlib, extensions under `src/`

**Secondary:**
- Gene (`*.gene`) - language examples, testsuite programs, and package manifests (`package.gene`, `examples/`, `testsuite/`)
- Bash - test and build tooling (`testsuite/run_tests.sh`, `scripts/*.sh`, `tools/build_llama_runtime.sh`)
- C/C++ - native integration surface (`src/gene/extension/gene_extension.h`, `src/genex/llm/shim/gene_llm.cpp`)
- YAML - CI workflow definitions (`.github/workflows/build-and-test.yml`)

## Runtime

**Environment:**
- Native CLI executable (`bin/gene`) built from `src/gene.nim`
- Nim runtime with ORC memory mode in optimized builds (see `nim.cfg` and `gene.nimble` `speedy` task)
- Optional async/event-loop runtime via Nim async libraries (`src/gene/vm.nim`, `src/gene/vm/async*.nim`)

**Package Manager:**
- Nimble (project manifest: `gene.nimble`)
- Lockfile: no npm/pip-style lockfile; dependency resolution is Nimble-managed

## Frameworks

**Core:**
- No web framework; custom language runtime architecture
- Nim standard libraries heavily used for parser/compiler/VM infrastructure

**Testing:**
- Nim `unittest` for unit/integration tests (`tests/test_*.nim`)
- Shell-driven black-box suite for Gene programs (`testsuite/run_tests.sh`)

**Build/Dev:**
- Nim compiler (`nim c`) and Nimble tasks (`nimble build`, `nimble test`, `nimble speedy`)
- Optional llama.cpp runtime build pipeline (`tools/build_llama_runtime.sh`)

## Key Dependencies

**Critical:**
- `db_connector` (declared in `gene.nimble`) - database connectivity used by `src/genex/sqlite.nim` and `src/genex/postgres.nim`
- Nim async stack (`asyncdispatch`, `asyncnet`, `asynchttpserver`) - async VM and HTTP extension support (`src/gene/vm.nim`, `src/genex/http.nim`)
- Nim regex package `nre` - parser/regex support in `src/gene/parser.nim`

**Infrastructure:**
- llama.cpp submodule (`tools/llama.cpp`) - optional local LLM backend used by `src/genex/llm.nim`
- GitHub Actions (`.github/workflows/build-and-test.yml`) - CI build + test execution

## Configuration

**Environment:**
- Runtime/feature env vars include `GENE_DEEP_VM_FREE`, `GENE_LLM_MODEL`, `GENE_TEST_POSTGRES_URL`, `OPENAI_API_KEY`, `OPENAI_BASE_URL`, `OPENAI_ORG`
- Package/module resolution env vars include `GENE_PACKAGE_PATH` and `GENE_WORKSPACE_PATH`

**Build:**
- `nim.cfg` contains release-mode optimization/threading flags
- `config.nims` includes local Nimble path configuration
- `gene.nimble` defines build/test/tasks and extension build commands

## Platform Requirements

**Development:**
- macOS/Linux supported in current workflow; CI runs on Ubuntu (`.github/workflows/build-and-test.yml`)
- Nim toolchain required (`nim`, `nimble`)
- Optional native dependencies:
  - PostgreSQL client libraries for postgres tests
  - `libpcre3-dev` in CI
  - CMake/toolchain for llama.cpp runtime build

**Production:**
- Distributed/used as a native executable (`bin/gene`)
- Optional extension libraries emitted into `build/` (`libsqlite.dylib`, `libpostgres.dylib`, `libhttp.dylib`)

---
*Stack analysis: 2026-02-26*
*Update after major dependency changes*
