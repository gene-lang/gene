# Enum and ADT Unification

## Motivation

Gene currently has two disconnected systems for sum types:

1. **Enums** — simple symbolic constants with integer values (`VkEnum` + `VkEnumMember`)
2. **ADTs** — hardcoded `Ok`/`Err`/`Some`/`None` as stdlib functions that create Gene expressions

These share nothing at the runtime, compiler, or type-system level. Pattern matching
only recognizes the 4 hardcoded ADT names. You can't define your own variants or add
payloads to enum members.

This document specifies a unified **tagged enum** system where every variant can
optionally carry data, replacing both systems with a single coherent design.

## Syntax

### Simple Enums (no payloads)

```gene
(enum Color red green blue)
```

Backward-compatible syntax. Members are unit variants with no data.

### Enums with Payloads

```gene
(enum Shape
  (Circle radius)
  (Rect width height)
  Point)

# With type annotations on fields
(enum Shape
  (Circle radius: Float)
  (Rect width: Int height: Int)
  Point)

(enum Result
  (Ok value)
  (Err message))

(enum Option
  (Some value)
  None)
```

Each variant is either:
- A **unit variant**: just a name (`Point`, `None`, `red`)
- A **data variant**: name + named fields (`(Circle radius)`, `(Ok value)`)

Fields can optionally carry type annotations using Gene's `name: Type` syntax.
When present, the constructor validates argument types at runtime (and at compile
time when type inference is available). Untyped fields accept any value.

### Construction

```gene
# Unit variants — access directly
(var c Color/red)
(var p Shape/Point)
(var n Option/None)

# Data variants — call like a constructor
(var s (Shape/Circle 5.0))
(var r (Result/Ok 42))
(var e (Result/Err "not found"))

# Keyword args also work for multi-field variants
(var rect (Shape/Rect ^width 10 ^height 20))
```

Data variants behave as constructors: `Shape/Circle` is a callable that takes the
declared fields and returns an enum value.

### Field Access

```gene
(var s (Shape/Circle 5.0))
(println (s .radius))             # => 5.0

(var r (Shape/Rect 10 20))
(println (r .width) (r .height))  # => 10 20
```

Fields are accessed by name via method dispatch, like class instances.

### Pattern Matching

```gene
(case s
  (when (Circle r) (println "circle r=" r))
  (when (Rect w h) (println "rect" w h))
  (when Point (println "point")))

(case result
  (when (Ok v) (println "success:" v))
  (when (Err e) (println "error:" e)))
```

Pattern matching destructures by variant name and binds fields positionally.

### `?` Operator (Result/Option unwrap)

```gene
# Returns early with Err/None if not Ok/Some
(var value (risky_operation)?))
```

The `?` operator works on any enum that has a conventional success/failure split.
Initially hardcoded for `Result` and `Option`, later extensible via protocol.

### Enum Methods

```gene
(enum Color red green blue
  (method to_hex [self]
    (case self
      (when red "#ff0000")
      (when green "#00ff00")
      (when blue "#0000ff"))))
```

Methods defined inside enum bodies are dispatched through the enum's class.

## Internal Representation

### Type System

```
VkEnum       — the enum type definition (Color, Shape, Result)
VkEnumMember — a variant definition, also the value for unit variants
VkEnumValue  — an instantiated data variant with payload (NEW)
```

### EnumDef (existing, extended)

```nim
EnumDef* = ref object
  name*: string
  members*: OrderedTable[string, EnumMember]  # ordered for iteration
  methods*: Table[string, Value]               # NEW: enum-level methods
```

### EnumMember (existing, extended)

```nim
EnumMember* = ref object
  parent*: Value              # → VkEnum (the enum type)
  name*: string
  value*: int                 # ordinal value (auto-incrementing)
  fields*: seq[string]        # field names, empty for unit variants
  field_types*: seq[TypeId]   # field type annotations (0 = untyped/Any)
```

- `fields.len == 0` → unit variant (VkEnumMember IS the value)
- `fields.len > 0` → data variant (VkEnumMember is the constructor, VkEnumValue is the value)
- `field_types[i] != 0` → field `i` has a type constraint, checked at construction time

### VkEnumValue (new)

Added to `reference_types.nim`:

```nim
of VkEnumValue:
  ev_variant*: Value          # → VkEnumMember (which variant)
  ev_data*: seq[Value]        # payload values, positional
```

**Storage:**
- `ev_variant` points to the VkEnumMember definition (carries field names, parent enum)
- `ev_data` stores field values in the same order as `fields`
- Field access by name: look up index in `ev_variant.ref.enum_member.fields`, read `ev_data[index]`

**Examples:**
```
Color/red           → VkEnumMember { parent: Color, name: "red", value: 0, fields: [] }
Shape/Point         → VkEnumMember { parent: Shape, name: "Point", value: 2, fields: [] }
(Shape/Circle 5.0)  → VkEnumValue { variant: Shape/Circle, data: [5.0] }
(Shape/Rect 10 20)  → VkEnumValue { variant: Shape/Rect, data: [10, 20] }
```

### Why Not Reuse Gene or Instance

**Gene**: `Gene{type: "Ok", children: [42]}` — overloads Gene for a different purpose,
loses type information (no link to enum definition), can't distinguish from actual
Gene code.

**Instance**: Blurs enums with classes. Enum values should be structurally equal by
variant + data, not identity-equal like instances. Different dispatch rules.

## Pattern Matching Changes

### Current (Remove)

- `IkMatchGeneType` — checks `gene.type.str` against hardcoded "Ok"/"Err"/"Some"/"None"
- `IkGetGeneChild` — extracts child from Gene expression
- `is_result_option_pattern()` — hardcoded 4-name check in compiler

### New

