# Spread Operator Design

## Overview

Gene supports a spread operator (`...`) for unpacking collections into collection literals and function arguments:
- **Arrays**: Spread elements into arrays or gene children using `...` syntax
- **Maps**: Spread key-value pairs into maps using `^...` syntax
- **Gene Properties**: Spread map key-value pairs into gene properties using `^...` syntax

The spread operator transforms a collection into individual items that are inserted at the spread location.

## Key Features

✅ **Works everywhere**: Spread works in **arrays**, **gene expressions** (children and properties), and **maps**
✅ **Any position**: `(f a... [2 3] ... "end")` - spread can appear anywhere in children
✅ **Two syntaxes for arrays/gene children**: Variable suffix `a...`, standalone postfix `expr ...`
✅ **Map spread syntax**: `{^... map}` spreads map's key-value pairs
✅ **Gene properties spread**: `(div ^... attrs child)` spreads map into gene properties
✅ **No marker type**: Handled at compile-time, no runtime overhead
✅ **Type-safe**: Arrays spread to arrays/gene children, maps spread to maps/gene properties

## Terminology

Gene uses **"spread"** terminology consistently:
- **User-facing**: "spread operator" (`...`)
- **Syntax**: The `...` symbol in various contexts
- **Instructions**: `IkArrayAddSpread`, `IkGeneAddSpread`, etc.
- **Documentation**: "spread" terminology

This aligns with industry-standard terminology from JavaScript/ES6+ and other modern languages.

## Syntax

Gene provides spread operators for different collection types:

### For Arrays and Gene Expressions

Two spread syntaxes:

### 1. Variable Suffix: `variable...`
```gene
(var a [1 2 3])
[a... 4 5]  # => [1 2 3 4 5]
```

The `...` suffix is parsed as part of the variable name and compiled to:
- Variable resolution (get the value)
- Appropriate spread instruction based on context

### 2. Standalone Postfix: `expression ...`
```gene
# Spread variable
(var a [1 2])
[a ... 4 5]  # => [1 2 4 5]

# Spread expression result
[(+ 1 2) ... 4]  # Evaluates (+ 1 2) → 3, error: can only spread arrays

# Spread function result
[(get_array) ... 4 5]

# In gene expressions
(f a ... [2 3] ...)
```

The standalone `...` acts as a postfix operator that spreads the value at the top of the stack:
- Evaluate the preceding expression (pushes value to stack)
- Appropriate spread instruction (spreads stack top)

This is the general form - it works with any expression that evaluates to an array.

### Syntax Comparison

Both forms are equivalent when spreading a simple variable:
```gene
(var a [1 2])

# In arrays:
[a...]           # Variable suffix - most concise
[a ...]          # Standalone postfix - more explicit

# In gene expressions (function calls):
(f a...)         # Variable suffix
(f a ...)        # Standalone postfix

# Both produce same result!
```

**When to use each:**

1. **Variable suffix `a...`**: Most concise for spreading variables
   ```gene
   [a... b... c...]
   (f args1... args2...)
   ```

2. **Standalone postfix `expr ...`**: For expressions and when you want clarity
   ```gene
   [(get_array) ... 4 5]
   (f a... [2 3] ... "end")
   [(do_something) ...]
   ```

**The standalone postfix form is more general** - it clearly shows "evaluate this expression, then spread it" and works with **any expression**, not just variables.

### For Maps

Maps use a special spread syntax with the `^` key prefix:

```gene
# Single map spread
{^a 1 ^... other_map}

# Variable map spread
(var defaults {^x 10 ^y 20})
{^... defaults ^y 30}  # => {^x 10 ^y 30} (later keys override)

# Multiple map spreads - use indexed syntax
{^... base ^...1 overrides ^...2 (create_map)}

# Expression spread
{^... (get_defaults) ^custom "value"}
```

**Map spread syntax:**
- `^...` spreads first map
- `^...1` spreads second map (index starts at 1)
- `^...2` spreads third map, etc.
- Later keys override earlier ones (like JavaScript `{...obj1, ...obj2}`)

**Why indexed syntax?**
Since maps are key-value collections, we can't use postfix `expr ...` (what would it mean to "spread after" a key-value pair?). Instead, we use `^...`, `^...1`, `^...2` as special keys that trigger spreading.

### For Gene Properties

Gene expressions can have properties (like HTML attributes), and you can spread maps into them:

