## 1. Selector Semantics
- [ ] 1.1 Confirm `void` vs `nil` behavior for all selector reads (`/`, `./`, `Selector.call`)
- [ ] 1.2 Define `/!` behavior in mid-path vs end-path

## 2. Match Locations
- [ ] 2.1 Define `SelectorMatch` representation (container + key/index + value)
- [ ] 2.2 Implement `selector/select` returning matches for supported inputs (Gene trees first)

## 3. Update & Transform APIs
- [ ] 3.1 Add `selector/set`, `selector/update`, `selector/delete`
- [ ] 3.2 Add `$update` and `$transform` user-facing helpers

## 4. HTML CSS Prototype
- [ ] 4.1 Implement `genex/html/style` module entrypoints required by `examples/html2.gene`
- [ ] 4.2 Implement minimal rule composition (`@` rule + `@*` rule-set) to apply style to matched `:BODY` nodes
- [ ] 4.3 Add tests validating selection + mutation on Gene ASTs

