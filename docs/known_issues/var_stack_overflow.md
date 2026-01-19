# Stack Overflow on Variable Resolution (IkVarResolve)

## Summary

A stack overflow error occurs when accessing module-level variables from exported functions, particularly when those functions are called from other modules. The error manifests as:

```
Stack overflow: frame stack exceeded 256 at pc 30 (IkVarResolve)
```

## Environment

- Gene VM with bytecode compiler
- Multi-module application with cross-module imports
- Module-level variables accessed via closure capture in exported functions

## Symptoms

1. Application crashes with "frame stack exceeded 256" error
2. Error occurs at `IkVarResolve` instruction (variable resolution)
3. Program counter (pc) is typically a low number (e.g., 30), indicating the crash happens early in function execution
4. Error is reproducible and occurs consistently when the problematic code path is executed

## Reproduction Scenario

### Module Structure

**tools.gene** (module with state):
```gene
# Module-level variable
(var TOOLS {})

# Exported function that accesses module-level variable via closure
(fn $ns/build_system_prompt []
  (var tool_list [])
  (TOOLS .each (fn [name tool]    # <-- Accessing TOOLS causes stack overflow
    (tool_list .append #"- #{name}: #{tool/description}")
  ))
  (tool_list .join "\n")
)

# Tool registration (works fine at module load time)
(fn $ns/register_tool [name description params handler]
  (TOOLS .set name {
    ^description description
    ^params params
    ^handler handler
  })
)
```

**llm.gene** (importing module):
```gene
(import build_system_prompt from "tools")

(fn $ns/build_prompt [history message]
  (var system_prompt (build_system_prompt))  # <-- Triggers stack overflow
  # ...
)
```

**handlers.gene** (another importing module):
```gene
(import execute_tool from "tools")
(import build_prompt from "llm")
# ...
```

### Trigger Conditions

The stack overflow occurs when:
1. A module defines a variable at module scope (e.g., `(var TOOLS {})`)
2. An exported function (`$ns/` prefix) captures this variable in its closure
3. The exported function is called from a different module
4. The function attempts to resolve the captured variable

### What Works vs. What Fails

**Works:**
- Accessing module-level variables from non-exported functions within the same module
- Registering tools at module load time (top-level `register_tool` calls)
- Simple exported functions that don't access module-level state

**Fails:**
- Exported functions that access module-level variables when called from other modules
- Iterating over module-level maps/arrays in exported functions
- Nested closures that capture module-level variables

## Attempted Solutions (Did Not Fix)

### 1. Getter Function Pattern

Attempted to access the variable through a getter function instead of direct closure capture:

```gene
(var TOOLS {})

(fn $ns/get_tools []
  TOOLS
)

(fn $ns/build_system_prompt []
  ((get_tools) .each (fn [name tool]  # Still causes stack overflow
    # ...
  ))
)
```

**Result:** Still causes stack overflow. The issue appears to be with variable resolution itself, not just closure capture.

### 2. Different Variable Access Patterns

Tried various patterns:
- Direct variable access: `TOOLS` - fails
- Through getter: `(get_tools)` - fails
- Assigned to local first: `(var tools TOOLS)` then use `tools` - likely fails

## Working Workaround

### Static String Replacement

Replace dynamic content generation with static strings:

```gene
(fn $ns/build_system_prompt []
  # Static system prompt to avoid iteration issues
  """You are a helpful AI assistant with access to tools.

Available tools:
- get_time: Get the current date and time
- calculate: Evaluate a mathematical expression.
  Parameters:
    expression: The math expression to evaluate
# ... rest of static content
"""
)
```

**Tradeoff:** Requires manual updates when tools change, but avoids the stack overflow entirely.

## Technical Analysis

### Likely Root Cause

The issue appears to be in the VM's variable resolution mechanism (`IkVarResolve` instruction). When resolving a variable captured in a closure from a different module context, the VM may be:

1. Entering an infinite loop trying to resolve the variable's scope chain
2. Recursively looking up the variable through parent scopes without termination
3. Having incorrect scope references when functions are exported and called cross-module

### Relevant VM Code Locations

- `src/gene/vm.nim` - VM execution, specifically `IkVarResolve` handling
- `src/gene/compiler.nim` - How variable references are compiled for closures
- `src/gene/types.nim` - Scope and variable representation

### Call Stack Pattern (Hypothesized)

```
1. handlers.gene calls build_prompt()
2. llm.gene:build_prompt calls build_system_prompt()
3. tools.gene:build_system_prompt tries to resolve TOOLS
4. VM looks for TOOLS in current scope -> not found
5. VM looks in parent scope -> incorrect reference?
6. VM recurses looking for scope -> stack overflow
```

## Impact

- Prevents using module-level state in exported functions
- Limits architectural patterns for Gene applications
- Forces workarounds like static strings or passing state as parameters

## Recommendations

### For Gene Users

1. Avoid accessing module-level variables from exported functions
2. Pass required data as function parameters instead of using closures
3. Use static content where dynamic generation would require module state
4. Keep module-level variables only for use within the same module

### For Gene Developers

1. Investigate `IkVarResolve` instruction handling in `vm.nim`
2. Check scope chain resolution for cross-module function calls
3. Add debugging/tracing for variable resolution to identify the recursion point
4. Consider adding a recursion guard or depth limit with better error messages
5. Review how closures capture variables when functions are exported

## Related Issues

- Single-threaded server cannot call itself (different issue, same project)
- Scope lifetime issues with async blocks (documented elsewhere)

## Test Case

A minimal reproduction case should be created:

```gene
# test_var_overflow_a.gene
(var STATE {"count" 0})

(fn $ns/get_state []
  STATE
)

(fn $ns/increment []
  (var s (get_state))
  (s .set "count" ((s .get "count") + 1))
)
```

```gene
# test_var_overflow_b.gene
(import increment get_state from "test_var_overflow_a")

(increment)  # May trigger stack overflow
(println (get_state))
```

## Version Information

- Gene VM: Current master branch
- Date discovered: January 2025
- Status: Unresolved, workaround available
