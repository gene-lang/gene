# AI-First Design: Implementation Roadmap

Gene is at version 0.0.x - we break backward compatibility freely. This document outlines the phased implementation of AI-first Gene: a statically typed, effect-tracked language with machine-verifiable contracts.

## Target: Statically Typed with Inference

Gene becomes a statically typed language where:
- Types are inferred by default
- Explicit annotations optional (for clarity or disambiguation)
- Compile-time type checking with clear error messages
- Effects tracked in the type system

## Execution Model

```
Source → Parse → AST → Type Infer → Typed AST → Compile → IR → VM
                        ↑
                  New phase
```

Enhanced for AI:
- Every stage queryable
- Execution observable, checkpointable
- Effects logged, reversible where possible

---

## Phase 1: Type Inference & Checking

**Goal**: Infer types at compile time. Reject ill-typed programs.

### Type Syntax

```gene
# Primitives
Int Float Bool String Symbol Char Nil

# Compound
(Array T)
(Map K V)
(Option T)          # (Some T) | None
(Result T E)        # (Ok T) | (Err E)

# Functions
(A B) -> R         # Pure
(A B) -> R ! [E]   # With effects (Phase 3)

# Union
(A | B | C)
```

### Inference Examples

```gene
(var x 1)                    # x: Int
(var y 1.5)                  # y: Float
(var s "hello")              # s: String
(var arr [1 2 3])            # arr: (Array Int)
(var map {^a 1 ^b 2})        # map: (Map Symbol Int)

(fn double [x] (x * 2))      # (Int) -> Int (inferred from *)

(fn first [arr]              # (Array T) -> (Option T)
  (if (arr .empty?) None (Some arr/0)))
```

### Explicit Annotations

```gene
# Variable
(var x: Float 1)             # Force Float

# Function parameters and return
(fn divide [a: Int b: Int] -> (Result Int Error)
  ...)

# Generic constraints
(fn sort [arr: (Array T)] -> (Array T)
  ^where [(T : Comparable)]
  ...)
```

### Type Errors

```
error[E001]: Type mismatch
  --> src/app.gene:15:10
   |
15 |   (+ x "hello")
   |      - ^^^^^^^ expected Int, found String
   |      |
   |      x has type Int
```

### Tasks

- [ ] Define type representation in compiler
- [ ] Implement Hindley-Milner style inference
- [ ] Add unification algorithm
- [ ] Implement generic type parameters
- [ ] Add union type support
- [ ] Create type error messages
- [ ] Update parser for type annotations

---

## Phase 2: Result Type & Structured Errors

**Goal**: Replace exceptions with explicit Result types.

### Result and Option Types

```gene
# Built-in types
(type (Option T) ((Some T) | None))
(type (Result T E) ((Ok T) | (Err E)))

# Err carries structured data
(Err ^code "db/NOT_FOUND" ^entity "user" ^id 123)
```

### Pattern Matching

```gene
(match (fetch-user id)
  (Ok user) (process user)
  (Err e)   (handle-error e/.code))

(match (find-item id)
  (Some item) item
  None        default-item)
```

### Error Propagation

```gene
# ? operator propagates errors
(fn get-user-email [id: Int] -> (Result String Error) ! [Db]
  (var user (db/get-user id)?)  # Returns early if Err
  (Ok user/.email))

# Equivalent to:
(fn get-user-email [id: Int] -> (Result String Error) ! [Db]
  (match (db/get-user id)
    (Err e) (Err e)
    (Ok user) (Ok user/.email)))
```

### Namespaced Error Codes

```gene
# Convention: namespace/CODE
"db/NOT_FOUND"
"db/CONNECTION_FAILED"
"http/TIMEOUT"
"http/NOT_FOUND"
"auth/FORBIDDEN"
"auth/INVALID_TOKEN"
"validation/INVALID_EMAIL"
"validation/REQUIRED_FIELD"
```

### Tasks

- [ ] Add Option and Result to type system
- [ ] Implement Some, None, Ok, Err constructors
- [ ] Add pattern matching for algebraic types
- [ ] Implement ? operator for error propagation
- [ ] Document error code conventions

---

## Phase 3: Effect System

**Goal**: Track side effects in function signatures. Compiler enforces boundaries.

### Effect Declaration

```gene
# Pure function (no ! clause)
(fn add [a: Int b: Int] -> Int
  (a + b))

# Function with effects
(fn save-user [user: User] -> (Result User DbError) ! [Db]
  (db/insert user))

# Multiple effects
(fn process [id: Int] -> (Result Data Error) ! [Db Http Log]
  (var user (db/get id)?)
  (var data (http/fetch user/.url)?)
  (log/info "processed" id)
  (Ok data))
```

