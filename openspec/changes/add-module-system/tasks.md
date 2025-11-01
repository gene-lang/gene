## 1. Implementation
- [ ] 1.1 Parse `import`/`export` forms in `parser.nim`
- [ ] 1.2 Extend `types.nim` with instructions for module ops
- [ ] 1.3 Emit module instructions in `compiler.nim`
- [ ] 1.4 Implement loader, resolution, and caching in `vm.nim`
- [ ] 1.5 Persist module metadata in `gir.nim`
- [ ] 1.6 Add tests in `tests/test_module.nim` and `testsuite/`
- [ ] 1.7 Update docs: `docs/IMPLEMENTATION_STATUS.md`, `docs/architecture.md`
- [ ] 1.8 Validate change: `openspec validate add-module-system --strict`

## 2. Rollout
- [ ] 2.1 Backward-compat review (temporary feature flag if needed)
- [ ] 2.2 Bench impact on cold start and steady-state
- [ ] 2.3 Land behind PR with green tests

