# Builder Pattern Design: $emit for Collection Construction

## Goal

Enable expressive collection construction with `$emit` to add elements dynamically during array, map, and gene expression evaluation. This allows for flexible data generation patterns without requiring template syntax.

### Motivation

**Current limitation:**
```gene
# To conditionally/iteratively build collections, need templates:
($render :[
  %(for i in [1 2 3]
    ($emit (* i 2)))
  5
])  # => [2 4 6 5]
```

**Desired capability:**
```gene
# Natural collection building in literals:
[
  (for i in [1 2 3]
    ($emit (* i 2)))
  5
]  # => [2 4 6 5]

# Conditional emission
[
  (for user in users
    (if user.active
      ($emit user.name)))
]

# Map building
($map
  (for pair in data
    ($emit pair.key pair.value)))
```

## Design

### Core Concept

1. **`$emit` function** adds values to the container currently being constructed
2. **Returns `VkVoid`** which is filtered out during collection building
3. **Container stack** tracks nested collection construction contexts

### Builder Functions vs Literals

Different collection types use different approaches:

- **Arrays `[...]`**: Literal syntax with `$emit` support - natural for lists
- **Maps `($map ...)`**: Builder function - maps have explicit key-value structure, function is clearer
- **Gene expressions `(...)`**: Literal syntax with `$emit` support - natural S-expression syntax

**Why `($map ...)` instead of `{...}`?**

Map literals have explicit structure:
```gene
{^key1 value1 ^key2 value2}  # Keys use ^ prefix
```

Supporting `$emit` in this syntax would be ambiguous:
```gene
{($emit :key value)}  # Not valid - position matters in map literals
```

Builder function is clearer:
```gene
($map ($emit :key value))  # Explicit: building a map with dynamic pairs
```

**Benefits of `$map` function approach:**
- Clear intent: explicitly building a map
- No syntax ambiguity with map literals
- Consistent with other builder patterns
- Easy to extend (e.g., `($map {} ...)` to start with initial map)

### Collection Construction Summary

| Type | Static Syntax | Dynamic Builder | `$emit` Args |
|------|---------------|-----------------|--------------|
| Array | `[1 2 3]` | `[(for i in data ($emit i))]` | 1 value |
| Map | `{^k1 v1 ^k2 v2}` | `($map (for x in data ($emit k v)))` | 2 values (key, value) |
| Gene | `(type a b)` | `(type (for i in data ($emit i)))` | 1 value |
| Template | `:(a %b)` | `($render :(a %(for i in x ($emit i))))` | 1 value |

### Container Stack

Add to VM state:
```nim
type VM = object
  # ... existing fields
  container_stack: seq[Value]  # Active containers being built
```

**Lifecycle:**
- Push container when construction starts (array/map/gene literal)
- `$emit` adds to `container_stack[^1]`
- Pop container when construction completes
- Empty when not building collections

### VkVoid Filtering

Collection construction filters out `VkVoid` values:

```nim
# Array building (pseudocode)
of IkArrayBuild:
  let arr = new_gene_array()
  for each element_value on stack:
    if element_value.kind != VkVoid:
      arr.add(element_value)
  # VkVoid silently omitted
```

This allows expressions to participate in collection building without contributing a value themselves.

### Implementation Approach

**1. Array Literals: `[a b c]`**
```nim
# Compilation
compile_array([a b c]):
  emit(IkArrayStart)        # Push empty array to container_stack
  compile(a)                # May call $emit
  compile(b)
  compile(c)
  emit(IkArrayEnd, count=3) # Build array, filter VkVoid, pop stack

# Execution
of IkArrayStart:
  let arr = new_gene_array()
  vm.container_stack.add(arr)
  vm.stack.push(arr)

of IkArrayEnd:
  let count = read_int()
  let arr = vm.container_stack.pop()  # Get from container stack
  for i in 0..<count:
    let val = vm.stack.pop()
    if val.kind != VkVoid:
      arr.insert(val, 0)  # Reverse stack order
  vm.stack.push(arr)
```

**2. Map Builder Function: `($map ...)`**
```nim
# $map is a function that creates container context
proc builtin_map(vm: VM, args: seq[Value]): Value =
  let map = new_gene_map()
  vm.container_stack.add(map)

  # Evaluate body (args[0]) - may call $emit
  let result = vm.eval(args[0])

  discard vm.container_stack.pop()
  return map

# $emit with 2 args adds key-value pair
```

**3. Gene Expressions: `(type a b c)`**
```nim
# IkGeneStart/IkGeneEnd similar to arrays
# Type is first element, rest are children
```

**4. Templates: `($render :(...))` (already supported)**
```nim
# Template rendering already creates context
# Now uses same container_stack mechanism
```

**5. $emit Implementation**
```nim
proc builtin_emit(vm: VM, args: seq[Value]): Value =
  if vm.container_stack.len == 0:
    vm.error("$emit can only be used during collection construction")

  let container = vm.container_stack[^1]

  case container.kind
  of VkArray:
    container.arr.add(args[0])

  of VkMap:
    if args.len != 2:
      vm.error("$emit in map requires 2 args: key and value")
    container.map[args[0].to_key()] = args[1]

  of VkGene:
    container.gene_children.add(args[0])

  else:
    vm.error("Invalid container type for $emit")

  return VkVoid  # Filtered out by collection builder
```

## Performance Implications

### Overhead

