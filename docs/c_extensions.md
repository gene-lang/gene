# C Extensions for Gene VM

Gene VM supports native extensions written in C (or any language that can produce C-compatible shared libraries).

## Overview

C extensions allow you to:
- Write performance-critical code in C
- Interface with existing C libraries
- Extend Gene with custom functionality
- Use the same extension API as Nim extensions

## Quick Start

### 1. Create Your Extension

```c
#include "gene_extension.h"

// Your extension functions
static Value my_function(VirtualMachine* vm, Value* args, 
                         int arg_count, bool has_keyword_args) {
    // Implementation
    return gene_to_value_int(42);
}

// Required: set_globals
void set_globals(VirtualMachine* vm) {
    // Called first - save VM pointer if needed
}

// Required: init
Namespace* init(VirtualMachine* vm) {
    Namespace* ns = gene_new_namespace("my_ext");
    gene_namespace_set(ns, "my_function", gene_wrap_native_fn(my_function));
    return ns;
}
```

### 2. Build the Extension

```bash
# macOS
gcc -fPIC -O2 -dynamiclib -undefined dynamic_lookup \
    -o my_ext.dylib my_ext.c

# Linux
gcc -fPIC -O2 -shared -o my_ext.so my_ext.c

# Windows (MinGW)
gcc -O2 -shared -o my_ext.dll my_ext.c
```

### 3. Use in Gene

```gene
# Load extension
(var my_ext (genex/load "path/to/my_ext"))

# Use functions
(my_ext/my_function)  # => 42
```

## API Reference

### Required Functions

Every extension must export these two functions:

#### `void set_globals(VirtualMachine* vm)`

Called first by the VM to pass the VM pointer. Use this to initialize any global state.

```c
void set_globals(VirtualMachine* vm) {
    // Save VM pointer if needed
    // Initialize global state
}
```

#### `Namespace* init(VirtualMachine* vm)`

Called after `set_globals()`. Create and return your extension's namespace.

```c
Namespace* init(VirtualMachine* vm) {
    Namespace* ns = gene_new_namespace("my_ext");
    
    // Register functions
    gene_namespace_set(ns, "func1", gene_wrap_native_fn(func1));
    gene_namespace_set(ns, "func2", gene_wrap_native_fn(func2));
    
    return ns;
}
```

### Value Conversion

#### Creating Values

```c
Value gene_to_value_int(int64_t i);
Value gene_to_value_float(double f);
Value gene_to_value_string(const char* s);
Value gene_to_value_bool(bool b);
Value gene_nil(void);
```

#### Extracting Values

```c
int64_t gene_to_int(Value v);
double gene_to_float(Value v);
const char* gene_to_string(Value v);  // Returns NULL if not a string
bool gene_to_bool(Value v);
bool gene_is_nil(Value v);
```

### Namespace Functions

```c
// Create namespace
Namespace* gene_new_namespace(const char* name);

// Set value in namespace
void gene_namespace_set(Namespace* ns, const char* key, Value value);

// Get value from namespace
Value gene_namespace_get(Namespace* ns, const char* key);
```

### Function Wrapping

```c
// Wrap C function as Gene value
Value gene_wrap_native_fn(NativeFn fn);
```

### Argument Handling

```c
// Get positional argument (handles keyword args correctly)
Value gene_get_arg(Value* args, int arg_count, bool has_keyword_args, int index);
```

### Error Handling

```c
// Raise an exception (does not return)
void gene_raise_error(const char* message);
```

## Example: Math Extension

```c
#include "gene_extension.h"
#include <math.h>

static Value c_sqrt(VirtualMachine* vm, Value* args, 
                    int arg_count, bool has_keyword_args) {
    if (arg_count < 1) {
        gene_raise_error("sqrt requires 1 argument");
    }
    
    Value num = gene_get_arg(args, arg_count, has_keyword_args, 0);
    double result = sqrt((double)gene_to_int(num));
    
    return gene_to_value_float(result);
}

static Value c_pow(VirtualMachine* vm, Value* args,
                   int arg_count, bool has_keyword_args) {
    if (arg_count < 2) {
        gene_raise_error("pow requires 2 arguments");
    }
    
    Value base = gene_get_arg(args, arg_count, has_keyword_args, 0);
    Value exp = gene_get_arg(args, arg_count, has_keyword_args, 1);
    
    double result = pow((double)gene_to_int(base), (double)gene_to_int(exp));
    
    return gene_to_value_float(result);
}

void set_globals(VirtualMachine* vm) {
    // Nothing to initialize
}

Namespace* init(VirtualMachine* vm) {
    Namespace* ns = gene_new_namespace("math");
    
    gene_namespace_set(ns, "sqrt", gene_wrap_native_fn(c_sqrt));
    gene_namespace_set(ns, "pow", gene_wrap_native_fn(c_pow));
    
    return ns;
}
```

## Building Extensions

### Using Makefile

```makefile
# Detect OS
UNAME_S := $(shell uname -s)

ifeq ($(UNAME_S),Darwin)
    EXT_FILE = my_ext.dylib
    LDFLAGS = -dynamiclib -undefined dynamic_lookup
else ifeq ($(UNAME_S),Linux)
    EXT_FILE = my_ext.so
    LDFLAGS = -shared -fPIC
else
    EXT_FILE = my_ext.dll
    LDFLAGS = -shared
endif

CFLAGS = -fPIC -O2 -Wall

$(EXT_FILE): my_ext.c
	gcc $(CFLAGS) $(LDFLAGS) -o $@ $<
```

### Manual Build

**macOS:**
```bash
gcc -fPIC -O2 -Wall -dynamiclib -undefined dynamic_lookup \
    -o my_ext.dylib my_ext.c
```

**Linux:**
```bash
gcc -fPIC -O2 -Wall -shared -o my_ext.so my_ext.c
```

**Windows:**
```bash
gcc -O2 -Wall -shared -o my_ext.dll my_ext.c
```

## Best Practices

1. **Error Handling**: Always validate arguments and use `gene_raise_error()` for errors
2. **Memory Management**: Gene owns string memory - don't free strings returned by `gene_to_string()`
3. **Type Checking**: Check value types before conversion
4. **Null Checks**: Check for NULL when converting to strings
5. **Thread Safety**: Extensions should be thread-safe if used with threading

## Limitations

- Extensions cannot directly access Gene VM internals
- All interaction must go through the C API
- Extensions are loaded once and shared across all threads
- No garbage collection integration (use C memory management)

## See Also

- [Extension API Header](../src/gene/extension/gene_extension.h)
- [Example C Extension](../tests/c_extension.c)
- [Nim Extensions](extensions.md)