```gene
# Single property spread
(var attrs {^class "btn" ^id "submit"})
(button ^... attrs "Click me")  # => (button ^class "btn" ^id "submit" "Click me")

# Multiple spreads with overrides
(var base_attrs {^class "widget" ^data-id "123"})
(var extra_attrs {^style "color: red"})
(div ^... base_attrs ^...1 extra_attrs ^class "widget active" child1 child2)
# ^class gets overridden to "widget active"

# Conditional attributes
(input ^type "text" ^... (if required {^required true} {}))

# Expression spread
(component ^... (get_default_props) ^custom_prop "value" child)
```

**Gene property spread syntax:**
- Same as map spread: `^...`, `^...1`, `^...2`
- Properties come before children in gene syntax
- Later properties override earlier ones
- Useful for component props, HTML attributes, metadata

**Gene structure:**
```gene
(type ^prop1 val1 ^prop2 val2 child1 child2)
      ↑____________↑          ↑__________↑
       properties              children
```

Both sections support spread!

## Usage Contexts

### Array Literals
```gene
(var a [1 2])
(var b [3 4])

# Multiple spreads in one array (both syntaxes)
[a... b... 5]           # Variable suffix
[a ... b ... 5]         # Standalone postfix

# Mix with regular elements
[0 a... 99]             # => [0 1 2 99]
[0 a ... 99]            # => [0 1 2 99] (same result)

# Spread expression results
[(get_array) ... 10]    # Spread the result of function call
```

### Function Arguments / Gene Expressions
```gene
(var args [1 2 3])
(println args...)  # Equivalent to: (println 1 2 3)

# Mix positional and spread
(fn add3 [a b c] (+ a b c))
(add3 args...)  # => 6

# Spread can appear anywhere in argument list
(f a... [1 2] ...)  # Spreads a, passes [1 2], spreads [1 2]
(println "start" vals... "end")

# Gene expression children
(var children [(li "Item 1") (li "Item 2")])
(ul children...)  # => (ul (li "Item 1") (li "Item 2"))

# Multiple spreads in gene
(div header... body... footer...)
```

### Map Literals
```gene
(var defaults {^host "localhost" ^port 8080})
(var overrides {^port 3000})

# Spread defaults, override specific keys
{^... defaults ^port 9000}  # => {^host "localhost" ^port 9000}

# Merge multiple maps
{^... defaults ^...1 overrides}  # => {^host "localhost" ^port 3000}

# Spread with additional keys
{^... base ^env "production" ^... extra}

# Common pattern: defaults + overrides
(fn create_config [opts]
  {^... default_config ^...1 opts})
```

**Key collision behavior:**
- Later keys override earlier keys
- `{^a 1 ^... {^a 2}}` → `{^a 2}`
- `{^... {^a 1} ^a 2}` → `{^a 2}`
- Same semantics as JavaScript spread: `{...obj1, ...obj2}`

### Gene Properties (Attributes)
```gene
# HTML-like attributes
(var button_attrs {^class "btn" ^type "button"})
(button ^... button_attrs ^id "submit" "Submit")
# => (button ^class "btn" ^type "button" ^id "submit" "Submit")

# Component props
(var base_props {^size "medium" ^variant "primary"})
(MyComponent ^... base_props ^size "large" child1 child2)
# ^size overridden to "large"

# Conditional props
(fn Button [disabled]
  (button
    ^type "button"
    ^... (if disabled {^disabled true ^class "btn-disabled"} {})
    "Click"))

# React/JSX-like spread
(var item {^key "123" ^title "Hello" ^value 42})
(ListItem ^... item)  # Spreads all properties

# Multiple spreads with base + overrides
(div
  ^... default_styles
  ^...1 (if hover hover_styles {})
  ^...2 custom_styles
  (span "Content"))
```

**Use cases:**
- HTML attributes in templates
- Component prop forwarding (like React `{...props}`)
- Conditional attribute sets
- Style merging
- Metadata spreading

## Implementation

### Design Philosophy

**No marker type needed!** The spread operator is handled entirely at compile time. The parser keeps `...` as a regular symbol, and the compiler recognizes it in context to emit appropriate spread instructions.

**Key insight**: We don't need a runtime `VkSpread` marker value. The compiler can determine at compile time whether to spread or not, and emit the correct instruction.

### Compilation Strategy

The compiler detects spread syntax and emits specialized instructions:

