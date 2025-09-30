# Gene Standard Library Tests

This directory contains tests for the Gene standard library implementation.

## Test Organization

- `001_core_print.gene` - Core I/O functions (print, println)
- `002_math_basic.gene` - Basic math functions (abs, sqrt, pow)
- `003_env_vars.gene` - Environment variable functions
- `004_file_ops.gene` - File operations (read, write, delete)
- `005_math_advanced.gene` - Advanced math functions (min, max, floor)
- `006_system.gene` - System information functions
- `007_file_class.gene` - File class with both static and instance methods
- `008_class_as_namespace.gene` - Demonstrates class serving as namespace

## Running Tests

Run all tests:
```bash
for file in testsuite/stdlib/*.gene; do
  echo "=== Testing $file ==="
  bin/gene run "$file" || echo "FAILED"
done
```

Run individual test:
```bash
bin/gene run testsuite/stdlib/001_core_print.gene
```

## Standard Library Organization

The standard library is organized into modules:

### core (src/gene/stdlib/core.nim)
- I/O: `print`, `println`
- Debugging: `debug`, `assert`, `trace_start`, `trace_end`
- Timing: `sleep`, `run_forever`
- Environment: `get_env`, `set_env`, `has_env`
- Encoding: `base64`, `base64_decode`
- VM debugging: `vm/print_stack`, `vm/print_instructions`

### math (src/gene/stdlib/math.nim)
- Basic: `abs`, `sqrt`, `pow`
- Trigonometry: `sin`, `cos`, `tan`
- Logarithms: `log`, `log10`
- Rounding: `floor`, `ceil`, `round`
- Comparison: `min`, `max`
- Random: `random`, `random_int`
- Constants: `math/PI`, `math/E`

### io (src/gene/stdlib/io.nim)
- File operations: `File/read`, `File/write`, `File/append`, `File/exists`, `File/delete`
- Directory operations: `Dir/exists`, `Dir/create`, `Dir/delete`, `Dir/list`
- Path utilities: `io/path_join`, `io/path_abs`, `io/path_basename`, `io/path_dirname`, `io/path_ext`

### system (src/gene/stdlib/system.nim)
- Process execution: `system/exec`, `system/shell`
- Directory: `system/cwd`, `system/cd`
- Exit: `system/exit`
- Arguments: `system/args`
- Platform info: `system/os`, `system/arch`

## Global Namespace

Many commonly-used functions are added directly to the global namespace for convenience:

- Math: `abs`, `sqrt`, `pow`, `min`, `max`, `floor`, `ceil`, `round`, `random`, `random_int`
- Core: `print`, `println`, `assert`, `debug`, `sleep`, `base64`, `base64_decode`
- System: `exit`, `cwd`, `args`
- IO: `File`, `Dir`

Functions can be accessed either directly or through their namespace:
```gene
(println "hello")           # Direct access
(math/sqrt 16)              # Namespace access
(sqrt 16)                   # Also works (added to global)
```

## Class as Namespace

Classes in Gene can serve dual roles - both as classes (with constructors and instance methods) and as namespaces (with static methods). This is particularly useful for the `File` class:

### Static Methods (Class as Namespace)
Static methods can be called directly on the class name using the `/` syntax:

```gene
(File/read "path.txt")           # Static method - takes path as argument
(File/write "path.txt" "content")
(File/exists "path.txt")
(File/delete "path.txt")
```

### Instance Methods (Class as Class)
Instance methods are called on instances created with `new`:

```gene
(var f (new File "path.txt"))    # Create File instance with path
(f .read)                         # Instance method - path is in instance
(f .write "content")              # Instance method
```

### Implementation

This is implemented via the `members` field in the `Class` type:
- **Static methods** are stored in `class.members` as functions
- **Instance methods** are stored in `class.methods` as bound methods
- When resolving `Class/member`, the VM checks `members` first, then `ns`

Example from `io.nim`:
```nim
let file_class = new_class("File")
file_class.def_native_constructor(io_file_constructor)
file_class.def_native_method("read", io_file_read_instance)   # Instance method
file_class.def_static_method("read", io_file_read)            # Static method
```

This pattern allows:
- `(File/read "a.txt")` - Static method, convenient for one-off operations
- `((new File "a.txt") .read)` - Instance method, cleaner when performing multiple operations on the same file