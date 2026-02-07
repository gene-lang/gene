# How Types Work in Gene Today

This document explains the current pipeline for typed Gene code:

`Source -> Parse -> Type Check -> Compile -> GIR -> Execute`

It uses `examples/sample_typed.gene` as the running example.

## Quick Run Commands

```bash
./bin/gene run examples/sample_typed.gene
./bin/gene parse examples/sample_typed.gene
./bin/gene compile --format pretty examples/sample_typed.gene
./bin/gene run --trace-instruction examples/sample_typed.gene
```

## 1. Parse Phase

Parser entry points are in `src/gene/parser.nim`.

The parser does not interpret types. It builds `Value` trees (`VkGene`, `VkArray`, `VkSymbol`, ...).

Typed params are parsed as symbols ending with `:` followed by a type expression.

Example source:

```gene
(fn add [x: Int y: Int] -> Int
  (x + y))
```

Example parse shape (`gene parse` pretty output):

```text
(fn
  add
  [
    x:
    Int
    y:
    Int
  ]
  ->
  Int
  (x
    +
    y
  )
)
```

Important detail: there is no separate `":"` token node in the AST for params. The symbol itself is `x:`.

## 2. Type Check Phase

Type checker is in `src/gene/type_checker.nim`.

`parse_and_compile*` currently constructs the checker as:

- `new_type_checker(strict = false, ...)`

So unknown type names do not fail immediately at compile time in default mode.

### Internal type representation

Compile-time types use `TypeExpr` variants, including:

- `TkAny`
- `TkNamed`
- `TkApplied`
- `TkFn`
- `TkVar`

For example:

- `Int` -> `TkNamed("Int")`
- `(Result Int String)` -> `TkApplied("Result", [Int, String])`
- `(Fn [Int] Int)` -> `TkFn(params=[Int], ret=Int)`

### Metadata attached to AST nodes

The checker stores type metadata into Gene node props using keys from `src/gene/types/type_defs.nim`:

- `__tc_param_types`
- `__tc_return_type`

`__tc_param_types` is a map by parameter name, not an array.

Example conceptual shape:

```text
__tc_param_types = { x: "Int", y: "Int" }
__tc_return_type = "Int"
```

This is recorded by `record_param_types`.

## 3. Compile Phase

Compiler is in `src/gene/compiler.nim`.

### Module-mode normalization

`gene run` compiles with `module_mode = true`.

`normalize_module_nodes` separates module definitions and top-level executable statements, synthesizing/appending `__init__` as needed.

### How typed info reaches runtime

There are two important paths:

1. Function/method parameter annotations

- At runtime, functions are materialized from AST by `to_function` in `src/gene/types/value_core.nim`.
- It reads `__tc_param_types` / `__tc_return_type` from node props.
- It populates matcher fields like `param.type_name` and `matcher.return_type_name`.
- VM argument binding then validates these through `process_args*` in `src/gene/vm/args.nim`.

2. Local variable annotations

- Compiler writes expected types into `ScopeTracker.type_expectations`.
- VM validates on variable store/assign instructions (`IkVar`, `IkVarValue`, `IkVarAssign`, `IkVarAssignInherited`).

## 4. GIR Serialization

GIR serializer is in `src/gene/gir.nim`.

Current version:

- `GIR_VERSION = 9`

Saved data includes:

- Header (`GENE`, version, ABI, hash/timestamp)
- Instructions
- Source trace tree + instruction trace indices
- Unit metadata (`kind`, `id`, `skip_return`)
- Module metadata (`module_exports`, `module_imports`, `module_types`)
- Type descriptor table (`type_descriptors`)

Notes:

- Scope tracker snapshots are serialized for nested values like function defs and scope-tracker values.
- Top-level `save_gir` currently writes empty constants/symbol tables in this path.

## 5. Runtime Execution Phase

Main VM loop is in `src/gene/vm.nim`.

### Runtime type checks for parameters

For typed params, runtime checks happen in argument processing (`src/gene/vm/args.nim`):

- `process_args_core` binds args to scope slots.
- If `matcher.has_type_annotations`, it calls `validate_type(value, param.type_name, ...)`.

So function-call validation does not rely only on `IkVar`.

### Runtime type checks for local vars

VM instruction handlers validate expected local types using `scope.tracker.type_expectations`:

- `IkVar`
- `IkVarValue`
- `IkVarAssign`
- `IkVarAssignInherited`

They call `validate_type` from `src/gene/types/runtime_types.nim`.

### `.is` checks

`.is` is implemented as native `Object.is` in `src/gene/stdlib.nim`.

It compares runtime class identity/inheritance against a class (or instance) argument.

### ADT runtime representation

`Ok/Err/Some/None` values are represented as `VkGene` values with tagged symbol types (`Ok`, `Err`, ...).

## Runtime Type Engine Today

`validate_type` currently receives expected types as strings and parses/caches them in `runtime_types.nim`.

Common primitive checks are fast due tag-based `ValueKind` detection (`Int`, `Float`, `String`, etc.).

Complex types (`Fn`, unions, applied forms) are parsed into runtime `RtType` structures and cached by string.

## What `--no-type-check` Actually Disables

`--no-type-check` disables the compile-time checker pass.

It does **not** disable runtime validator paths.

Examples:

```gene
(fn f [x: Int] x)
(f "oops")
```

- with type check on: compile-time error
- with `--no-type-check`: runtime error still occurs during arg binding

```gene
(fn g []
  (var x: Int 42)
  (x = "bad"))
(g)
```

- with `--no-type-check`: runtime error occurs via `IkVarAssign`

## Known Caveat (Current Behavior)

Top-level typed vars that are lowered into module `__init__` have a known mismatch risk between parameter slot shifting and `type_expectations` indexing.

Practical effect today: some top-level `(var x: T ...)` assignment checks may not fire at runtime when compile-time checking is disabled.

So this may pass with `--no-type-check`:

```gene
(var x: Int 42)
(x = "bad")
```

while equivalent logic inside an ordinary function does fail at runtime.

Treat this as a current implementation gap, not intended long-term semantics.

## Summary

Current system is already gradual and two-layered:

1. Compile-time checker (`TypeExpr`, non-strict by default).
2. Runtime validator (`validate_type`) on typed boundaries.

Type metadata already survives into runtime and GIR, and module type trees + descriptor tables are now present in compilation units. Runtime validation still primarily consumes string type names today; descriptor-driven runtime checks are the next architectural step.
