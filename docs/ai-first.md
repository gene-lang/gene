# AI-First Language Design for Gene

Gene is an AI-native language: statically typed with inference, explicit effects, and machine-verifiable contracts. Optimized for AI to write, read, and execute - while remaining clear to humans.

## Core Language Properties

### Static Typing with Inference

Types are inferred at compile time. Explicit annotations optional for clarity.

```gene
# Inferred types
(var count 0)           # count: Int
(var name "alice")      # name: String
(var items [1 2 3])     # items: Array[Int]
(var scores {^a 95 ^b 87})  # scores: Map[Symbol, Int]

# Explicit when needed
(var ratio: Float 1)    # Force Float, not Int

# Function types inferred from body
(fn double [x]          # (Int) -> Int
  (x * 2))

# Explicit signature
(fn divide [a: Int b: Int] -> Result[Int, Error]
  ...)
```

### S-Expression Syntax with Properties

Regular, predictable syntax. Properties (`^key value`) attach metadata.

```gene
(type ^prop1 value1 ^prop2 value2 child1 child2)
```

### Homoiconicity

Code is data. Macros transform code as data structures.

## Type System

### Primitive Types

```gene
Int Float Bool String Symbol Char Nil
```

### Compound Types

```gene
Array[T]              # [1 2 3]: Array[Int]
Map[K, V]             # {^a 1}: Map[Symbol, Int]
Tuple[A, B, ...]      # (: 1 "a"): Tuple[Int, String]
Option[T]             # Some[T] | None
Result[T, E]          # Ok[T] | Err[E]
```

### Function Types

```gene
(A, B) -> R           # Pure function
(A, B) -> R ! [E1, E2] # Function with effects
```

### Generic Functions

```gene
(fn first [arr: Array[T]] -> Option[T]
  (if (arr .empty?)
    None
    (Some arr/0)))

(fn map [arr: Array[T] f: (T) -> U] -> Array[U]
  ...)
```

### Union Types

```gene
(type UserId (Int | String))
(type ApiResult (Ok[Data] | Err[ApiError] | Loading))
```

## Effect System

Effects are part of the type signature. Compiler enforces effect boundaries.

### Declaring Effects

```gene
# Pure - no effects (default if no ! clause)
(fn add [a: Int b: Int] -> Int
  (a + b))

# With effects
(fn save [user: User] -> Result[User, DbError] ! [Db]
  (db/insert user))

# Multiple effects
(fn process [id: Int] -> Result[Data, Error] ! [Db, Http, Log]
  (var user (db/get id))
  (var data (http/fetch user/.url))
  (log/info "processed" id)
  (Ok data))
```

### Standard Effects

```gene
Db          # Database read/write
Http        # Network requests
Io          # File system
Log         # Logging
Env         # Environment variables
Time        # Current time
Random      # Random numbers
Console     # stdin/stdout
```

### Effect Handlers

```gene
(with-handler Db (mock-db)
  (test-user-creation))

(with-handler Http (recorded-responses)
  (replay-api-calls))
```

## Contracts

### Preconditions and Postconditions

```gene
(fn withdraw [account: Account amount: Int] -> Result[Account, Error] ! [Db]
  ^pre [(amount > 0)
        (account/.balance >= amount)]
  ^post [(result .is_ok) => (result/.value/.balance == account/.balance - amount)]

  (db/update account ^balance (account/.balance - amount)))
```

### Contract Checking Modes

```
gene run --contracts=on    # Check at runtime (dev/test)
gene run --contracts=off   # Skip checks (production)
gene check                 # Static verification where possible
```

## Structured Errors

### Result Type

```gene
(type Result[T, E] (Ok[T] | Err[E]))

# Creating results
(Ok 42)
(Err ^code "db/NOT_FOUND" ^entity "user" ^id 123)

# Pattern matching
(match (fetch-user id)
  (Ok user) (process user)
  (Err e)   (log/error e/.code))
```