#### 1. Variable Suffix: `a...`
```nim
# Compiler recognizes variable...
if symbol_str.endsWith("..."):
  let base_symbol = symbol_str[0..^4]
  self.compile_variable(base_symbol)  # Push variable value
  # Context determines instruction:
  # - In array: IkArrayAddSpread
  # - In gene children: IkGeneAddSpread
```

#### 2. Standalone Postfix: `expr ...`
```nim
proc compile_array(self: Compiler, input: Value) =
  self.output.instructions.add(Instruction(kind: IkArrayStart))

  var i = 0
  while i < input.ref.arr.len:
    let child = input.ref.arr[i]

    # Look ahead for ... operator
    if i + 1 < input.ref.arr.len:
      let next = input.ref.arr[i + 1]
      if next.kind == VkSymbol and next.str == "...":
        # Spread pattern: compile element, emit spread instruction
        self.compile(child)
        self.output.instructions.add(Instruction(kind: IkArrayAddSpread))
        i += 2  # Skip both element and ...
        continue

    # Normal element
    self.compile(child)
    self.output.instructions.add(Instruction(kind: IkArrayAdd))
    i += 1

  self.output.instructions.add(Instruction(kind: IkArrayEnd))

proc compile_gene_children(self: Compiler, gene: ptr Gene) =
  # Same lookahead logic for gene children
  var i = 0
  while i < gene.children.len:
    let child = gene.children[i]

    # Look ahead for ... operator
    if i + 1 < gene.children.len:
      let next = gene.children[i + 1]
      if next.kind == VkSymbol and next.str == "...":
        # Spread pattern: compile element, emit spread instruction
        self.compile(child)
        self.output.instructions.add(Instruction(kind: IkGeneAddSpread))
        i += 2  # Skip both element and ...
        continue

    # Normal child
    self.compile(child)
    self.output.instructions.add(Instruction(kind: IkGeneAdd))
    i += 1
```

#### 3. Map Spread: `^... map`
```nim
proc compile_map(self: Compiler, input: Value) =
  self.output.instructions.add(Instruction(kind: IkMapStart))

  for k, v in map_data(input):
    let key_str = k.to_string()  # Convert Key to string

    # Check for spread keys: ^..., ^...1, ^...2, etc.
    if key_str == "...":
      # Single spread: {^... map}
      self.compile(v)  # Evaluate map expression
      self.output.instructions.add(Instruction(kind: IkMapSpread))
    elif key_str.match(re"^\.\.\.(\d+)$"):
      # Indexed spread: {^...1 map1 ^...2 map2}
      self.compile(v)
      self.output.instructions.add(Instruction(kind: IkMapSpread))
    else:
      # Normal key-value: {^key value}
      self.compile(v)
      self.output.instructions.add(Instruction(kind: IkMapSetProp, arg0: k))

  self.output.instructions.add(Instruction(kind: IkMapEnd))
```

#### 4. Gene Property Spread: `(gene ^... map)`
```nim
proc compile_gene(self: Compiler, gene: ptr Gene) =
  self.output.instructions.add(Instruction(kind: IkGeneStart))

  # Compile properties (key-value pairs like maps)
  for k, v in gene.props:
    let key_str = k.to_string()

    # Check for spread keys in properties: ^..., ^...1, ^...2
    if key_str == "...":
      self.compile(v)  # Evaluate map expression
      self.output.instructions.add(Instruction(kind: IkGenePropsSpread))
    elif key_str.match(re"^\.\.\.(\d+)$"):
      self.compile(v)
      self.output.instructions.add(Instruction(kind: IkGenePropsSpread))
    else:
      # Normal property
      self.compile(v)
      self.output.instructions.add(Instruction(kind: IkGeneSetProp, arg0: k))

  # Compile children (with lookahead for ...)
  # ... (see compile_gene_children above)

  self.output.instructions.add(Instruction(kind: IkGeneEnd))
```

**Key points:**
- Parser keeps `...` as a regular symbol everywhere (including in map keys and gene props)
- Compiler uses lookahead in arrays AND gene children
- Compiler recognizes `^...` pattern in map keys AND gene properties
- Emits context-appropriate spread instructions
- Works in any position: `(f a... b ... c)` or `{^... base ^key val}` or `(div ^... attrs child)`
- No runtime marker type needed

### VM Instructions

The VM has specialized instructions for each spread context:

