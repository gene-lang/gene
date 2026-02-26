# Codebase Structure

**Analysis Date:** 2026-02-26

## Directory Layout

```
gene-old/
├── src/                 # Nim source code (CLI, VM, compiler, parser, stdlib, extensions)
│   ├── commands/        # CLI command handlers (`run`, `eval`, `compile`, etc.)
│   ├── gene/            # Core language runtime internals
│   └── genex/           # Optional extension namespaces (http, db, ai, llm, etc.)
├── tests/               # Nim unittest-based test files and fixtures
├── testsuite/           # Black-box Gene program test suite and shell runners
├── docs/                # Architecture/design/performance notes
├── examples/            # Gene language examples
├── example-projects/    # Small sample applications/libraries using Gene
├── benchmarks/          # Performance micro/macro benchmarks
├── scripts/             # Utility scripts (profiling, model download, benchmark helpers)
├── tools/               # Extra tooling (llama.cpp submodule, nginx config, vscode extension)
├── openspec/            # Spec proposals and change tracking
├── gene.nimble          # Nimble project manifest and tasks
├── nim.cfg              # Compiler/runtime build flags
└── README.md            # Project overview and usage
```

## Directory Purposes

**src/**
- Purpose: Main implementation code
- Contains: Nim source files (`*.nim`) for runtime and tooling
- Key files: `src/gene.nim`, `src/gene/vm.nim`, `src/gene/compiler.nim`, `src/gene/parser.nim`
- Subdirectories:
  - `src/commands/` command modules
  - `src/gene/` core internals (types, vm, compiler submodules, stdlib)
  - `src/genex/` external-facing extension modules

**tests/**
- Purpose: Unit/integration tests executed via Nim compiler
- Contains: `test_*.nim`, helpers, fixtures, extension build artifacts for tests
- Key files: `tests/helpers.nim`, `tests/test_basic.nim`, `tests/test_parser.nim`
- Subdirectories: `tests/fixtures/` for sample modules/files/test data

**testsuite/**
- Purpose: End-to-end language behavior validation via `.gene` programs
- Contains: category folders (`basics/`, `oop/`, `stdlib/`, etc.) and runners
- Key files: `testsuite/run_tests.sh`, category-specific `run_tests.sh` scripts

**docs/**
- Purpose: Design docs, architecture notes, and implementation status/context
- Contains: markdown specs and design deep dives
- Key files: `docs/architecture.md`, `docs/performance.md`, `docs/README.md`

**openspec/**
- Purpose: Structured spec-change workflow docs
- Contains: active changes and spec deltas
- Key files: `openspec/AGENTS.md`, `openspec/project.md`, `openspec/changes/*`

## Key File Locations

**Entry Points:**
- `src/gene.nim`: CLI main entry and command dispatch
- `src/commands/run.nim`: primary file execution path
- `src/commands/eval.nim`: inline/stdi n evaluation path

**Configuration:**
- `gene.nimble`: package metadata, build and test tasks
- `nim.cfg`: compile/link/runtime defaults for Nim builds
- `.github/workflows/build-and-test.yml`: CI pipeline

**Core Logic:**
- `src/gene/parser.nim`: source reader/parser
- `src/gene/compiler.nim`: bytecode emission
- `src/gene/vm.nim`: bytecode execution engine
- `src/gene/gir.nim`: serialized compilation cache format

**Testing:**
- `tests/`: Nim unittest suite
- `testsuite/`: black-box language tests
- `tests/helpers.nim`: shared test harness macros/helpers

**Documentation:**
- `README.md`: onboarding and command overview
- `docs/`: architecture/performance/design docs
- `CLAUDE.md` (aliased by `AGENTS.md`): project-specific agent notes

## Naming Conventions

**Files:**
- `snake_case.nim` for most core/runtime files (`type_checker.nim`, `runtime_helpers.nim`)
- command files use simple command names (`run.nim`, `eval.nim`, `compile.nim`)
- tests use `test_*.nim`

**Directories:**
- lowercase names; mostly snake_case for multiword directories (`example-projects`, `known_issues`)
- category-like directories for testsuite (`control_flow`, `callable_instances`)

**Special Patterns:**
- `src/gene/compiler/*.nim` splits compiler by form/concern
- `src/gene/vm/*.nim` splits VM behavior by subsystem and include targets
- testsuite files use numeric prefixes (`1_*.gene`, `2_*.gene`) to preserve execution order

## Where to Add New Code

**New Language Feature (parser/compiler/vm):**
- Parser updates: `src/gene/parser.nim`
- Compiler emission logic: `src/gene/compiler.nim` or `src/gene/compiler/*.nim`
- VM instruction semantics: `src/gene/vm.nim` and/or `src/gene/vm/*.nim`
- Tests: `tests/test_*.nim` + relevant `testsuite/<category>/`

**New CLI Command:**
- Implementation: `src/commands/<command>.nim`
- Registration: `src/gene.nim`
- Tests: add/extend command-focused tests under `tests/`

**New Extension Namespace:**
- Implementation: `src/genex/<feature>.nim`
- Registration hooks: extension init in module and VM init path
- Tests: create focused tests in `tests/` and optionally examples in `examples/`

**Documentation Changes:**
- Architecture/runtime docs: `docs/`
- Spec/proposal work: `openspec/changes/...`

## Special Directories

**build/**
- Purpose: generated artifacts (GIR cache, built extension libs)
- Source: produced by compile/run/build tasks
- Committed: no (gitignored)

**bin/**
- Purpose: compiled executable output (`bin/gene`)
- Source: Nim build outputs
- Committed: no (gitignored)

**tools/llama.cpp/**
- Purpose: submodule dependency for local LLM runtime
- Source: git submodule
- Committed: submodule reference tracked

---
*Structure analysis: 2026-02-26*
*Update when directory structure changes*
