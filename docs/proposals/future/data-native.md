# Data Native — Design Document

Gene treats data manipulation as a first-class concern. Arrays, maps, and selectors are built-in primitives with ergonomic syntax for querying, transforming, and chaining operations.

## 1. Array Methods (Chaining)

All array methods support chaining via `;`. Non-mutating methods return new arrays/values; mutating methods (`push`/`pop`) modify in-place.

`;` is handled in the parsing stage.

(a b; c d; ^f 1 g) is parsed into (((a b) c d) ^f 1 g)

```gene
([5 3 1 4 2] .filter (fn [x] (x > 2)); .sort; .reverse; .take 2)
# => [5 4]
```

### Available Methods

#### Non-mutating (return new values)

| Method | Signature | Returns | Description |
|--------|-----------|---------|-------------|
| `map` | `.map (fn [x] ...)` | new array | Transform each element |
| `filter` | `.filter (fn [x] ...)` | new array | Keep elements matching predicate |
| `reduce` | `.reduce init (fn [acc x] ...)` | accumulated value | Fold left with initial value |
| `find` | `.find (fn [x] ...)` | element or `nil` | First element matching predicate |
| `any` | `.any (fn [x] ...)` | bool | True if any element matches |
| `all` | `.all (fn [x] ...)` | bool | True if all elements match |
| `sort` | `.sort` or `.sort (fn [a b] ...)` | new array | Natural ascending, or custom comparator (return negative/0/positive) |
| `reverse` | `.reverse` | new array | Reversed copy |
| `zip` | `.zip other` | new array of pairs | Combine element-wise, truncates to shorter |
| `take` | `.take n` | new array | First n elements |
| `skip` | `.skip n` | new array | Elements after first n |
| `each` | `.each (fn [x] ...)` | `nil` | Side-effect iteration |
| `to_map` | `.to_map` | map | Convert `[[key, val], ...]` pairs to map |

#### Mutating (modify in-place)

| Method | Signature | Returns | Description |
|--------|-----------|---------|-------------|
| `push` | `.push val` | new length (int) | Append element in-place |
| `pop` | `.pop` | removed element | Remove & return last element |

### Chaining with `;`

Semicolon pipes the result of the previous expression as the receiver for the next method call:

```gene
(arr .sort; .reverse; .take 3; .map (fn [x] (x * 2)))
# equivalent to:
((((arr .sort) .reverse) .take 3) .map (fn [x] (x * 2)))
```

## 2. Selectors

Selectors are XPath/CSS-selector-like path expressions for querying nested data structures. They are first-class values.

### Selector Literals

Symbols starting with `@` are selector literals:

```gene
@users           # select key "users"
@users/0/name    # path: key "users" → index 0 → key "name"
@users/*/name    # wildcard: iterate array, get "name" from each
```

### Applying Selectors

Selectors are callable — pass data as the argument:

```gene
(var data {^users [{^name "Alice"} {^name "Bob"}]})

(@users/0/name data)    # => "Alice"
(@users/*/name data)    # => ["Alice", "Bob"]

# Store and reuse
(var sel @users/*/name)
(sel data)               # => ["Alice", "Bob"]
```

### Explicit Constructor `(@)`

For dynamic segments (variables, functions), use the `(@)` constructor:

```gene
(var idx 1)
(var sel (@ "users" idx "name"))
(sel data)    # => "Bob"
```

### Segment Types

| Segment | Syntax | Behavior |
|---------|--------|----------|
| Key | `name` or `"name"` | Map key lookup |
| Index | `0`, `1` | Array index access |
| Wildcard | `*` | Iterate array, apply remaining path to each element |
| Function | `(fn [x] ...)` | Call with current value, use return as next value |
| Generator | `(fn* [x] ...)` | Collect yielded values as array |

### Function Segments

Functions receive the parent value as their argument:

```gene
# Transform step
(@ "users" (fn [xs] (xs .map (fn [x] x/name))))
# => ["Alice", "Bob"]

# Generator: yields become array
(@ "users" (fn* [xs]
  (for x in xs (yield x/name))))
# => ["Alice", "Bob"]
```