#### Array Spread: `IkArrayAddSpread`
```nim
of IkArrayAdd:
  # Normal add: pop value, add to array
  let value = self.frame.pop()
  self.frame.current().ref.arr.add(value)

of IkArrayAddSpread:
  # Spread add: pop array, add all elements
  let value = self.frame.pop()
  case value.kind:
    of VkArray:
      for item in value.ref.arr:
        self.frame.current().ref.arr.add(item)
    else:
      not_allowed("... can only spread arrays")
```

#### Gene Spread: `IkGeneAddSpread`
```nim
of IkGeneAdd:
  # Normal add: pop value, add to gene children
  let value = self.frame.pop()
  self.frame.current().gene.children.add(value)

of IkGeneAddSpread:
  # Spread add: pop array, add all elements
  let value = self.frame.pop()
  case value.kind:
    of VkArray:
      for item in value.ref.arr:
        self.frame.current().gene.children.add(item)
    else:
      not_allowed("... can only spread arrays in gene expressions")
```

#### Map Spread: `IkMapSpread`
```nim
of IkMapSetProp:
  # Normal key-value: pop value, set in map
  let key = inst.arg0.Key
  let value = self.frame.pop()
  map_data(self.frame.current())[key] = value

of IkMapSpread:
  # Spread map: pop source map, copy all key-value pairs
  let source = self.frame.pop()
  case source.kind:
    of VkMap:
      for k, v in map_data(source):
        # Later keys override earlier keys
        map_data(self.frame.current())[k] = v
    else:
      not_allowed("^... can only spread maps")
```

#### Gene Properties Spread: `IkGenePropsSpread`
```nim
of IkGeneSetProp:
  # Normal property: pop value, set in gene props
  let key = inst.arg0.Key
  let value = self.frame.pop()
  self.frame.current().gene.props[key] = value

of IkGenePropsSpread:
  # Spread properties: pop source map, copy all key-value pairs to gene props
  let source = self.frame.pop()
  case source.kind:
    of VkMap:
      for k, v in map_data(source):
        # Later properties override earlier properties
        self.frame.current().gene.props[k] = v
    else:
      not_allowed("^... in gene properties can only spread maps")
```

**Benefits:**
- No marker type cluttering the value system
- Clear, specialized instructions for each context
- Spread determined at compile time (static)
- Better performance (no marker wrapping/unwrapping)
- Natural key override semantics for maps and gene properties
- Gene properties work exactly like maps (both use `^key value` syntax)

## Design Decisions

### Type Safety: Arrays and Maps Only

The spread operator **only accepts arrays and maps** depending on context:

```gene
[... 42]        # Error: ... can only spread arrays
[... "hello"]   # Error: ... can only spread arrays
{^... 42}       # Error: ^... can only spread maps
{^... [1 2]}    # Error: ^... can only spread maps
```

**Rationale:**

1. **Type Safety**: The developer should know what type they're working with. If you're spreading a value, you should know it's the right collection type.

2. **Context-Specific**:
   - In arrays/genes: Only arrays can spread
   - In maps: Only maps can spread
   - This prevents confusing type mismatches

3. **Fail Fast**: Attempting to spread the wrong type likely indicates a bug. Failing immediately helps catch errors early.

4. **Explicit Intent**: If you want a single element, write it directly: `[x]` not `[... x]`.

5. **Consistency**: Spreading implies "unpack multiple items." A scalar has nothing to unpack.

### Alternative Considered: Identity Operation

We could make `... scalar` be a no-op (just use the scalar as-is):

```gene
[... 42]  # Could return [42]
```

**Rejected because:**
- Hides bugs (spreading the wrong type silently works)
- Unclear semantics (is it unpacking or not?)
- Reduces type awareness

### Supported Collection Types

Gene supports spread for:

- **Arrays**: Spread elements into arrays or gene expressions
  ```gene
  [1 ... [2 3] 4]  # => [1 2 3 4]
  (f args... more...)
  ```

- **Maps**: Spread key-value pairs into maps
  ```gene
  {^a 1 ^... other_map}  # Merge maps
  {^... defaults ^...1 overrides}
  ```

### Future Extensions

Possible future spread support:

- **Sets**: Spread elements into another set
  ```gene
  #{1 2 ... other_set}
  ```

- **Generators**: Spread lazy sequences
  ```gene
  [(take 10 fibonacci) ...]
  ```

## Edge Cases

### Empty Collections
```gene
# Empty array
[1 ... [] 2]  # => [1 2]

# Empty map
{^a 1 ^... {}}  # => {^a 1}
```
Spreading empty collections adds no elements.