### Standard Effects

```gene
effect Db        # Database operations
effect Http      # Network requests
effect Io        # File system
effect Log       # Logging
effect Env       # Environment variables
effect Time      # Current time
effect Random    # Random numbers
effect Console   # stdin/stdout
effect Async     # Async operations
```

### Effect Rules

1. Pure functions cannot call effectful functions
2. Effects propagate: caller must declare callee's effects
3. Effect handlers can intercept/mock effects

```gene
# Compile error: pure function calls effectful
(fn bad [x: Int] -> Int          # No effects declared
  (db/get x))                    # Error: Db effect not declared

# Correct
(fn good [x: Int] -> Int ! [Db]
  (db/get x))
```

### Effect Handlers

```gene
# Mock database for testing
(with-handler Db (mock-db {^users [{^id 1 ^name "Alice"}]})
  (test-user-lookup))

# Record HTTP calls
(with-handler Http (recording-handler)
  (make-api-calls))
```

### Tasks

- [ ] Add effect syntax to parser
- [ ] Track effects in type checker
- [ ] Implement effect propagation rules
- [ ] Add standard effect definitions
- [ ] Implement effect handlers
- [ ] Create effect violation error messages

---

## Phase 4: Contracts

**Goal**: Pre/postconditions checked at runtime (dev) or compile time (where possible).

### Contract Syntax

```gene
(fn withdraw [account: Account amount: Int] -> (Result Account Error) ! [Db]
  ^pre [
    (amount > 0)
    (account/.balance >= amount)
  ]
  ^post [
    (result .is_ok) => (result/.value/.balance == account/.balance - amount)
  ]

  (var new-balance (account/.balance - amount))
  (db/update account ^balance new-balance))
```

### Contract Modes

```bash
gene run file.gene              # Contracts off (default)
gene run --contracts file.gene  # Contracts on
gene test file.gene             # Contracts on in tests
```

### Examples as Tests

```gene
(fn fibonacci [n: Int] -> Int
  ^pre [(n >= 0)]
  ^examples [
    {^in [0] ^out 0}
    {^in [1] ^out 1}
    {^in [10] ^out 55}
  ]

  (if (n < 2) n
    (+ (fibonacci (n - 1)) (fibonacci (n - 2)))))
```

```bash
gene test --examples  # Run all ^examples as tests
```

### Tasks

- [ ] Parse ^pre and ^post properties
- [ ] Generate contract checking code
- [ ] Add --contracts flag
- [ ] Implement example runner
- [ ] Static contract verification (simple cases)

---

## Phase 5: Canonical Formatter

**Goal**: `gene fmt` produces deterministic output.

### Property Order

```gene
(fn name [params] -> ReturnType ! [Effects]
  # 1. Intent/docs
  ^intent "..."
  ^version "..."

  # 2. Contracts
  ^pre [...]
  ^post [...]

  # 3. Context
  ^requires [...]

  # 4. Evidence
  ^examples [...]

  # 5. Body
  body)
```

### Commands

```bash
gene fmt file.gene         # Format in place
gene fmt --check file.gene # Check without modifying (CI)
gene fmt --diff file.gene  # Show diff
```

### Tasks

- [ ] Implement formatter
- [ ] Define canonical ordering rules
- [ ] Add CLI commands
- [ ] Editor plugin integration

---

## Phase 6: Context System

**Goal**: Explicit context passing, compile-time checking of requirements.

### Providing Context

```gene
(with-context [
  (user_id 123)
  (permissions ["read" "write"])
  (db (db/connect url))
]
  (handle-request request))
```

### Requiring Context

```gene
(fn handle-request [req: Request] -> Response ! [Db]
  ^requires [user_id permissions]

  (if (not ($ctx/.permissions .includes "write"))
    (Err ^code "auth/FORBIDDEN")
    (do-work req)))
```

### Compile-Time Checking

```gene
# Error: required context not provided
(fn main []
  (handle-request req))  # Error: user_id, permissions not in context
```

### Tasks

- [ ] Implement with-context
- [ ] Add $ctx accessor
- [ ] Track context in type checker
- [ ] Verify ^requires at compile time

---

## Phase 7: Tool Definitions

**Goal**: First-class tools for AI function calling.

### Tool Syntax