### Nil Safety

Missing keys and out-of-bounds indices return `nil` (no errors):

```gene
(@missing data)        # => nil
(@users/99/name data)  # => nil
(@users/0/foo data)    # => nil
```

### Method Syntax

Selectors can also be applied as methods on the receiver:

```gene
# Literal path as method
(data .@users/0/name)       # => "Alice"
(data .@users/*/name)       # => ["Alice", "Bob"]

# Explicit construction as method
(data .@ "users" 0 "name")  # => "Alice"
(data .@ "users" idx "name")  # dynamic segments

# Chaining selectors with array methods via ;
(data .@users; .filter (fn [u] (u/age > 25)); .map (fn [u] u/name))
# => ["Alice", "Carol"]
```

### Properties

- **Callable:** Yes — `(selector data)` applies the query
- **First-class:** Can be stored in variables, passed to functions, used in `map`/`filter`

## 3. Map Methods

Maps support methods for converting to arrays for processing:

```gene
(var m {^name "Alice" ^age 30 ^city "NYC"})

(m .keys)    # => ["name" "age" "city"]
(m .values)  # => ["Alice" 30 "NYC"]
(m .pairs)   # => [["name" "Alice"] ["age" 30] ["city" "NYC"]]
```

### Round-trip with Arrays

Convert maps to pairs, process with array methods, convert back:

```gene
# Remove a key
(m .pairs; .filter (fn [p] (p/0 != "age")); .to_map)
# => {^name "Alice" ^city "NYC"}

# Transform values
(m .pairs; .map (fn [p] [p/0 (str p/1)]); .to_map)
# => {^name "Alice" ^age "30" ^city "NYC"}
```

| Method | On | Returns |
|--------|-----|---------|
| `.keys` | Map | Array of key strings |
| `.values` | Map | Array of values |
| `.pairs` | Map | Array of `[key, value]` arrays |
| `.to_map` | Array | Map (input must be `[[string, any], ...]`) |

## 4. Database & ORM (stdlib — planned)

Gene's database layer provides an easy-to-use ORM built on **SQLite**. SQLite is the foundation — battle-tested, zero-config, ACID-compliant, and already integrated via Gene's `ffi_sqlite` bindings. The ORM makes it feel native to Gene.

### Quick Start

```gene
(import * as db "std/db")

# Open a database (SQLite file, or :memory: for tests)
(var app (db/open "app.db"
  (table `users
    (col `id    `int    ^^primary_key ^^auto)
    (col `name  `string ^^not_null)
    (col `email `string ^^unique)
    (col `age   `int))

  (table `posts
    (col `id      `int    ^^primary_key ^^auto)
    (col `user_id `int    ^foreign_key `users/id ^on_delete `cascade)
    (col `title   `string ^^not_null)
    (col `body    `string)
    (col `status  `string ^default "draft"))
))

# That's it — tables are created automatically
```

### Column Definition Syntax

Columns follow the pattern: `(col name type ^prop value ...)` where:
- **name** — symbol or string for the column name
- **type** — symbol for the data type
- **^prop value** — keyword arguments for constraints and options
- **^^prop** — shorthand for `^prop true`

#### Column Types

| Type | SQLite Type | Description |
|------|-------------|-------------|
| `` `int `` | INTEGER | Integer |
| `` `float `` | REAL | Floating point |
| `` `string `` | TEXT | Text |
| `` `bool `` | INTEGER (0/1) | Boolean |
| `` `blob `` | BLOB | Binary data |

#### Column Constraints (keyword arguments)

| Keyword | Description |
|---------|-------------|
| `^^primary_key` | Unique identifier, indexed |
| `^^auto` | Auto-increment (INTEGER PRIMARY KEY) |
| `^^not_null` | Rejects nil values |
| `^^unique` | No duplicate values |
| `^default val` | Default value on insert |
| `^foreign_key ref` | Foreign key reference (e.g. `` `users/id ``) |
| `^on_delete action` | Cascade behavior: `` `restrict ``, `` `cascade ``, `` `set_nil `` |

### CRUD Operations

```gene
# Create
(var alice (app/users .create {^name "Alice" ^email "alice@test.com" ^age 30}))
# => {^id 1 ^name "Alice" ^email "alice@test.com" ^age 30}