### Nested Spread
```gene
# Arrays - not recursive
[... [1 2 [3 4]]]  # => [1 2 [3 4]]

# Maps - not recursive
{^... {^a {^b 1}}}  # => {^a {^b 1}} (nested map stays nested)
```
Spread is not recursive - nested structures remain as-is.

### Multiple Spreads
```gene
# Arrays
[a... b... c...]  # Spreads multiple arrays

# Maps - later keys override
{^... base ^...1 overrides ^...2 final}
```
Each spread is independent and processed left-to-right.

### Key Override in Maps
```gene
{^a 1 ^... {^a 2} ^b 3}  # => {^a 2 ^b 3}
{^... {^a 1} ^... {^a 2}}  # => {^a 2}
{^... base ^a 99}  # ^a in base gets overridden
```
Later keys override earlier keys - same as JavaScript `{...obj1, ...obj2}`.

### Spread in Spread
```gene
# Arrays - double spread of same value
(var x [1 2])
[x ... ...]  # Error: second ... sees VkArray on stack, spreads again

# Cleaner: just use one spread
[x ...]  # => [1 2]
```

Note: Spreading an already-spread value would require the stack to contain individual elements, but spread consumes the array in one operation. Just use a single spread.

## Examples

### Flatten One Level
```gene
(var nested [[1 2] [3 4] [5 6]])
(var flat [])
(for arr in nested
  (flat = (concat flat arr...)))
# flat => [1 2 3 4 5 6]

# Or using array builder with postfix spread:
(fn flatten [nested]
  [(for arr in nested arr ...)])
```

### Prepend/Append to Array
```gene
(var arr [2 3 4])
(var prepended [1 arr...])      # => [1 2 3 4]
(var prepended2 [1 arr ...])    # => [1 2 3 4] (postfix)
(var appended [arr... 5])       # => [2 3 4 5]
(var appended2 [arr ... 5])     # => [2 3 4 5] (postfix)
```

### Merge Arrays
```gene
(var a [1 2])
(var b [3 4])
(var c [5 6])

# Both syntaxes work:
(var merged1 [a... b... c...])     # Variable suffix
(var merged2 [a ... b ... c ...])  # Standalone postfix

# Both produce: [1 2 3 4 5 6]
```

### Variadic Function Arguments
```gene
(fn sum [& args]
  (reduce args 0 (fnx [acc x] (+ acc x))))

(var numbers [1 2 3 4 5])
(sum numbers...)  # => 15

# Spread in different positions
(var args1 [1 2])
(var args2 [4 5])
(my_fn args1... 3 args2...)  # Equivalent to: (my_fn 1 2 3 4 5)
```

### Spread Anywhere in Arguments
```gene
# Before regular args
(printf "%s %d %s" ["Hello" 42] ... "World")
# Equivalent to: (printf "%s %d %s" "Hello" 42 "World")

# After regular args
(println "Start:" vals... "End")

# Multiple spreads mixed with regular args
(format-string template... defaults... overrides... opts...)

# Your example: spread in middle
(f a... [2 3] ...)
# Compiles to:
#   IkGeneStart
#   compile(a) → IkGeneAddSpread
#   compile([2 3]) → IkGeneAdd
#   (lookahead sees ...) → IkGeneAddSpread
#   IkGeneEnd
```

### Dynamic Gene Construction
```gene
(var items ["Apple" "Banana" "Orange"])
(ul
  (for item in items
    (li item))...)
# => (ul (li "Apple") (li "Banana") (li "Orange"))
```

### Spreading Function Results
```gene
# In arrays
(fn get_numbers [] [1 2 3])
[(get_numbers) ... 4 5]  # => [1 2 3 4 5]

# In function calls - your example!
(var a [1])
(f a... [2 3] ...)
# Equivalent to: (f 1 [2 3] 2 3)
# First spreads a → 1
# Passes [2 3] as-is
# Then spreads [2 3] → 2 3

# With do block
(println
  (do
    (var x (compute_values))
    (filter x some_predicate))
  ...
  "done")

# User's original array example
[a ... [2 3] ... 4]  # => [1 2 3 4]
```

### Conditional Spread
```gene
(var debug true)
(var base_args ["-o" "output.txt"])
(var args [
  base_args...
  (if debug ["-v" "-d"] [])...
])
# If debug=true: ["-o" "output.txt" "-v" "-d"]
# If debug=false: ["-o" "output.txt"]
```

