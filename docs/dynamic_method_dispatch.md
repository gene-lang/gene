# Dynamic Method Dispatch Implementation

## Problem Statement

The Gene VM currently only supports static method dispatch where method names must be known at compile time. This limitation prevents patterns like:

```gene
(var action "index")
(var controller (new Controller))
(var result (controller . action "test"))  # FAILS - action is a variable
```

The reference interpreter (gene-new) supports this feature, but the bytecode VM does not.

## Root Cause Analysis

### Parse Structure

The parser creates different structures for static vs dynamic method calls:

**Static** (`(controller .index "test")`):
```
(controller          # type
  .index            # children[0] - method name embedded
  "test"            # children[1]
)
```

**Dynamic** (`(controller . action "test")`):
```
(controller          # type
  .                 # children[0] - separator only
  action            # children[1] - variable to evaluate
  "test"            # children[2]
)
```

### Current Compiler Behavior

In `src/gene/compiler.nim:1963-1968`:

```nim
else:
  # (obj .method_name args...) - obj is explicit
  self.compile(gene.type)
  let first = gene.children[0]
  method_name = first.str[1..^1]  # Extract "index" from ".index"
  method_value = method_name.to_symbol_value()
  start_index = 1
```

**Problem**: When `first.str` is just `"."`, the code extracts an empty string and treats it as a compile-time constant. The method name in `children[1]` is never evaluated.

### Current VM Behavior

In `src/gene/vm.nim:5804-5811` (IkUnifiedMethodCall2):

```nim
of IkUnifiedMethodCall2:
  let call_info = self.pop_call_base_info(2)
  let method_name = inst.arg0.str  # Method name from instruction
  let arg2 = self.frame.pop()
  let arg1 = self.frame.pop()
  let obj = self.frame.pop()
```

**Problem**: The method name comes from `inst.arg0.str` (a compile-time constant). There's no way to get the method name from the stack at runtime.

## Solution Design

### Approach

Instead of creating new instructions, we can leverage the existing infrastructure by compiling the method name expression and handling it at runtime.

### Compiler Changes

Modify `compile_method_call` in `src/gene/compiler.nim` around line 1963:

```nim
else:
  # (obj .method_name args...) - obj is explicit
  self.compile(gene.type)
  let first = gene.children[0]

  # Check if this is dynamic dispatch: (obj . variable ...)
  if first.kind == VkSymbol and first.str == ".":
    # Dynamic dispatch - method name comes from children[1]
    let method_expr = gene.children[1]

    # Compile the method name expression (pushes value onto stack)
    self.compile(method_expr)

    # Compile remaining arguments
    for i in 2..<gene.children.len:
      self.compile(gene.children[i])

    # Emit dynamic method call instruction
    let arg_count = gene.children.len - 2
    if arg_count == 0:
      self.emit(Instruction(kind: IkDynamicMethodCall0))
    elif arg_count == 1:
      self.emit(Instruction(kind: IkDynamicMethodCall1))
    elif arg_count == 2:
      self.emit(Instruction(kind: IkDynamicMethodCall2))
    else:
      self.emit(Instruction(
        kind: IkDynamicMethodCall,
        arg1: (arg_count + 1).int32  # +1 for self
      ))
    return  # Early return - don't continue with static path

  # Static dispatch - method name is in children[0]
  method_name = first.str[1..^1]
  method_value = method_name.to_symbol_value()
  start_index = 1
```

### New Instruction Types

Add to `InstructionKind` enum in `src/gene/types.nim`:

```nim
IkDynamicMethodCall0
IkDynamicMethodCall1
IkDynamicMethodCall2
IkDynamicMethodCall   # For 3+ arguments
```

### VM Implementation

Add handlers in `src/gene/vm.nim` after existing UnifiedMethodCall handlers:

