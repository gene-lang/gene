# Genie: A WASM-Compatible Gene Language

> Design document for a WebAssembly-compatible language inspired by Gene

## Overview

Genie is a statically-typed, S-expression-based language that compiles to WebAssembly. It preserves Gene's elegant Lisp-like syntax and powerful macro system while adding the type safety and performance characteristics required for WASM targets.

### Design Goals

1. **WASM-first** - Compile to efficient WebAssembly bytecode
2. **Type-safe** - Static typing with inference, catch errors at compile time
3. **Familiar** - Keep Gene's S-expression syntax and semantics where possible
4. **Interoperable** - Seamless JavaScript/WASI integration
5. **Minimal runtime** - Small binary size, fast startup
6. **Macro-powered** - Compile-time metaprogramming

---

## Table of Contents

1. [Syntax Reference](#1-syntax-reference)
2. [Type System](#2-type-system)
3. [Memory Model](#3-memory-model)
4. [Control Flow](#4-control-flow)
5. [Functions & Closures](#5-functions--closures)
6. [Structs & Enums](#6-structs--enums)
7. [Traits](#7-traits)
8. [Pattern Matching](#8-pattern-matching)
9. [Error Handling](#9-error-handling)
10. [Modules & Visibility](#10-modules--visibility)
11. [Macros](#11-macros)
12. [Async](#12-async)
13. [Platform Interop](#13-platform-interop)
14. [Memory Management](#14-memory-management)
15. [Standard Library](#15-standard-library)
16. [Compilation Pipeline](#16-compilation-pipeline)
17. [Examples](#17-examples)

---

## 1. Syntax Reference

### Comments

```gene
# Single line comment

#|
   Multi-line
   block comment
|#
```

### Literals

```gene
# Integers
42          # i32 (default)
42i64       # i64
0xFF        # Hexadecimal
0b1010      # Binary
1_000_000   # Underscores for readability

# Floats
3.14        # f64 (default)
3.14f32     # f32
1.0e-10     # Scientific notation

# Boolean
true
false

# Strings
"hello world"
"line1\nline2"          # Escape sequences
`raw string \n`         # Raw string (no escapes)
(format "x = {}" x)     # String interpolation

# Characters
'A'         # u8 (single byte)
'\n'        # Escape sequences

# Unit (void)
unit
```

### Variables

```gene
# Mutable variable
(var x 42)
(var x:i32 42)          # Explicit type
(x = 100)               # Assignment

# Immutable binding
(let y 42)
(let y:i32 42)

# Multiple bindings
(var (a b c) (1 2 3))
(let (x y) (get-coords))
```

### Operators

```gene
# Arithmetic
(a + b)
(a - b)
(a * b)
(a / b)
(a % b)                 # Modulo

# Comparison
(a == b)
(a != b)
(a < b)
(a <= b)
(a > b)
(a >= b)

# Logical
(a and b)
(a or b)
(not a)

# Bitwise
(a & b)                 # AND
(a | b)                 # OR
(a ^ b)                 # XOR
(~a)                    # NOT
(a << n)                # Left shift
(a >> n)                # Right shift
```

### Collections

```gene
# Arrays
[1 2 3 4 5]
(var nums:[i32] [1 2 3])
nums/0                  # Access (0-indexed)
(nums/0 = 10)           # Mutation
nums/.len               # Length

# Slices (views, no copy)
(nums .slice 1 3)       # [2 3]

# Maps
{^key "value" ^count 42}
(var m:{str i32} {^a 1 ^b 2})
m/key                   # Access
(m/key = "new")         # Mutation
(m .get "key")          # Returns Option

# Sets
#{1 2 3 4 5}
(var s:#{i32} #{1 2 3})
(s .contains 2)         # true
(s .add 4)
(s .remove 1)
```

---

## 2. Type System

### Primitive Types

| Genie Type | WASM Type | Size | Description |
|------------|-----------|------|-------------|
| `i32` | i32 | 4 bytes | 32-bit signed integer |
| `i64` | i64 | 8 bytes | 64-bit signed integer |
| `u32` | i32 | 4 bytes | 32-bit unsigned integer |
| `u64` | i64 | 8 bytes | 64-bit unsigned integer |
| `f32` | f32 | 4 bytes | 32-bit float |
| `f64` | f64 | 8 bytes | 64-bit float |
| `bool` | i32 | 4 bytes | Boolean (0 or 1) |
| `u8` | i32 | 1 byte | Byte/character |
| `unit` | (none) | 0 bytes | Unit/void type |

### Compound Types

```gene
# Arrays (heap allocated, growable)
[T]                     # Array of T
[[T]]                   # Nested array

# Fixed-size arrays (stack allocated)
[T; N]                  # Array of N elements

# Tuples
(T1 T2 T3)              # Tuple of 3 elements

# Strings
str                     # UTF-8 string (heap)

# Maps and Sets
{K V}                   # Map from K to V
#{T}                    # Set of T

# Optional and Result
(Option T)              # Some(T) or None
(Result T E)            # Ok(T) or Err(E)

# Function types
(fn [A B] -> R)         # Function taking A, B returning R
(fn [A...] -> R)        # Variadic function

# Pointers (unsafe)
(ptr T)                 # Raw pointer to T
(box T)                 # Heap-allocated, ref-counted
(rc T)                  # Explicit ref-counted
(weak T)                # Weak reference
```

### Type Inference

```gene
# Inferred from literal
(var x 42)              # x: i32
(var y 3.14)            # y: f64
(var s "hello")         # s: str
(var a [1 2 3])         # a: [i32]

# Inferred from usage
(fn double [x] (x * 2)) # Error: can't infer x
(fn double [x:i32] (x * 2))  # Ok: returns i32

# Bidirectional inference
(var f:(fn [i32] -> i32) (fn [x] (x + 1)))

# Explicit type annotation
(var x (42 :as i64))    # Cast literal
(var y (x :as i32))     # Explicit cast
```

### Generics

```gene
# Generic struct
(struct Pair [T U]
  first:T
  second:U)

(var p (Pair 1 "hello"))  # Pair[i32 str]

# Generic function
(fn swap [T] [a:T b:T] -> (T T)
  (b a))

# Generic with trait bounds
(fn sum [T: Add + Default] [items:[T]] -> T
  (var acc (T/default))
  (for item in items
    (acc = (acc + item)))
  acc)

# Where clauses for complex bounds
(fn merge [K V] [a:{K V} b:{K V}] -> {K V}
  where (K: Hash + Eq)
        (V: Clone)
  ...)
```

---

## 3. Memory Model

### Stack vs Heap

```gene
# Stack allocation (default for small types)
(var point (Vec3 1.0 2.0 3.0))   # On stack
(var num 42)                      # On stack

# Heap allocation
(var boxed (box (Vec3 1.0 2.0 3.0)))  # Ref-counted heap
(var array [1 2 3 4 5])               # Arrays always on heap
(var string "hello")                   # Strings always on heap
```

### Memory Layout

```
WASM Linear Memory Layout
─────────────────────────────────────────────
0x0000    │ Reserved (null trap)
0x1000    │ Static data (string literals, consts)
0x10000   │ Heap start ──────────────────────►
          │   [header][data][header][data]...
          │              Free space
          │ ◄────────────────────── Stack end
0xFFFFF   │ Stack start
─────────────────────────────────────────────
```

### Reference Counting

```gene
# Automatic ref-counting for boxed values
(var a (box (MyStruct ...)))
(var b a)                    # ref_count = 2
# When a goes out of scope:  ref_count = 1
# When b goes out of scope:  ref_count = 0, freed

# Weak references (break cycles)
(var parent (box (Node ...)))
(var child (box (Node ...)))
(child/parent = (weak parent))  # Doesn't increment ref
```

### Arenas (Batch Allocation)

```gene
(fn process-data [items:[Item]] -> Result
  (arena temp
    # All allocations in this block use the arena
    (var processed [])
    (for item in items
      (var transformed (heavy-computation item))
      (processed .push transformed))

    # Copy result out before arena is freed
    (processed .to-owned)))
# Arena memory freed here (single deallocation)
```

### Unsafe Memory Operations

```gene
(unsafe
  # Raw pointer operations
  (var ptr (alloc 1024))        # Allocate bytes
  (ptr .write-i32 0 42)         # Write at offset
  (var val (ptr .read-i32 0))   # Read from offset
  (free ptr))                   # Manual free
```

---

## 4. Control Flow

### Conditionals

```gene
# If expression
(if (x > 0)
  "positive"
else
  "non-positive")

# If with multiple branches
(if (x > 0)
  "positive"
elif (x < 0)
  "negative"
else
  "zero")

# When (if without else, returns unit)
(when (debug-mode)
  (println "Debug info"))

# Unless
(unless (valid input)
  (panic "Invalid input"))

# Cond (multi-way branch)
(cond
  (x < 0)   "negative"
  (x == 0)  "zero"
  (x < 10)  "small"
  (x < 100) "medium"
  else      "large")
```

### Loops

```gene
# Infinite loop with break
(loop
  (var input (read-line))
  (if (input == "quit")
    (break)
    (process input)))

# Loop with result
(var result
  (loop
    (var x (compute))
    (if (x > threshold)
      (break x))))

# While loop
(while (x > 0)
  (process x)
  (x = (x - 1)))

# For loop (iterators)
(for item in items
  (process item))

# For with index
(for [i item] in (enumerate items)
  (println i item))

# Range iteration
(for i in (range 0 10)      # 0..9
  (println i))

(for i in (range 0 10 2)    # 0, 2, 4, 6, 8
  (println i))

# Continue
(for item in items
  (when (skip? item)
    (continue))
  (process item))
```

---

## 5. Functions & Closures

### Function Definition

```gene
# Basic function
(fn add [a:i32 b:i32] -> i32
  (a + b))

# No return type (returns unit)
(fn greet [name:str]
  (println "Hello" name))

# Multiple expressions (last is return value)
(fn process [x:i32] -> i32
  (var y (x * 2))
  (var z (y + 1))
  z)

# Early return
(fn find [items:[Item] pred:(fn [Item] -> bool)] -> (Option Item)
  (for item in items
    (when (pred item)
      (return (Some item))))
  None)

# Multiple return values
(fn divmod [a:i32 b:i32] -> (i32 i32)
  ((a / b) (a % b)))

(var (quotient remainder) (divmod 17 5))

# Default parameters
(fn greet [name:str greeting:str = "Hello"]
  (println greeting name))

(greet "Alice")              # Hello Alice
(greet "Bob" "Hi")           # Hi Bob

# Named parameters
(fn create-user [name:str age:i32 active:bool = true]
  (User name age active))

(create-user ^name "Alice" ^age 30)
(create-user ^age 25 ^name "Bob" ^active false)
```

### Closures

```gene
# Anonymous function
(var double (fn [x:i32] -> i32 (x * 2)))

# Closure capturing environment
(fn make-counter [] -> (fn [] -> i32)
  (var count 0)
  (fn []
    (count = (count + 1))
    count))

(var counter (make-counter))
(counter)  # 1
(counter)  # 2
(counter)  # 3

# Short closure syntax
(items .map |x| (x * 2))
(items .filter |x| (x > 0))
(items .reduce 0 |acc x| (acc + x))
```

### Higher-Order Functions

```gene
(fn map [T U] [arr:[T] f:(fn [T] -> U)] -> [U]
  (var result [])
  (for item in arr
    (result .push (f item)))
  result)

(fn filter [T] [arr:[T] pred:(fn [T] -> bool)] -> [T]
  (var result [])
  (for item in arr
    (when (pred item)
      (result .push item)))
  result)

(fn fold [T A] [arr:[T] init:A f:(fn [A T] -> A)] -> A
  (var acc init)
  (for item in arr
    (acc = (f acc item)))
  acc)
```

---

## 6. Structs & Enums

### Structs

```gene
# Basic struct
(struct Point
  x:f32
  y:f32)

# Creating instances
(var p (Point 3.0 4.0))
(var p (Point ^x 3.0 ^y 4.0))  # Named fields

# Field access
p/x
p/y

# Field mutation
(p/x = 5.0)

# Struct with defaults
(struct Config
  host:str = "localhost"
  port:i32 = 8080
  debug:bool = false)

(var cfg (Config))                    # All defaults
(var cfg (Config ^port 3000))         # Override port

# Generic struct
(struct Pair [T U]
  first:T
  second:U)

# Struct methods (see Traits section)
```

### Enums (Tagged Unions)

```gene
# Simple enum
(enum Color
  Red
  Green
  Blue)

(var c Color/Red)

# Enum with data
(enum Shape
  (Circle radius:f32)
  (Rectangle width:f32 height:f32)
  (Triangle a:f32 b:f32 c:f32))

(var s (Shape/Circle 5.0))
(var r (Shape/Rectangle 10.0 20.0))

# Generic enum
(enum Option [T]
  None
  (Some val:T))

(enum Result [T E]
  (Ok val:T)
  (Err err:E))

# Using enums
(var maybe (Option/Some 42))
(var result (Result/Ok "success"))
```

---

## 7. Traits

### Trait Definition

```gene
(trait Display
  (fn display [self] -> str))

(trait Clone
  (fn clone [self] -> Self))

(trait Default
  (fn default [] -> Self))

(trait Add [Rhs = Self]
  (type Output)
  (fn add [self rhs:Rhs] -> Self/Output))
```

### Trait Implementation

```gene
(struct Point
  x:f32
  y:f32)

(impl Display for Point
  (fn display [self] -> str
    (format "({}, {})" self/x self/y)))

(impl Clone for Point
  (fn clone [self] -> Point
    (Point self/x self/y)))

(impl Default for Point
  (fn default [] -> Point
    (Point 0.0 0.0)))

(impl Add for Point
  (type Output Point)
  (fn add [self rhs:Point] -> Point
    (Point (self/x + rhs/x) (self/y + rhs/y))))
```

### Associated Methods

```gene
(impl Point
  # Constructor
  (fn new [x:f32 y:f32] -> Point
    (Point x y))

  # Instance method
  (fn distance [self other:Point] -> f32
    (var dx (self/x - other/x))
    (var dy (self/y - other/y))
    (sqrt ((dx * dx) + (dy * dy))))

  # Static method
  (fn origin [] -> Point
    (Point 0.0 0.0)))

# Usage
(var p (Point/new 3.0 4.0))
(var d (p .distance (Point/origin)))
```

### Trait Bounds

```gene
(fn print-all [T: Display] [items:[T]]
  (for item in items
    (println (item .display))))

(fn clone-and-modify [T: Clone + Default] [item:T] -> T
  (var copy (item .clone))
  # ... modify copy
  copy)
```

---

## 8. Pattern Matching

### Basic Matching

```gene
(match value
  1 "one"
  2 "two"
  3 "three"
  _ "other")          # _ is wildcard

# Match with binding
(match value
  0 "zero"
  n (format "number: {}" n))
```

### Enum Matching

```gene
(match option
  None "nothing"
  (Some x) (format "got {}" x))

(match result
  (Ok val) val
  (Err e) (panic e))

(match shape
  (Circle r) (format "circle with radius {}" r)
  (Rectangle w h) (format "{}x{} rectangle" w h)
  (Triangle a b c) (format "triangle: {} {} {}" a b c))
```

### Struct Matching

```gene
(match point
  (Point 0.0 0.0) "origin"
  (Point x 0.0) (format "on x-axis at {}" x)
  (Point 0.0 y) (format "on y-axis at {}" y)
  (Point x y) (format "at ({}, {})" x y))
```

### Guards

```gene
(match x
  n if (n < 0) "negative"
  n if (n > 100) "large"
  n "normal")
```

### Multiple Patterns

```gene
(match c
  'a' | 'e' | 'i' | 'o' | 'u' "vowel"
  _ "consonant")
```

### Let with Pattern

```gene
(let (Some x) (get-value))   # Panics if None
(let (x y) (get-pair))       # Destructure tuple

# If-let for safe destructuring
(if-let (Some x) (get-value)
  (use x)
else
  (handle-none))

# While-let
(while-let (Some item) (iter .next)
  (process item))
```

---

## 9. Error Handling

### Result Type

```gene
(fn divide [a:i32 b:i32] -> (Result i32 str)
  (if (b == 0)
    (Err "division by zero")
    (Ok (a / b))))

# Explicit handling
(match (divide 10 2)
  (Ok val) (println "Result:" val)
  (Err e) (println "Error:" e))
```

### Propagation Operator

```gene
# ? operator returns early on Err
(fn compute [x:i32 y:i32] -> (Result i32 str)
  (var a (divide x y)?)       # Returns Err if divide fails
  (var b (divide a 2)?)
  (Ok (b + 1)))

# Works with Option too
(fn get-name [id:i32] -> (Option str)
  (var user (users .get id)?)
  (Some user/name))
```

### Try Blocks

```gene
(var result
  (try
    (var a (may-fail-1)?)
    (var b (may-fail-2 a)?)
    (Ok (process a b))
  catch e
    (Err (format "Failed: {}" e))))
```

### Panic

```gene
# Unrecoverable error
(panic "something went terribly wrong")

# Assert
(assert (x > 0) "x must be positive")

# Debug assert (removed in release builds)
(debug-assert (invariant-holds))

# Unreachable
(fn process [x:i32] -> str
  (match x
    1 "one"
    2 "two"
    _ (unreachable)))         # Compiler hint
```

---

## 10. Modules & Visibility

### Module Definition

```gene
# In file: math.genie
(module math
  # Public items
  (pub fn add [a:i32 b:i32] -> i32 (a + b))
  (pub fn sub [a:i32 b:i32] -> i32 (a - b))

  (pub struct Point
    x:f32
    y:f32)

  # Private (module-internal)
  (fn helper [x:i32] -> i32 (x * 2)))
```

### Imports

```gene
# Import specific items
(use math [add sub Point])

# Import with alias
(use math [add :as plus])

# Import all public items
(use math [*])

# Qualified import
(use math)
(math/add 1 2)

# Rename module
(use math :as m)
(m/add 1 2)
```

### Nested Modules

```gene
(module utils
  (module string
    (pub fn trim [s:str] -> str ...))

  (module math
    (pub fn abs [x:i32] -> i32 ...)))

(use utils/string [trim])
(use utils/math [abs])
```

### Visibility Modifiers

```gene
(pub fn public-fn [])           # Visible everywhere
(fn private-fn [])              # Module-private
(pub(crate) fn crate-fn [])     # Visible in crate
```

---

## 11. Macros

### Basic Macros

```gene
# Simple macro
(macro inc! [var]
  `(,var = (,var + 1)))

(var x 5)
(inc! x)    # x is now 6

# Debug macro
(macro dbg! [expr]
  `(do
    (var _result ,expr)
    (println ,(stringify expr) "=" _result)
    _result))

(dbg! (1 + 2))  # Prints: (1 + 2) = 3
```

### Macro with Multiple Arguments

```gene
(macro swap! [a b]
  `(do
    (var _tmp ,a)
    (,a = ,b)
    (,b = _tmp)))

(var x 1)
(var y 2)
(swap! x y)   # x=2, y=1
```

### Variadic Macros

```gene
(macro println! [fmt args...]
  `(print (format ,fmt ,@args) "\n"))

(println! "x={} y={}" x y)
```

### Compile-Time Computation

```gene
(macro const-fib [n]
  (fn fib [x]
    (if (x <= 1) x ((fib (x - 1)) + (fib (x - 2)))))
  (fib n))

(var fib10 (const-fib 10))  # Computed at compile time
```

### Conditional Compilation

```gene
(macro when-debug [body...]
  (if (cfg debug)
    `(do ,@body)
    `unit))

(when-debug
  (println "Debug mode"))
```

---

## 12. Async

### Async Functions

```gene
(async fn fetch-data [url:str] -> (Result str Error)
  (var response (await (http/get url)))
  (var body (await (response .text)))
  (Ok body))
```

### Await

```gene
(async fn main []
  # Sequential await
  (var user (await (fetch-user 1)))
  (var posts (await (fetch-posts user/id)))

  # Parallel await
  (var (users posts) (await-all
    (fetch-users)
    (fetch-posts)))

  # Race (first to complete)
  (var result (await-race
    (fetch-from-server-a)
    (fetch-from-server-b))))
```

### Futures

```gene
# Create future without awaiting
(var future (async (expensive-computation)))

# Do other work...

# Await when needed
(var result (await future))
```

### Channels (for concurrency)

```gene
(var (tx rx) (channel i32 10))  # Buffered channel

(spawn
  (for i in (range 0 10)
    (tx .send i)))

(async fn consumer []
  (while-let (Some val) (await (rx .recv))
    (println "Got:" val)))
```

---

## 13. Platform Interop

### JavaScript Interop

```gene
# Import from JavaScript
(extern "js"
  (fn console_log [msg:str])
  (fn document_getElementById [id:str] -> JsValue)
  (fn setTimeout [callback:(fn []) delay:i32])
  (fn fetch [url:str] -> (Promise Response)))

# Export to JavaScript
(pub fn greet [name:str] -> str
  (format "Hello, {}!" name))

(pub fn process [data:JsValue] -> JsValue
  ...)

# Working with JS values
(fn handle-click [event:JsValue]
  (var target (event .get "target"))
  (var id (target .get "id")))
```

### Generated TypeScript Bindings

```typescript
// Auto-generated: my_module.d.ts
export function greet(name: string): string;
export function process(data: any): any;
export class Point {
  constructor(x: number, y: number);
  readonly x: number;
  readonly y: number;
  distance(other: Point): number;
}
```

### WASI (System Interface)

```gene
(use genie/wasi [args env fs process])

(fn main [] -> i32
  # Command line arguments
  (var arguments (args/get))

  # Environment variables
  (var home (env/get "HOME"))

  # File system
  (var content (fs/read-file "input.txt")?)
  (fs/write-file "output.txt" content)

  # Process
  (process/exit 0))
```

### Raw WASM Interop

```gene
# Import WASM function
(extern "wasm"
  (fn memory_grow [pages:i32] -> i32)
  (fn memory_size [] -> i32))

# Inline WAT (WebAssembly Text)
(wasm-inline "
  (func $fast_add (param i32 i32) (result i32)
    local.get 0
    local.get 1
    i32.add)
")
```

---

## 14. Memory Management

### Automatic Management (Default)

```gene
# Stack allocation for small types
(var point (Point 1.0 2.0))

# Heap allocation for collections
(var items [1 2 3 4 5])

# Reference counting for shared data
(var shared (box (LargeStruct ...)))
(var alias shared)  # Increments ref count
```

### Manual Memory Control

```gene
# Arena allocation
(arena temp
  (var data (process-large-input input))
  (var result (transform data))
  (result .to-owned))  # Copy out before arena freed

# Manual allocation (unsafe)
(unsafe
  (var ptr (alloc 1024))
  (defer (free ptr))       # Ensure cleanup

  (ptr .write-bytes data)
  (process-raw ptr 1024))
```

### Memory Layout Control

```gene
# Packed struct (no padding)
#[repr(packed)]
(struct PackedData
  a:u8
  b:u32
  c:u8)

# C-compatible layout
#[repr(C)]
(struct CCompatible
  x:i32
  y:i32)

# Explicit alignment
#[align(16)]
(struct Aligned
  data:[f32; 4])
```

---

## 15. Standard Library

### Core (Always Available)

```gene
# Prelude - automatically imported
Option None Some
Result Ok Err
bool true false
print println format
assert panic unreachable
```

### Collections

```gene
(use genie/collections [Vec Map Set Deque])

(var v (Vec/new))
(v .push 1)
(v .pop)

(var m (Map/new))
(m .insert "key" "value")
(m .get "key")

(var s (Set/new))
(s .insert 1)
(s .contains 1)
```

### Strings

```gene
(use genie/string [*])

(s .len)
(s .is-empty)
(s .contains "sub")
(s .starts-with "pre")
(s .ends-with "suf")
(s .trim)
(s .split ",")
(s .replace "old" "new")
(s .to-uppercase)
(s .to-lowercase)
```

### Math

```gene
(use genie/math [*])

(abs x)
(min a b)
(max a b)
(clamp x low high)
(sqrt x)
(pow base exp)
(sin x) (cos x) (tan x)
(floor x) (ceil x) (round x)

PI E
```

### I/O

```gene
(use genie/io [*])

(print "hello")
(println "hello")
(var line (read-line))
(var content (fs/read-file "path")?)
(fs/write-file "path" content)
```

### JSON

```gene
(use genie/json [parse stringify])

(var data (parse json-string)?)
(var json (stringify data))

# Typed parsing
(var user (parse-as User json-string)?)
```

### Time

```gene
(use genie/time [*])

(var now (Instant/now))
(var elapsed (now .elapsed))
(sleep (Duration/from-millis 100))
```

---

## 16. Compilation Pipeline

```
Source (.genie)
      │
      ▼
┌─────────────┐
│   Lexer     │ ─── Tokens
└─────────────┘
      │
      ▼
┌─────────────┐
│   Parser    │ ─── S-expression AST
└─────────────┘
      │
      ▼
┌─────────────┐
│   Macros    │ ─── Expanded AST
└─────────────┘
      │
      ▼
┌─────────────┐
│ Type Check  │ ─── Typed AST
└─────────────┘
      │
      ▼
┌─────────────┐
│  Genie IR   │ ─── High-level IR
└─────────────┘
      │
      ▼
┌─────────────┐
│ Optimizer   │ ─── Optimized IR
└─────────────┘
      │
      ▼
┌─────────────┐
│ WASM Codegen│ ─── .wasm binary
└─────────────┘
      │
      ├─── .wasm (binary)
      ├─── .wat (text, debug)
      └─── .d.ts (TypeScript bindings)
```

### Compiler Flags

```bash
genie build main.genie              # Build to WASM
genie build --release main.genie    # Optimized build
genie build --target wasi main.genie  # WASI target
genie build --emit wat main.genie   # Output WAT text
genie check main.genie              # Type check only
genie run main.genie                # Build and run
```

---

## 17. Examples

### Hello World

```gene
(fn main []
  (println "Hello, World!"))
```

### Fibonacci

```gene
(fn fib [n:i32] -> i32
  (if (n <= 1)
    n
    ((fib (n - 1)) + (fib (n - 2)))))

(fn main []
  (for i in (range 0 20)
    (println (format "fib({}) = {}" i (fib i)))))
```

### Todo Application

```gene
(struct Todo
  id:i32
  text:str
  done:bool)

(struct App
  todos:[Todo]
  next_id:i32)

(impl App
  (fn new [] -> App
    (App [] 1))

  (fn add [self text:str] -> i32
    (var id self/next_id)
    (self/todos .push (Todo id text false))
    (self/next_id = (id + 1))
    id)

  (fn toggle [self id:i32] -> bool
    (for todo in self/todos
      (when (todo/id == id)
        (todo/done = (not todo/done))
        (return true)))
    false)

  (fn remove [self id:i32] -> bool
    (match (self/todos .find-index |t| (t/id == id))
      (Some i) (do (self/todos .remove i) true)
      None false)))

# Export for JavaScript
(pub var app (App/new))

(pub fn add_todo [text:str] -> i32
  (app .add text))

(pub fn toggle_todo [id:i32] -> bool
  (app .toggle id))

(pub fn remove_todo [id:i32] -> bool
  (app .remove id))
```

### HTTP Server (WASI)

```gene
(use genie/wasi/http [Server Request Response])

(fn handle [req:Request] -> Response
  (match req/path
    "/" (Response/ok "Hello, World!")
    "/api/data" (Response/json {^status "ok"})
    _ (Response/not-found)))

(fn main []
  (var server (Server/bind "0.0.0.0:8080"))
  (println "Listening on :8080")
  (server .serve handle))
```

---

## Open Questions

1. **Garbage Collection**: Should we support WASM GC proposal for cycle collection, or stick with ref-counting + weak refs?

2. **Effect System**: Add algebraic effects for structured side effects?

3. **Lifetimes**: Rust-style lifetime annotations for borrowed references?

4. **Inline Assembly**: How much raw WASM access should be exposed?

5. **Build System**: Cargo-like package manager? How to handle dependencies?

6. **Interop Complexity**: How seamless should JS/WASI interop be?

---

## Related Work

- **AssemblyScript** - TypeScript-like syntax for WASM
- **Grain** - Functional language for WASM
- **Rust** - Systems language with WASM target
- **Zig** - Low-level language with WASM support
- **Gleam** - Type-safe BEAM language (different target, similar philosophy)

---

## Next Steps

1. Implement lexer and parser for core syntax
2. Design type checker with inference
3. Build simple IR for optimization
4. Implement WASM code generation
5. Create minimal runtime library
6. Add JavaScript interop layer
7. Build standard library modules