### Map Merging and Configuration
```gene
# Defaults + overrides pattern
(var defaults {^host "localhost" ^port 8080 ^debug false})
(var user_config {^port 3000})

(var config {^... defaults ^...1 user_config})
# => {^host "localhost" ^port 3000 ^debug false}

# Environment-specific config
(fn create_config [env]
  {
    ^... base_config
    ^...1 (if (== env "production") prod_config {})
    ^...2 (if (== env "development") dev_config {})
  })

# Conditional map merging
{
  ^... defaults
  ^...1 (if enable_feature feature_opts {})
  ^custom "value"
}
```

### Map Spread with Overrides
```gene
# HTTP request options
(var default_headers {^"Content-Type" "application/json" ^"Accept" "*/*"})
(var auth_headers {^"Authorization" "Bearer token123"})

(fn make_request [url opts]
  {
    ^method "GET"
    ^url url
    ^... {^headers {^... default_headers ^...1 auth_headers}}
    ^...1 opts
  })

# Database connection
(var db_defaults {
  ^host "localhost"
  ^port 5432
  ^database "app"
  ^pool_size 10
})

(fn connect [opts]
  (db/connect {^... db_defaults ^...1 opts}))

(connect {^host "prod.example.com" ^ssl true})
# => {^host "prod.example.com" ^port 5432 ^database "app"
#     ^pool_size 10 ^ssl true}
```

### Gene Properties Spread Examples

```gene
# HTML templating with attribute spreading
(fn render_button [text attrs]
  (button
    ^type "button"
    ^class "btn"
    ^... attrs  # Spread user attributes
    text))

(render_button "Submit" {^id "submit-btn" ^class "btn-primary"})
# => (button ^type "button" ^class "btn-primary" ^id "submit-btn" "Submit")
# Note: ^class gets overridden

# Component composition
(fn Card [props & children]
  (div
    ^class "card"
    ^... props
    children...))

(Card {^id "card-1" ^data-testid "test"} (h1 "Title") (p "Content"))

# Conditional attributes based on state
(fn Input [value disabled]
  (input
    ^type "text"
    ^value value
    ^... (if disabled {^disabled true ^class "input-disabled"} {})
    ^... (if (> (len value) 0) {^data-filled true} {})))

# Style object spreading (CSS-in-JS like)
(var base_styles {^display "flex" ^padding "10px"})
(var responsive_styles {^flex-direction "column" ^gap "5px"})

(div
  ^... {^style {^... base_styles ^...1 responsive_styles}}
  "Content")

# React-like prop forwarding
(fn Wrapper [props & children]
  (div ^class "wrapper" ^... props children...))

(fn MyComponent [all_props]
  (Wrapper all_props... (span "Child")))

# Merge base props with overrides
(fn create_element [type base_props override_props & children]
  (gene
    type
    ^... base_props
    ^...1 override_props
    children...))

(create_element
  "button"
  {^class "btn" ^type "button"}
  {^class "btn-large" ^id "submit"}
  "Click Me")
# => (button ^class "btn-large" ^type "button" ^id "submit" "Click Me")
```

## Implementation Checklist

### Core Functionality
- [ ] New VM instructions:
  - [ ] `IkArrayAdd` (normal add, rename from `IkArrayAddChild`)
  - [ ] `IkArrayAddSpread` (spread add in arrays)
  - [ ] `IkGeneAdd` (normal add, rename from `IkGeneAddChild`)
  - [ ] `IkGeneAddSpread` (spread add in gene children)
  - [ ] `IkGeneSetProp` (set single property in gene)
  - [ ] `IkGenePropsSpread` (spread map into gene properties)
  - [ ] `IkMapSpread` (spread key-value pairs from source map to target map)
- [ ] Compiler support:
  - [ ] `var...` suffix syntax → `IkArrayAddSpread` or `IkGeneAddSpread` based on context
  - [ ] Standalone `expr ...` syntax with lookahead in arrays
  - [ ] Standalone `expr ...` syntax with lookahead in gene children
  - [ ] `^...` pattern in map keys → `IkMapSpread`
  - [ ] `^...` pattern in gene properties → `IkGenePropsSpread`
  - [ ] `^...N` indexed spread (where N is 1, 2, 3, etc.) for maps and gene props
  - [ ] Context tracking (array vs gene children vs gene props vs map)