- `IkMatchEnumVariant` — checks if value's variant matches expected name
  - For `VkEnumMember`: compare directly (unit variant match)
  - For `VkEnumValue`: check `ev_variant.ref.enum_member.name`
- `IkBindEnumFields` — destructure `ev_data` into local variables
  - Binds fields positionally from pattern: `(when (Circle r) ...)` binds `r = ev_data[0]`

### Exhaustiveness Checking (future)

With all variants known at compile time, the compiler can warn when a `case` doesn't
cover all variants. Not required for initial implementation but the data model supports it.

## Compiler Changes

### Enum Definition

`(enum Shape (Circle radius) (Rect width height) Point)` compiles to:

1. `IkCreateEnum "Shape"` — creates EnumDef, pushes to stack
2. `IkEnumAddMember "Circle" ^fields ["radius"]` — adds data variant
3. `IkEnumAddMember "Rect" ^fields ["width", "height"]` — adds data variant
4. `IkEnumAddMember "Point"` — adds unit variant (no fields)
5. Store in scope

### Variant Construction

`(Shape/Circle 5.0)` compiles to:

1. Resolve `Shape/Circle` → VkEnumMember
2. Check it's a data variant (`fields.len > 0`)
3. Compile argument expression `5.0`
4. `IkCreateEnumValue` — pops args + member, creates VkEnumValue

For unit variants, `Shape/Point` resolves directly to the VkEnumMember value.

### Pattern Matching

`(case s (when (Circle r) body) (when Point body2))` compiles to:

1. Compile `s`, push to stack
2. For each `when`:
   a. `IkMatchEnumVariant "Circle"` — check variant, jump to next arm if no match
   b. `IkBindEnumFields` — bind `r` from `ev_data[0]`
   c. Compile body
   d. Jump to end
3. Default: push nil

## Equality and Display

### Equality

```gene
(== Color/red Color/red)                    # => true (same VkEnumMember)
(== (Shape/Circle 5.0) (Shape/Circle 5.0))  # => true (structural)
(== (Shape/Circle 5.0) (Shape/Circle 3.0))  # => false
(== (Shape/Circle 5.0) (Shape/Rect 5 5))    # => false
```

- Unit variants: identity equal (same VkEnumMember pointer)
- Data variants: structural — same variant + all fields `==`

### Display (`to_s`)

```gene
(println Color/red)                  # => Color/red
(println Shape/Point)                # => Shape/Point
(println (Shape/Circle 5.0))         # => (Shape/Circle 5.0)
(println (Shape/Rect 10 20))         # => (Shape/Rect 10 20)
```

## Built-in Enums

Result and Option become regular enums in the stdlib, not hardcoded:

```gene
(enum Result
  (Ok value)
  (Err message))

(enum Option
  (Some value)
  None)
```

Registered in the global namespace during `init_stdlib`. The `?` operator is
initially hardcoded to recognize Result and Option enums by name, later extensible
via a protocol/interface.

## What Gets Removed

- `vm_ok`, `vm_err`, `vm_some`, `none_val` functions in `stdlib/core.nim`
- `IkMatchGeneType` instruction
- `IkGetGeneChild` instruction
- `IkUnwrap` logic that checks Gene expression type strings
- `is_result_option_pattern()` in compiler
- The `(type (Result T E) ...)` type alias syntax (replaced by `(enum Result ...)`)

## Implementation Phases

### Phase 1: Extend enum definition
- Add `fields: seq[string]` to `EnumMember`
- Add `VkEnumValue` to type system with `ev_variant`, `ev_data`
- Update `compile_enum` to parse data variant syntax `(Circle radius)`
- Update `IkEnumAddMember` to store field names
- Update `$` / `to_s` for new types
- Tests for simple and payload enum definitions

### Phase 2: Variant construction
- Make data variant members callable (constructor behavior)
- `IkCreateEnumValue` instruction — creates VkEnumValue from member + args
- Field access via method dispatch (`.radius`, `.width`)
- Keyword argument support for multi-field constructors
- Equality for VkEnumValue (structural)
- Tests for construction and field access

### Phase 3: Pattern matching
- Replace `IkMatchGeneType` with `IkMatchEnumVariant`
- Replace `IkGetGeneChild` with `IkBindEnumFields`
- Update `compile_case` to handle enum variant patterns
- Remove `is_result_option_pattern()` hardcoding
- Tests for pattern matching with custom enums

### Phase 4: Built-in Result/Option
- Define Result and Option as built-in enums in stdlib
- Update `?` operator to work with enum-based Result/Option
- Remove old `vm_ok`/`vm_err`/`vm_some`/`none_val` functions
- Remove old Gene-expression-based ADT code
- Migration: ensure all existing tests work with new representation

### Phase 5 (future): Exhaustiveness and methods
- Compile-time exhaustiveness warnings for case/when
- Enum-level method definitions
- Generic enum types: `(enum (Result T E) (Ok T) (Err E))`

## Files to Modify

- `src/gene/types/type_defs.nim` — add VkEnumValue, extend EnumMember
- `src/gene/types/reference_types.nim` — add VkEnumValue case
- `src/gene/types/core/constructors.nim` — new_enum_value constructor
- `src/gene/types/core/value_ops.nim` — equality, display, kind for VkEnumValue
- `src/gene/types/core/enums.nim` — extend enum operations
- `src/gene/compiler/control_flow.nim` — compile_enum, compile_case updates
- `src/gene/vm/exec.nim` — new instructions, remove old ADT instructions
- `src/gene/stdlib/core.nim` — built-in Result/Option enums, remove old ADT functions
- `spec/02-types.md` — update enum/ADT sections
- `spec/12-patterns.md` — update pattern matching section
- `testsuite/` — new and updated tests
