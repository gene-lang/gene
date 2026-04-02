# 16. Compile-Time Evaluation (`comptime`)

## 16.1 Overview

`(comptime ...)` blocks run during compilation, before bytecode generation. They are most useful for choosing which definitions or imports are emitted based on compile-time conditions.

```gene
(comptime
  (var target "mod1")
  (if (target == "mod1")
    (import a from "tests/fixtures/mod1")
  else
    (import b from "tests/fixtures/mod1")
  )
)

(println #"a=#{a}")  # prints a=1
```

At runtime, the `comptime` expression itself evaluates to `Nil`:

```gene
(do
  (var result (comptime
    (var x 42)
  ))
  (println #"result=#{result}")  # prints result=nil
)
```

Names declared inside the comptime environment exist only while the block is expanding. They do not become runtime bindings unless the block emits a definition or import.

## 16.2 Supported Expressions

### Literals

All primitive values evaluate to themselves: `Nil`, `Bool`, `Int`, `Float`, `Char`, `Bytes`, `String`, `Regex`, `Range`.

```gene
(comptime
  (var x 42)
  (var y 3.14)
  (var z "hello")
  (var ok true)
)
```

### Variable Declaration and Assignment

```gene
(comptime
  (var x 10)
  (var name: String "gene")
  (x = 20)
  (x += 5)
  (name = "gene_vm")
)
```

The type annotation syntax is accepted, but the type is ignored by the comptime evaluator. String interpolation is currently a runtime feature, so use plain strings inside comptime blocks.

Referencing an undeclared variable is a compilation error.

### Arithmetic

```gene
(comptime
  (var total (2 + (3 * 4)))
  (if (total == 14)
    (import a from "tests/fixtures/mod1")
  else
    (import b from "tests/fixtures/mod1")
  )
)

(println #"a=#{a}")  # prints a=1
```

Division between integers produces a float: `(10 / 2)` => `5.0`.

### Comparison

```gene
(comptime
  (var same_module ("mod1" == "mod1"))
  (if same_module
    (import a from "tests/fixtures/mod1")
  else
    (import b from "tests/fixtures/mod1")
  )
)

(println #"a=#{a}")  # prints a=1
```

### Logical

```gene
(comptime
  (var ok ((false || true) && (not false)))
  (if ok
    (import a from "tests/fixtures/mod1")
  else
    (import b from "tests/fixtures/mod1")
  )
)

(println #"a=#{a}")  # prints a=1
```

### Conditionals

```gene
(comptime
  (var level 7)
  (if (level > 10)
    (import a from "tests/fixtures/mod1")
  elif (level > 5)
    (import b from "tests/fixtures/mod1")
  else
    (import n from "tests/fixtures/mod1")
  )
)

(println #"b=#{b}")  # prints b=2
```

`ifel` is also supported as a fixed-arity conditional expression:

```gene
(comptime
  (var label (ifel true "enabled" "disabled"))
)
```

### Block Expressions

```gene
(comptime
  (var pick
    (do
      (var base 4)
      (base + 1)
    )
  )
  (if (pick == 5)
    (import a from "tests/fixtures/mod1")
  else
    (import b from "tests/fixtures/mod1")
  )
)

(println #"a=#{a}")  # prints a=1
```

### Environment Variables

```gene
(comptime
  (var target (get_env "GENE_SPEC_COMPTIME" "a"))
  (if (target == "a")
    (import a:selected from "tests/fixtures/mod1")
  else
    (import b:selected from "tests/fixtures/mod1")
  )
)

(println #"selected=#{selected}")  # prints selected=1 by default
```

`$env` is a synonym for `get_env` with the same `(name, default?)` behavior.

### Quoting

```gene
(comptime
  (var module_name "tests/fixtures/mod1")
  (var form `(import a from %module_name))
)
```

Quoted forms are data inside the comptime evaluator. They are not emitted automatically; current emission only happens when the evaluator directly encounters a module definition such as `(import ...)` or `(fn ...)`.

### Collections

Arrays and maps evaluate their elements recursively:

```gene
(comptime
  (var xs [1 2 (3 + 4)])
  (var m {^a 1 ^b (2 + 3)})
)
```

## 16.3 Code Emission

When the comptime evaluator directly encounters a module definition node, that node is emitted into the surrounding compilation unit.

```gene
(comptime
  (fn add_two [x] (x + 2))
)

(var answer (add_two 3))
(println #"answer=#{answer}")  # prints answer=5
```

Recognized emitted definitions:

| Definition | Example |
|---|---|
| `fn` | `(fn add [a b] (a + b))` |
| `class` | `(class Point ...)` |
| `ns` | `(ns geometry ...)` |
| `enum` | `(enum Color red green blue)` |
| `type` | `(type Alias Int)` |
| `object` | `(object Config ...)` |
| `import` | `(import * from "module")` |
| `interface` | `(interface Printable ...)` |
| `implement` | `(implement ...)` |
| `$dep` | `($dep "path")` |

Expressions such as `var`, `if`, `do`, arithmetic, collections, and quotes are evaluated during expansion but are not emitted. Unsupported expressions cause a compilation error.

## 16.4 Pipeline Integration

Comptime expansion occurs before module variable predeclaration and type checking:

1. Parse source to AST
2. Expand comptime blocks and emit definitions
3. Predeclare module variables
4. Normalize and type-check
5. Compile to bytecode

Emitted definitions are processed by the normal compilation pipeline.

## 16.5 Use Cases

### Conditional Imports

```gene
(comptime
  (var target ($env "GENE_SPEC_TARGET" "mod1"))
  (if (target == "mod1")
    (import a:selected from "tests/fixtures/mod1")
  else
    (import b:selected from "tests/fixtures/mod1")
  )
)

(println #"selected=#{selected}")  # prints selected=1 by default
```

### Conditional Definition Selection

```gene
(comptime
  (var flavor "fast")
  (if (flavor == "fast")
    (fn selected_mode [] "fast")
  else
    (fn selected_mode [] "safe")
  )
)

(var mode (selected_mode))
(println #"mode=#{mode}")  # prints mode=fast
```

---

## Potential Improvements

- No user-defined function calls inside comptime. Only the built-in comptime forms, operators, and `$env` / `get_env` are available.
- No loops: `while`, `for`, and `loop` are not supported inside comptime blocks.
- No computed AST emission: quoting can build data, but there is no separate `emit` mechanism for dynamically constructed forms.
- Limited I/O: only `$env` / `get_env` are available for external input. No file reading or network access during compilation.
- No reflection: no access to types, module metadata, or compiler internals.
- No error recovery: any error in comptime halts compilation immediately.
- Emission scope: emitted definitions are injected at the comptime block's position.
