## Why
Function definitions currently allow multiple forms (`fn`, `fnx`, `fnxx`, and unbracketed argument lists), which makes the language harder to read and remember for app developers. Requiring bracketed argument lists and removing `fnx` reduces special cases and improves consistency.

## What Changes
- **BREAKING**: Remove `fnx`, `fnx!`, and `fnxx` as function-definition forms.
- **BREAKING**: Require bracketed argument lists for `fn` in both named and anonymous forms: `(fn [args] ...)` and `(fn name [args] ...)`.
- Update parser/compiler/arg matcher to reject legacy forms and emit clear errors.
- Update docs, examples, tests, and tooling (LSP, VS Code grammar) to the new syntax.

## Impact
- Affected specs: `function-syntax` (new) and the reserved keyword list in pending `add-symbol-resolution-spec`.
- Affected code: `src/gene/compiler.nim`, `src/gene/types/value_core.nim`, `src/gene/lsp/document.nim`, `tools/vscode-extension/syntaxes/gene.tmLanguage.json`, docs/examples/tests.