**Per-literal cost:**
- 1 push + 1 pop on `container_stack` (seq[Value])
- 1 `kind != VkVoid` check per element
- Negligible: ~2 pointer ops + 1 comparison per literal

**Memory:**
- `container_stack: seq[Value]` on VM struct: 24 bytes
- Stack depth = nesting level (typically 1-3)
- Pre-allocated seq has minimal allocation overhead

### Optimization: Lazy Allocation

**Fast path (no $emit):**
```gene
[1 2 3]  # No $emit used - just VkVoid checks (near-zero cost)
```

**Only overhead when needed:**
```gene
[(for i in [1 2] ($emit i))]  # Container stack used
```

The `container_stack.len` check in `$emit` is the only runtime cost for non-emit code.

### Compared to Alternatives

**Template-only approach:**
```gene
($render :[...])  # Function call + context allocation overhead
```

**Builder pattern:**
```gene
[...]  # Direct construction with inline emit support
```

Builder is **faster** - no function call, no separate render context allocation.

## Examples

### Basic Emission
```gene
[(for i in [1 2 3] ($emit i)) 4]
# => [1 2 3 4]
```

### Conditional Emission
```gene
[
  (for x in [1 2 3 4 5]
    (if (> x 2)
      ($emit x)))
]
# => [3 4 5]
```

### Multiple Emissions per Iteration
```gene
[
  (for i in [1 2]
    (do
      ($emit i)
      ($emit (* i 10))))
]
# => [1 10 2 20]
```

### Map Construction
```gene
# Basic map building
($map
  (for user in users
    ($emit user.id user.name)))
# => {^id1 "Alice" ^id2 "Bob"}

# Conditional map entries
($map
  (for user in users
    (if user.active
      ($emit user.id user.name))))

# Transform keys and values
($map
  (for [k v] in (pairs data)
    ($emit
      (str "prefix_" k)
      (* v 2))))
```

### Gene Expression Building
```gene
(div
  (for item in items
    ($emit (li item.text))))
# => (div (li "text1") (li "text2") ...)
```

### Nested Collections
```gene
[
  (for row in data
    ($emit
      [(for col in row ($emit col))]))
]
# => [[1 2] [3 4] [5 6]]
```

### Template Compatibility
```gene
# Still works with templates
($render :[
  %(for i in [1 2] ($emit i))
])
# => [1 2]
```

## Trade-offs

### Pros
- **Expressive**: Natural syntax for data generation
- **Flexible**: Conditionals, loops, any control flow
- **Efficient**: Minimal overhead, lazy allocation
- **Consistent**: Same pattern for arrays, maps, gene expressions
- **Backward compatible**: Templates still work

### Cons
- **Complexity**: Adds VM state (`container_stack`)
- **Debugging**: `$emit` failures might be confusing (wrong context)
- **Mental model**: Users need to understand VkVoid filtering

### Edge Cases

**$emit outside collection:**
```gene
(var x ($emit 5))  # Error: no container context
```

**$emit in nested function:**
```gene
[
  (fn helper [] ($emit 1))
  (helper)  # Error: helper's frame has no container context
]
```

**Solution:** `$emit` only works in the immediate expression context of a literal, not through function boundaries.

**Workaround for functions:**
```gene
[
  (fn helper [] 1)  # Return value instead
  (helper)  # Added to array normally
]
```

## Future Extensions

### 1. Spread Operator
```gene
[1 ...other_array 4]  # Splice array inline
# Implemented as: (for x in other_array ($emit x))
```

### 2. Comprehensions
```gene
[for x in data if (> x 5) (* x 2)]
# Sugar for: [(for x in data (if (> x 5) ($emit (* x 2))))]
```

### 3. Generator Functions
```gene
(gen fibonacci []
  ($emit 1)
  ($emit 1)
  (while true
    ($emit (+ prev1 prev2))))

[...(take 10 (fibonacci))]  # Use spread
```

## Relationship to XPath/XSLT

This builder pattern enables XSLT-like generative templates:

**XSLT:**
```xml
<xsl:for-each select="users/user">
  <li><xsl:value-of select="name"/></li>
</xsl:for-each>
```

**Gene with $emit:**
```gene
(ul
  (for user in users
    ($emit (li user.name))))
```

The `$emit` mechanism provides the "generative" capability that makes template systems powerful, without requiring a separate template context.

## Implementation Checklist

- [ ] Add `container_stack: seq[Value]` to VM
- [ ] Implement `IkArrayStart`/`IkArrayEnd` with stack management
- [ ] Implement `IkGeneStart`/`IkGeneEnd` with stack management
- [ ] Update compiler to emit Start/End instructions for array and gene literals
- [ ] Implement `builtin_emit` function (1 or 2 args)
- [ ] Implement `builtin_map` function (creates map container context)
- [ ] Add VkVoid filtering to array/gene collection builders
- [ ] Update template rendering to use container_stack
- [ ] Add tests for array emission
- [ ] Add tests for gene expression emission
- [ ] Add tests for map emission with `$map`
- [ ] Add tests for nested collections
- [ ] Add tests for error cases (emit outside container)
- [ ] Add tests for conditional/loop-based emission
- [ ] Update documentation with examples

## References

- Gene Template System: `tests/test_template.nim`
- VM Architecture: `src/gene/vm.nim`
- Compiler: `src/gene/compiler.nim`
- Value Types: `src/gene/types.nim`