### Namespaced Error Codes

```gene
# Errors are namespaced for stable taxonomy
"db/NOT_FOUND"
"db/CONNECTION_FAILED"
"http/TIMEOUT"
"auth/FORBIDDEN"
"validation/INVALID_EMAIL"
```

## Function Metadata

### Intent and Documentation

```gene
(fn create_user [email: String password: String] -> Result[User, Error] ! [Db, Email]
  ^intent "Create user account with email verification"
  ^version "1.0.0"

  ...)
```

### Examples as Tests

```gene
(fn fibonacci [n: Int] -> Int
  ^examples [
    {^in [0] ^out 0}
    {^in [1] ^out 1}
    {^in [10] ^out 55}
  ]

  (if (n < 2) n
    (+ (fibonacci (n - 1)) (fibonacci (n - 2)))))
```

Run with `gene test --examples`.

## Context System

Explicit context passing replaces global state.

```gene
# Provide context
(with-context [
  (user_id 123)
  (permissions ["read" "write"])
  (db (connect db_url))
]
  (handle-request request))

# Require context
(fn handle-request [req: Request] -> Response ! [Db]
  ^requires [user_id permissions]

  (if (not ($ctx/.permissions .includes "write"))
    (Err ^code "auth/FORBIDDEN")
    (process req)))
```

## Tool Definitions

First-class tools for AI function calling.

```gene
(tool create_user
  ^description "Create a new user account"
  ^params {
    ^email {^type String ^format "email"}
    ^password {^type String ^min 8}
    ^name {^type String ^optional true}
  }
  ^returns (Result User Error)
  ^effects [Db Email]
  ^errors [
    "validation/INVALID_EMAIL"
    "validation/WEAK_PASSWORD"
    "db/DUPLICATE_EMAIL"
  ]
  ^examples [
    {^in {^email "a@b.com" ^password "secret123"}
     ^out (Ok (User ^id 1 ^email "a@b.com"))}
  ]

  [email password name]
  ...)
```

## Observability

### Tracing

```gene
(with-trace
  (complex-operation data))
# Returns: {^result ... ^trace [...]}
```

### Dry Run

```gene
(dry-run
  (db/insert user)
  (email/send welcome))
# Returns effect list without executing
```

### Checkpoints

```gene
(var cp (checkpoint))
(try
  (risky-op)
catch
  (restore cp)
  (fallback-op))
```

## Code Introspection

```gene
# Query codebase
(code/find ^type Fn ^has_effect Db)
(code/find ^returns (Result * *) ^error_codes ["db/*"])

# Get function metadata
(code/meta some_function)
# => {^intent "..." ^effects [Db] ^params [...] ...}

# Get AST
(code/ast some_function)
```

## Canonical Formatting

`gene fmt` produces deterministic output:

1. Properties in standard order
2. Consistent indentation
3. Deterministic for same semantics

```bash
gene fmt file.gene        # Format
gene fmt --check file.gene # Verify canonical
```

## Module System

```gene
# my_app/user.gene
(module my_app/user
  ^exports [User create_user get_user])

(type User {
  ^id Int
  ^email String
  ^name (Option String)
})

(fn create_user [email: String] -> Result[User, Error] ! [Db]
  ...)
```

```gene
# main.gene
(import my_app/user [User create_user])
(import my_app/db :as db)

(fn main [] -> Nil ! [Db Console]
  (var user (create_user "test@example.com"))
  (println user))
```

## Summary: Design Principles

1. **Static types, inferred** - Compiler knows all types, you write few
2. **Effects are types** - Side effects tracked in signatures
3. **Contracts are code** - Preconditions/postconditions, not comments
4. **Errors are values** - Result types, not exceptions
5. **Context is explicit** - No hidden globals
6. **Code is data** - Queryable, transformable
7. **Deterministic formatting** - AI-safe round-trips