# Read
(app/users .find 1)                            # by primary key
(app/users .find_by `email "alice@test.com")   # by field
(app/users .all)                               # all rows

# Update
(app/users .update 1 {^age 31})

# Delete
(app/users .delete 1)
```

### Query Builder

Chainable methods that generate SQL behind the scenes:

```gene
# WHERE — field-based conditions (SQL-translatable)
(app/users .where {^age [> 25]})
# => SELECT * FROM users WHERE age > 25

# Multiple conditions
(app/users .where {^age [> 25] ^name ["Alice" "Bob"]})
# => SELECT * FROM users WHERE age > 25 AND name IN ('Alice', 'Bob')

# Select specific columns
(app/users .select [`name `age])
# => SELECT name, age FROM users

# Sort
(app/users .sort_by `age)
(app/users .sort_by `age `desc)

# Limit & offset
(app/users .limit 10 ^offset 20)

# Chain everything
(app/users
  .where {^age [> 25]}
  ; .sort_by `name
  ; .select [`name `email]
  ; .limit 10)

# Count & aggregate
(app/users .count)
(app/users .where {^age [> 30]}; .count)
(app/users .sum `age)
(app/users .avg `age)
```

#### Where Conditions

The `.where` method takes a map of field → condition pairs that translate directly to SQL:

| Gene | SQL |
|------|-----|
| `{^age 25}` | `age = 25` |
| `{^age [> 25]}` | `age > 25` |
| `{^age [>= 25]}` | `age >= 25` |
| `{^age [< 25]}` | `age < 25` |
| `{^name "Alice"}` | `name = 'Alice'` |
| `{^name ["Alice" "Bob"]}` | `name IN ('Alice', 'Bob')` |
| `{^email nil}` | `email IS NULL` |
| `{^name [like "A%"]}` | `name LIKE 'A%'` |
| `{^age [between 20 30]}` | `age BETWEEN 20 AND 30` |

For complex queries that can't be expressed as conditions, use `.where_fn` (in-memory filter on results):

```gene
(app/users .where_fn (fn [r] (r/name .starts_with "A")))
```

### Integration with Gene Data Methods

Query results are regular Gene arrays of maps — all array methods and selectors work:

```gene
(app/users .where {^age [> 25]}
  ; .map (fn [r] r/name)
  ; .sort
  ; .reverse)
# => ["Carol" "Alice"]

# Selectors work on results
(app/users .all; .@ */name)
# => ["Alice" "Bob" "Carol"]
```

### Relationships

Foreign keys define relationships. The ORM resolves them automatically:

```gene
# belongs_to — post.user_id → users.id
(var post (app/posts .find 1))
(post .belongs_to `users)
# => {^id 1 ^name "Alice" ...}

# has_many — user.id ← posts.user_id
(var alice (app/users .find 1))
(alice .has_many `posts)
# => [{^id 1 ^title "Hello" ...} {^id 2 ^title "World" ...}]

# Joins (SQL JOIN)
(app/posts .join `users)
# => [{^id 1 ^title "Hello" ^user {^id 1 ^name "Alice" ^age 30}} ...]

(app/posts .join `users; .@ */user/name)
# => ["Alice" "Bob"]

# Eager loading (avoid N+1 queries)
(app/users .include `posts)
# => [{^id 1 ^name "Alice" ^posts [{...} {...}]}
#     {^id 2 ^name "Bob" ^posts [{...}]}]

# Left join
(app/posts .left_join `comments)
```

### Validations

```gene
(app/users .validate
  (fn [r]
    (if (r/age < 0)
      (throw "age cannot be negative"))
    (if_not (r/email .contains "@")
      (throw "invalid email"))))

(app/users .create {^name "Bad" ^email "nope" ^age -5})
# => Error: invalid email
```

### Hooks

```gene
(app/users .before_create (fn [r]
  (r .set ^created_at (now))))

(app/users .after_create (fn [r]
  (print "Created user: " r/name "\n")))
```

### Transactions

```gene
(app .transaction (fn []
  (var user (app/users .create {^name "Alice" ^email "alice@test.com"}))
  (app/posts .create {^user_id user/id ^title "First post"})
  # If any operation fails, all changes roll back
))
```

### Migrations

```gene
# Add columns
(app .migrate
  (alter `users
    (add_col `status `string ^default "active")
    (add_col `created_at `int)))