```nim
of IkDynamicMethodCall2:
  {.push checks: off}
  # Stack layout (top to bottom):
  # - arg2
  # - arg1
  # - method_name (string/symbol)
  # - obj

  let call_info = self.pop_call_base_info(3)  # 3 items before obj
  let arg2 = self.frame.pop()
  let arg1 = self.frame.pop()
  let method_name_value = self.frame.pop()
  let obj = self.frame.pop()

  # Convert method name value to string
  var method_name: string
  case method_name_value.kind:
  of VkString:
    method_name = method_name_value.str
  of VkSymbol:
    method_name = method_name_value.str
  else:
    not_allowed("Method name must be string or symbol, got " & $method_name_value.kind)

  # Handle super methods
  if obj.kind == VkSuper:
    let saved_frame = self.frame
    if call_super_method(self, obj, method_name, [arg1, arg2], @[]):
      if self.frame == saved_frame:
        self.pc.inc()
      inst = self.cu.instructions[self.pc].addr
      continue

  # Try value method call for non-instance types
  if obj.kind notin {VkInstance, VkCustom}:
    if call_value_method(self, obj, method_name, [arg1, arg2]):
      self.pc.inc()
      inst = self.cu.instructions[self.pc].addr
      continue

  # Instance/Custom object method call
  case obj.kind:
  of VkInstance, VkCustom:
    let class = obj.get_object_class()
    if class.is_nil:
      not_allowed("Object has no class for method call")

    # NOTE: Cannot use inline cache for dynamic dispatch
    # since method name is not known at compile time

    var meth = class.get_method(method_name)
    if meth.is_nil:
      meth = class.get_inherited_method(method_name)

    if meth.is_nil:
      not_allowed("Method " & method_name & " not found on " & class.name)

    call_method(self, obj, meth, [arg1, arg2], @[])
  else:
    not_allowed("Method " & method_name & " not found on " & $obj.kind)
  {.pop}
```

Similar implementations needed for:
- `IkDynamicMethodCall0` (no args)
- `IkDynamicMethodCall1` (one arg)
- `IkDynamicMethodCall` (3+ args)

### Performance Considerations

**Trade-offs**:
- **Static dispatch**: Fast (uses inline cache for method lookup)
- **Dynamic dispatch**: Slower (no inline cache, runtime string conversion)

**Optimization opportunities** (future):
1. Could cache last-used method name + class → method mapping
2. Could use a small LRU cache for dynamic dispatch
3. For now, correctness > performance

## Implementation Plan

### Phase 1: Core Implementation
1. ✅ Analyze problem and design solution
2. Add new instruction types to `InstructionKind`
3. Modify compiler to detect and handle dynamic dispatch
4. Implement VM handlers for new instructions
5. Test with simple examples

### Phase 2: Testing
1. Create unit tests for dynamic dispatch
2. Test with http_todo_app
3. Test edge cases:
   - Method name from various value types
   - Non-existent methods
   - Super method calls
   - Macro-like methods

### Phase 3: Optimization (Optional)
1. Profile performance impact
2. Implement caching if needed
3. Document performance characteristics

## Testing Strategy

### Unit Tests

```gene
# Test 1: Basic dynamic dispatch
(class Controller
  (method index req "index called")
  (method create req "create called")
)

(var action "index")
(var controller (new Controller))
(var result (controller . action "test"))
(assert (result == "index called"))

# Test 2: Variable method name
(action = "create")
(result = (controller . action "test"))
(assert (result == "create called"))

# Test 3: Method name from expression
(var actions ["index" "create"])
(result = (controller . (actions / 0) "test"))
(assert (result == "index called"))

# Test 4: Error handling
(try
  (controller . "nonexistent" "test")
catch e
  (assert ($type e) == "Exception"))
```

### Integration Test

Run `examples/http_todo_app.gene` and verify:
- Server starts
- Routes are dispatched correctly
- All HTTP methods work

## Backward Compatibility

This change is **fully backward compatible**:
- Existing static method calls continue to work unchanged
- New dynamic dispatch syntax is additive
- No breaking changes to existing code

## Alternative Approaches Considered

### Alternative 1: Rewrite http_todo_app
**Pros**: No VM changes needed
**Cons**: Limits language expressiveness, not a real solution

### Alternative 2: Use function call instead of method call
```gene
(var action_fn (controller . action))  # Get bound method
(action_fn "test")  # Call it
```
**Pros**: Works with current VM
**Cons**: Not idiomatic, awkward syntax

### Alternative 3: Use match/case statement
```gene
(match action
  "index" (controller .index "test")
  "create" (controller .create "test")
)
```
**Pros**: Works with current VM
**Cons**: Not scalable, violates DRY

## References

- Reference interpreter dynamic dispatch: `gene-new/src/gene/features/oop.nim:369` (`eval_invoke_dynamic`)
- Current compiler method call handling: `src/gene/compiler.nim:1953`
- Current VM method call execution: `src/gene/vm.nim:5804`
- Gene syntax reference: `examples/full.gene`

## Status

- **Design**: ✅ Complete
- **Implementation**: ⏳ Ready to start
- **Testing**: ⏳ Pending implementation
- **Documentation**: ✅ This document
