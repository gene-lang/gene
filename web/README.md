# Gene Web REPL

An interactive browser-based REPL (Read-Eval-Print Loop) for the Gene programming language.

## Features

- **Interactive Evaluation**: Type Gene code and see results immediately
- **Persistent State**: Variables and functions persist between evaluations (like IRB)
- **Syntax Highlighting**: Visual distinction between input, output, and errors
- **Modern UI**: Clean, VS Code-inspired interface
- **Keyboard Shortcuts**:
  - `Ctrl+Enter` - Evaluate code
  - `Ctrl+L` - Clear output
  - `Ctrl+R` - Reset VM

## Usage

### Running Locally

Simply open `gene_repl.html` in a web browser:

```bash
open web/gene_repl.html
```

Or serve via HTTP server:

```bash
cd web
python3 -m http.server 8000
# Then open http://localhost:8000/gene_repl.html
```

### Examples

Try these Gene expressions in the REPL:

```gene
# Variables
(var x 42)
(var name "Gene")

# Math
(+ 1 2 3 4 5)
(* 10 (- 20 5))

# Lists
(var nums [1 2 3 4 5])
(first nums)
(length nums)

# I/O
(println "Hello" name)
(println "x =" x)

# Conditionals
(if (> x 10) "big" "small")

# Functions
(fn factorial [n]
  (if (<= n 1)
    1
    (* n (factorial (- n 1)))))

(factorial 5)

# Loops
(for n in nums
  (println "Number:" n))

# Combining features
(var total 0)
(for n in nums
  (var total (+ total n)))
(println "Sum:" total)
```

## Implementation

The current version includes a simplified Gene interpreter written in JavaScript. It supports:

- **Data Types**: Numbers, strings, booleans, lists
- **Variables**: `(var name value)`
- **Functions**: `(fn name [params] body)`
- **Control Flow**: `if`, `do`, `while`, `for`
- **Operators**: Math (`+`, `-`, `*`, `/`), comparison (`==`, `<`, `>`), logical (`and`, `or`, `not`)
- **List Operations**: `list`, `first`, `rest`, `length`
- **I/O**: `print`, `println`

## Future Work

To use the full Gene VM in the browser, we would need to:

1. **Create JavaScript-compatible implementation**:
   - Port or rewrite platform-specific code
   - Replace regex library with JS-compatible version
   - Handle file I/O differences

2. **Compile to WebAssembly**:
   - Use Emscripten to compile Nim to WASM
   - Create JavaScript bindings
   - Bundle with HTML interface

3. **Add more features**:
   - Syntax highlighting in input
   - Auto-completion
   - Code history navigation (up/down arrows)
   - Save/load sessions
   - Share code via URL

## Architecture

```
web/
├── gene_repl.html     # Main REPL interface
├── README.md          # This file
└── (future)
    ├── gene.js        # Compiled Gene VM
    ├── gene.wasm      # WASM binary
    └── gene_worker.js # Web Worker for background execution
```

## Contributing

To improve the Gene Web REPL:

1. **Enhance the interpreter**: Add missing language features
2. **Improve UI/UX**: Better syntax highlighting, themes, etc.
3. **Add examples**: Create example programs showcasing Gene
4. **Optimize performance**: Make execution faster for complex programs

## License

MIT License - Same as the Gene project