# Rename a column
(app .migrate
  (alter `users
    (rename_col `name `full_name)))

# Add a new table
(app .migrate
  (table `tags
    (col `id   `int    ^^primary_key ^^auto)
    (col `name `string ^^unique)))
```

### Raw SQL Escape Hatch

When the ORM isn't enough:

```gene
(app .query "SELECT * FROM users WHERE age > ? AND name LIKE ?" [25 "A%"])
(app .exec "UPDATE users SET age = age + 1 WHERE id = ?" [1])
```

### Architecture

```
┌─────────────────────────────────────┐
│  Gene ORM API                       │  .create .find .where .join ...
│  (easy-to-use, Gene-native)         │
├─────────────────────────────────────┤
│  Query Builder                      │  Translates method chains → SQL
├─────────────────────────────────────┤
│  SQLite (via ffi_sqlite)            │  Storage, indexing, transactions
└─────────────────────────────────────┘
```

- **`:memory:`** for tests and ephemeral data
- **File-based** for persistence (default)
- **Future:** PostgreSQL/MySQL adapters behind the same ORM API

### Design Goals

1. **Easy to use** — minimal boilerplate, sensible defaults, just works
2. **Gene-native** — results are maps/arrays, work with selectors and array methods
3. **SQL-translatable** — `.where` conditions compile to SQL, not in-memory filters
4. **SQLite-powered** — leverage battle-tested storage, don't reinvent it
5. **Escape hatch** — raw SQL when the ORM isn't enough
6. **Progressive** — start with `:memory:`, switch to file when ready

## 6. `.gdat` — Gene Data Files

Save and load any Gene value to gzip-compressed files:

```gene
(cap_grant "cap.fs.read")
(cap_grant "cap.fs.write")

(gdat/save data "app.gdat")
(var loaded (gdat/load "app.gdat"))
```

**Current implementation:** Gene Value → JSON → gzip → file (works today)

### File Format

`.gdat` files use a block comment header for format identification:

```
#< gdat 1.0 >#
{^users [{^name "Alice" ^age 30} {^name "Bob" ^age 25}]}
```

### 🔴 HIGH PRIORITY: Native Gene Format

**Status: TODO**

Replace JSON serialization with Gene's own syntax:

**What's needed:**
1. `gene/parse` native — parse Gene text string into a value (data only, no code execution)
2. Update `gdat/save` to use `toDebugString` (Gene syntax) instead of `json/stringify`
3. Update `gdat/load` to use `gene/parse` instead of `json/parse`
4. Add `#< gdat 1.0 >#` header on save, validate on load

**Why this matters:**
- **Self-describing** — `.gdat` files are human-readable Gene syntax (just gunzip to inspect)
- **Richer types** — preserves symbols, keywords, gene expressions that JSON can't represent
- **No JSON dependency** — Gene becomes fully self-contained for data serialization
- **Dog-fooding** — Gene should use Gene for its own data format

## 7. Block Comments

Gene supports inline/block comments with `#< ... >#`:

```gene
#< This is a block comment >#

(var x #< inline ># 42)

#<
  Multi-line
  block comment
>#

#< Nested #< comments ># are supported >#
```

Block comments are used for the `.gdat` file header: `#< gdat 1.0 >#`

## Design Principles

1. **Eager by default** — all operations return results immediately
2. **Method chaining** — `;` enables fluent pipelines
3. **Selectors as functions** — selectors are callable, composable query objects
4. **Nil-safe navigation** — missing paths return `nil`, not errors
5. **No lambda shorthand** — use `(fn [x] ...)` explicitly
6. **No flat_map** — use `map` + custom logic
7. **Canonical column syntax** — `(col name type ^prop value ...)` with keyword args for constraints
