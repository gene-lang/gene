## Context

Gene's VM dispatches method calls through various instruction handlers (`IkCallMethod1`, `IkUnifiedMethodCall*`, etc.). When a method is not found, the VM currently throws a `not_allowed` error. This change adds a fallback mechanism via `method_missing`.

The `ClassObj` type already has a commented-out `method_missing` field at `src/gene/types/type_defs.nim:371`, indicating this was anticipated.

## Goals / Non-Goals

**Goals:**
- Enable dynamic method dispatch via `method_missing` hook
- Support inheritance (child inherits parent's `method_missing`)
- Minimal performance impact on normal method calls (fast path unchanged)
- Simple, Ruby-like semantics

**Non-Goals:**
- Property access interception (`obj/foo`) - out of scope
- `respond_to` style introspection - can be added later
- `method_missing!` macro variant - can be added later if needed
- Per-instance method_missing - classes only

## Decisions

### Decision 1: Store method_missing as Value, not Method
**What:** The `method_missing` field stores a `Value` (function) rather than a `Method` object.
**Why:** Simpler implementation. The method_missing handler is looked up once and called directly. No need for method table indirection.

### Decision 2: Lookup method_missing via class hierarchy
**What:** When method not found, traverse class hierarchy looking for `method_missing`.
**Why:** Matches inheritance semantics. Child can override parent's `method_missing`.

### Decision 3: Pass method name as string, args as rest parameters
**What:** Signature is `(method method_missing [name args...] ...)`.
**Why:**
- Method name as string is most flexible for pattern matching
- Rest args (`args...`) captures all arguments naturally
- Matches Ruby's `method_missing(name, *args)` pattern

### Decision 4: Check method_missing only after full hierarchy search
**What:** Only check `method_missing` after confirming no regular method exists anywhere in the hierarchy.
**Why:** Regular methods must always take precedence. This preserves expected OOP semantics.

## Implementation Approach

### Step 1: Enable the field
```nim
# In type_defs.nim ClassObj
method_missing*: Value  # Uncomment this line
```

### Step 2: Add hierarchy lookup helper
```nim
# In classes.nim
proc get_method_missing*(self: Class): Value =
  if self.method_missing != NIL:
    return self.method_missing
  elif self.parent != nil:
    return self.parent.get_method_missing()
  return NIL
```

### Step 3: Modify VM dispatch points
At each "Method not found" error site in `vm.nim`, add:
```nim
# Before: not_allowed("Method " & method_name & " not found on instance")
# After:
let mm = class.get_method_missing()
if mm != NIL:
  # Build args array: [method_name_string, arg1, arg2, ...]
  # Call mm with self and args
else:
  not_allowed("Method " & method_name & " not found on instance")
```

### Step 4: Calling method_missing
The call needs to:
1. Create an array containing `[original_arg1, original_arg2, ...]`
2. Call `method_missing` with `(self, method_name_as_string, args_array)`
3. Use splat/rest handling for the args

## Risks / Trade-offs

**Risk:** Performance regression on method-not-found errors.
**Mitigation:** Only affects the error path; normal method calls unchanged. The `get_method_missing` lookup is O(hierarchy depth), same as regular method lookup.

**Risk:** Complex interaction with method caching.
**Mitigation:** Method cache misses already fall back to full lookup. Add cache invalidation when `method_missing` is set on a class.

**Trade-off:** No `respond_to` equivalent.
**Rationale:** Keep initial implementation simple. Can be added later. Gene can use `(has_method obj "name")` for now.

## Migration Plan

No migration needed - this is a new additive feature. Existing code continues to work. Classes without `method_missing` behave exactly as before.

## Open Questions

1. **Should method_missing work with keyword arguments?** Initial implementation: No. Can be added later.
2. **Should there be a way to call the "original" method (like `super`)?** N/A - there is no original method to call.