```gene
(tool create_user
  ^description "Create a new user account"
  ^params {
    ^email {^type String ^format "email" ^required true}
    ^password {^type String ^min 8 ^required true}
    ^name {^type String}
  }
  ^returns (Result User Error)
  ^effects [Db Email]
  ^errors [
    {^code "validation/INVALID_EMAIL" ^when "Email format invalid"}
    {^code "validation/WEAK_PASSWORD" ^when "Password too short"}
    {^code "db/DUPLICATE_EMAIL" ^when "Email already exists"}
  ]
  ^examples [
    {^in {^email "a@b.com" ^password "secret123"}
     ^out (Ok (User ^id 1 ^email "a@b.com"))}
  ]

  [email password name]
  (impl ...))
```

### Export Schemas

```bash
gene tools export --format openai    # OpenAI function calling
gene tools export --format anthropic # Anthropic tool use
gene tools export --format json      # JSON Schema
```

### Tasks

- [ ] Implement tool macro
- [ ] Validate tool definitions
- [ ] Schema export for AI platforms
- [ ] Tool registry

---

## Phase 8: Observability

**Goal**: AI can observe, checkpoint, and control execution.

### Tracing

```gene
(with-trace
  (complex-operation data))
# => {^result value ^trace [{^fn "..." ^args [...] ^result ...} ...]}
```

### Dry Run

```gene
(var effects (dry-run
  (db/insert user)
  (email/send welcome)))
# => [{^effect Db ^op "insert" ^args [...]} {^effect Email ^op "send" ^args [...]}]
```

### Checkpoints

```gene
(var cp (checkpoint))
(try
  (risky-operation)
catch
  (restore cp)
  (safe-fallback))
```

### Tasks

- [ ] Implement tracing infrastructure
- [ ] Add dry-run mode
- [ ] Implement checkpoint/restore
- [ ] Effect logging

---

## Phase 9: Code Introspection

**Goal**: Query and analyze code programmatically.

### Query API

```gene
# Find functions with specific effects
(code/find ^type Fn ^effects [Db])

# Find functions returning Result with specific errors
(code/find ^returns Result ^errors ["db/*"])

# Get function metadata
(code/meta create_user)
# => {^intent "..." ^params {...} ^effects [Db Email] ...}
```

### AST Access

```gene
(code/ast some-function)  # Get AST
(code/ir some-function)   # Get compiled IR
```

### Tasks

- [ ] Build code index
- [ ] Implement query language
- [ ] AST/IR introspection APIs

---

## Phase 10: Module System

**Goal**: Proper modules with explicit exports.

### Module Definition

```gene
# src/my_app/user.gene
(module my_app/user
  ^exports [User create_user get_user])

(type User {
  ^id Int
  ^email String
  ^name (Option String)
  ^created_at DateTime
})

(fn create_user [email: String password: String] -> (Result User Error) ! [Db]
  ...)

(fn- helper [x: Int] -> Int  # Private (fn- not fn)
  ...)
```

### Imports

```gene
# Import specific items
(import my_app/user [User create_user])

# Import with alias
(import my_app/db :as db)
(db/query ...)

# Import all exports
(import my_app/utils :all)
```

### Tasks

- [ ] Implement module declaration
- [ ] Add export tracking
- [ ] Implement import resolution
- [ ] Private/public distinction
- [ ] Circular dependency detection

---

## Version Targets

| Phase | Feature | Version |
|-------|---------|---------|
| 1 | Type inference & checking | 0.1.0 |
| 2 | Result type & errors | 0.1.0 |
| 3 | Effect system | 0.2.0 |
| 4 | Contracts | 0.3.0 |
| 5 | Canonical formatter | 0.3.0 |
| 6 | Context system | 0.4.0 |
| 7 | Tool definitions | 0.5.0 |
| 8 | Observability | 0.6.0 |
| 9 | Code introspection | 0.7.0 |
| 10 | Module system | 0.8.0 |
| - | Stabilization | 1.0.0 |

---

## Breaking Change Policy

We freely make breaking changes that:

1. **Improve type safety** - Catch more errors at compile time
2. **Make effects explicit** - No hidden side effects
3. **Simplify semantics** - Fewer special cases
4. **Enable better AI integration** - More queryable, verifiable code

Each change must have clear benefit. We don't break things arbitrarily.

---

## See Also

- [ai-first.md](ai-first.md) - Language reference
- [examples/ai-first.gene](../examples/ai-first.gene) - Full example
- [architecture.md](architecture.md) - VM internals