- [ ] Array literal spread handling: `[a... b ... c]`
- [ ] Gene children spread handling: `(f a... [2 3] ...)`
- [ ] Gene properties spread handling: `(div ^... attrs ^class "x" child)`
- [ ] Map literal spread handling: `{^... base ^...1 overrides}`
- [ ] Spread can appear **anywhere** in children/arguments/keys/properties
- [ ] Type checking in VM instructions:
  - [ ] Arrays for array/gene children spread
  - [ ] Maps for map spread and gene properties spread

### Cleanup (Remove Old Approach)
- [ ] Remove `VkExplode`/`VkSpread` from types.nim
- [ ] Remove `IkSpread` instruction (replaced by context-specific ones)
- [ ] Update all VM code to use new instructions
- [ ] Update error messages to use "spread" terminology

### Testing & Documentation
- [x] Tests in testsuite/arrays/1_basic_arrays.gene
- [ ] Tests for standalone postfix syntax
- [ ] Additional tests for edge cases
- [ ] Documentation in user guide

### Benefits of New Design
- ✅ No marker type needed - simpler value system
- ✅ Compile-time spread detection - better performance
- ✅ Context-specific instructions - clearer semantics
- ✅ Easier to understand and maintain

## Performance

### New Design (No Marker)

**Overhead:**
- No marker allocation needed!
- Direct unpacking during collection building

**Cost per spread operation:**
1. `IkArrayAddSpread`/`IkGeneAddSpread`: Pop array, iterate and add elements
2. Total: O(N) where N is the size of the spread array

**Performance benefits vs marker approach:**
- ✅ No marker allocation/deallocation
- ✅ One less instruction (no separate wrap/unwrap)
- ✅ Better instruction cache locality
- ✅ Simpler runtime behavior

### Old Design (With Marker) - For Comparison

**Overhead:**
- Creating `VkExplode` marker: 1 allocation + 1 instruction
- Unpacking during collection building: Check marker type, iterate

**Cost:**
1. `IkSpread`: Pop value, wrap in marker, push marker (~3 stack ops + allocation)
2. `IkArrayAddChild`: Pop value, check if marker, unwrap and iterate

**Why new design is better:**
The marker approach adds unnecessary indirection and allocation for something that can be determined at compile time.

## References

- **Types**: `src/gene/types.nim`
  - `InstructionKind`: Add `IkArrayAdd`, `IkArrayAddSpread`, `IkGeneAdd`, `IkGeneAddSpread`, `IkGeneSetProp`, `IkGenePropsSpread`, `IkMapSpread`
  - Remove: `VkExplode` type (no longer needed)
- **Compiler**: `src/gene/compiler.nim`
  - `compile_array()`: Lookahead for `...` symbol, emit appropriate instruction
  - `compile_gene()`: Lookahead for `...` in children, check `^...` in properties
  - `compile_map()`: Check for `^...` and `^...N` keys, emit `IkMapSpread`
  - `compile_symbol()`: Recognize `var...` suffix syntax
- **VM**: `src/gene/vm.nim`
  - `IkArrayAdd`: Normal element addition
  - `IkArrayAddSpread`: Array element spreading
  - `IkGeneAdd`: Normal child addition
  - `IkGeneAddSpread`: Array element spreading to gene children
  - `IkGeneSetProp`: Normal property setting
  - `IkGenePropsSpread`: Map spreading to gene properties (with override semantics)
  - `IkMapSpread`: Map key-value pair spreading (with override semantics)
- **Tests**:
  - `testsuite/arrays/1_basic_arrays.gene` (lines 23-27) - Array spread
  - TBD: Map spread tests
  - TBD: Gene properties spread tests

## Design Rationale

### Why No Marker Type?

**The Problem with Markers:**
```nim
# Old approach:
compile(expr)       # Push value
IkSpread           # Pop, wrap in VkExplode, push marker
IkArrayAddChild    # Pop marker, check type, unwrap, iterate
```

**The Solution:**
```nim
# New approach:
compile(expr)       # Push value
IkArrayAddSpread   # Pop array, iterate, add elements
```

**Key insight:** Spread is a **compile-time** decision, not a runtime value property. We know at compile time whether something should be spread, so we can emit the right instruction directly.

**Benefits:**
1. Simpler value system (one less type)
2. Better performance (no allocation/deallocation)
3. Clearer semantics (instruction names say what they do)
4. Easier to extend (just add new spread instructions for new contexts)
