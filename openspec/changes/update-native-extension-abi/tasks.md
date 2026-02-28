## 1. ABI Contract
- [ ] 1.1 Add a versioned extension ABI definition module (host API struct, version constant, `gene_init` proc type).
- [ ] 1.2 Add/refresh extension-facing headers/helpers to reflect the canonical ABI.
- [ ] 1.3 Add ABI version mismatch checks and deterministic error mapping.

## 2. Loader Upgrade
- [ ] 2.1 Update `load_extension` to resolve `gene_init` first.
- [ ] 2.2 Remove compatibility fallback for legacy `set_globals` + `init` exports.
- [ ] 2.3 Ensure loader returns/publishes extension namespaces consistently for both paths.
- [ ] 2.4 Add deterministic diagnostics for missing library, missing symbols, ABI mismatch, and init failure.

## 3. Genex Migration
- [ ] 3.1 Identify all modules currently requiring static VM imports.
- [ ] 3.2 Migrate those modules to be dynamic-load-ready under the new ABI (or adapter layer).
- [ ] 3.3 Remove temporary static imports from `src/gene/vm.nim` after parity is verified.
- [ ] 3.4 Keep `gene_wasm` behavior unchanged for unsupported dynamic loading.

## 4. Build and Tooling
- [ ] 4.1 Ensure extension build tasks produce required shared libraries with consistent naming/path conventions.
- [ ] 4.2 Ensure default developer workflows still provide the same extension capabilities as before.
- [ ] 4.3 Update extension documentation and examples to describe canonical ABI + compatibility behavior.

## 5. Tests
- [ ] 5.1 Add/refresh tests for `import ... ^^native` with new ABI extensions.
- [ ] 5.2 Add/refresh tests for legacy extension fallback loading.
- [ ] 5.3 Add tests for `genex/<module>` lazy load behavior after static-import removal.
- [ ] 5.4 Add tests for extension-load error diagnostics.

## 6. Validation
- [ ] 6.1 Run extension-focused test suites (`test_ext`, `test_http`, sqlite/logging coverage, relevant module tests).
- [ ] 6.2 Run `nimble test` (or documented subset if environment-gated).
- [ ] 6.3 Run `openspec validate update-native-extension-abi --strict`.
