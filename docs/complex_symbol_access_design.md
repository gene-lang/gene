# Complex Symbol Access Design

This document explains how the VM compiler rewrites complex symbol
expressions when they are used as definition targets (class names,
variables, and assignments). The goal is to allow slash-delimited
paths such as `geometry/shapes/Circle` or `/status` while using
efficient compile-time resolution.

## Compilation Strategy

The compiler transforms complex symbols **before** emitting bytecode
using a stack-based approach for better performance:

- `(class A/B ...)` → Compile A, push to stack → Compile B as member of stack top
- `(class geometry/shapes/Circle ...)` → Compile geometry → Compile shapes → Compile Circle as member of shapes
- `(var /a value)` → Compile self, push to stack → Compile a as member of self
- `(/a = value)` → Compile self, push to stack → Set member on stack top

## Compilation Rules

### Class Definitions
**Single-segment**: `(class A/B ...)`
1. Compile container `A` and push to stack
2. Compile class `B` using `IkClassAsMember` with stack top as target
3. Result: `B` class stored as member of `A`

**Multi-segment**: `(class A/B/C ...)`
1. Compile `A` → push to stack
2. Compile `B` as member of `A` → push result to stack
3. Compile `C` as member of stack top (which is `B`)
4. Result: `C` class stored as member of `B`, which is member of `A`

### Variable Declarations
**Leading slash**: `(var /a value)`
1. Compile `self` and push to stack
2. Compile variable `a` as member of stack top
3. Result: `a` stored as member of current instance

**Complex container**: `(var container/a value)`
1. Compile `container` and push to stack
2. Compile variable `a` as member of stack top
3. Result: `a` stored as member of `container`

### Assignments
**Leading slash**: `(/a = value)`
1. Compile `self` and push to stack
2. Set member on stack top using `IkSetMember`
3. Result: `a` member updated on current instance

**Complex target**: `(container/prop = value)`
1. Compile `container` and push to stack
2. Set member on stack top using `IkSetMember`
3. Result: `prop` member updated on `container`

## Numeric Segment Handling

When the final segment is numeric, the compiler uses child access instructions:

- `(arr/0 = value)` → Compile `arr` → Use `IkSetChild` with index 0
- `(g/1 = value)` → Compile `g` → Use `IkSetChild` with index 1
- `(data/items/2 = value)` → Compile `data/items` → Set member `items` → Use `IkSetChild` with index 2

## VM Instructions Used

### Existing Instructions
- `IkClass`: Standard class creation
- `IkClassAsMember`: Create class as member of existing object (or extend IkClass with member flag)
- `IkSetMember`: Set property on object
- `IkSetChild`: Set child element in array/gene

### Required Enhancements
- **IkClassAsMember**: If not exists, extend `IkClass` with `arg1 = 1` flag to signal member creation
- **Stack Management**: Ensure proper stack ordering for multi-segment resolution

## Advantages

1. **Compile-time Resolution**: No runtime container lookup overhead
2. **Simple Implementation**: Uses existing VM infrastructure
3. **Predictable Behavior**: Containers resolved at compile time
4. **Better Performance**: No dynamic evaluation needed
5. **Clear Semantics**: Stack-based compilation is intuitive

## Leading Slash Semantics

A leading `/` always represents `self` in the current context:
- Class methods: `/property` refers to the instance
- Global scope: `/variable` refers to current namespace or global scope
- Nested contexts: `/property` resolves to nearest `self`

## Container Type Support

The system supports multiple container types automatically:
- **Namespaces**: Classes stored in namespace hierarchy
- **Classes**: Properties and methods stored on class objects
- **Instances**: Properties set on object instances
- **Maps**: Key-value pairs in map objects
- **Arrays/Gene**: Child element modification via numeric indexing

## Examples

```gene
(class geometry/shapes/Circle
  (method area _
    (* /radius /radius 3.14)
  )
)

(class Record
  (var /table "todos")
  (var /columns ["id" "description" "status"])
)

(method set_status [value]
  (/status = value)
)

; Numeric tail segments use child access
(var arr [1 2 3])
(arr/0 = 10)  # Compiles to IkSetChild 0
(println arr/0)
```

All three cases rely on the same rewriting rule internally, allowing
the rest of the compiler to consume a simple identifier plus a
`^container` property.
