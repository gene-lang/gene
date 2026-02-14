## 1. OpenSpec
- [x] 1.1 Define formatter behavior with `examples/full.gene` as canonical style oracle.
- [x] 1.2 Validate proposal with `openspec validate rewrite-gene-fmt-golden-style --strict`.

## 2. Implementation
- [ ] 2.1 Implement token-level formatter in `src/gene/formatter.nim` with shebang/comment/blank-line preservation.
- [ ] 2.2 Implement `gene fmt` command (`src/commands/fmt.nim`) with in-place and `--check` modes.
- [ ] 2.3 Wire command registration in `src/gene.nim` and help text updates.
- [ ] 2.4 Ensure no trailing whitespace and deterministic output.

## 3. Validation
- [ ] 3.1 Build with `PATH=$HOME/.nimble/bin:$PATH nimble build`.
- [ ] 3.2 Add/refresh `testsuite/fmt/` tests, including golden-style check for `examples/full.gene`.
- [ ] 3.3 Run formatter tests and `bin/gene fmt examples/full.gene --check`.
- [ ] 3.4 Run `./testsuite/run_tests.sh`.
