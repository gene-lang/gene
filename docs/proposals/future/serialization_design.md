# Gene Serialization Design

## Overview

Gene serialization converts runtime values into a storable/transmittable text format and back. The system must handle both pure data (literals) and runtime objects (classes, functions, instances) that exist within the module/namespace system.

## Current Implementation (`serdes.nim`)

### Two Serialization Modes

**1. Literal Serialization (`serialize_literal`)**

Restricted to pure data values safe for crossing thread/process boundaries:

- Primitives: `nil`, `bool`, `int`, `float`, `char`, `string`, `symbol`, `byte`, `bytes`, `date`, `datetime`
- Containers: `array`, `map`, `gene` — only if all contents are also literal
- Rejects anything else (functions, classes, instances, threads, futures, namespaces)

Used for thread messaging where arbitrary runtime objects are unsafe.

**2. Full Serialization (`serialize`)**

Handles runtime objects by converting them to reference forms:

| Value Kind | Serialized Form |
|------------|----------------|
| Literals | Themselves (identity) |
| Arrays/Maps/Genes | Recursive serialization of contents |
| Classes | `(gene/ref "ClassName")` |
| Functions | `(gene/ref "funcName")` |
| Instances | `(gene/instance (gene/ref "ClassName") {^prop1 val1 ^prop2 val2})` |

### Deserialization

`gene/ref` is resolved via `path_to_value()`, which searches:
1. Current VM frame's namespace
2. Global namespace
3. Namespace chains for paths like `"ns/ClassName"`

### Filesystem Tree Serialization

`write_tree` / `read_tree` explode nested structures into directory trees:

- Maps → directories (keys become filenames)
- Arrays → directories with `_genearray.gene` manifest for ordering
- Gene nodes → directories with `_genetype`, `_geneprops`, `_genechildren`
- Leaf values → `.gene` files containing serialized text

Supports lazy loading via `^lazy` option — only accessed subtrees are read from disk.

### Current Limitations

1. **Class/function refs store only the name** — `to_path` returns `self.name`, no module info
2. **No module auto-loading** — `path_to_value()` only searches already-loaded namespaces
3. **Cross-thread deserialization fails** if the defining module isn't loaded in the target thread
4. **No custom deserialization hooks** — instances are reconstructed by blindly copying properties

## Proposed Design

### Core Idea

At module load time, stamp every exported class/function/enum/named-instance with its module path and internal namespace path. Use typed reference forms in serialized output. On deserialization, auto-import modules as needed.

### Module Load Tagging

When a module finishes loading, traverse all namespace members and their descendants. For each taggable value, record:

- **Module path**: the import path used to load the module (e.g. `"x/y"`)
- **Internal path**: the namespace path within the module (e.g. `"n/m/ClassA"`)

**Phase 1 taggable types:**
- Namespaces
- Classes
- Function-like objects (functions, macros)
- Enums / enum members
- Named instances (singletons, exported objects)

This tagging happens once per module load and provides the identity needed for serialization.

### Three Serialization Buckets

**1. Named definition-like values** — classes, functions, namespaces, enums, named/singleton instances
→ Serialize by **canonical reference** (looked up by path on deserialize)

**2. Anonymous but reconstructible instances** — runtime-created objects with a serializable class + state
→ Serialize by **class ref + state** (reconstructed on deserialize)

**3. Transient / non-reconstructible values** — closures with captured state, active generators, threads, futures, native handles
→ **Not serializable** (clear error on attempt)

### Typed Reference Forms

Replace the generic `(gene/ref ...)` with typed references:

```gene
# Class reference
(ClassRef ^module "x/y" ^path "n/m/ClassA")

# Function reference
(FunctionRef ^module "x/y" ^path "n/m/my_func")

# Enum member reference
(EnumRef ^module "x/y" ^path "Color/Red")

# Named instance reference (singleton/exported)
(InstanceRef ^module "x/y" ^path "DEFAULT_CONFIG")

# Anonymous instance (class ref + serialized state)
(Instance (ClassRef ^module "x/y" ^path "n/m/MyClass")
  {^prop1 val1 ^prop2 val2})
```

For stdlib types, use path-only shorthand (no `^module` needed since stdlib is always loaded):

```gene
(ClassRef ^path "genex/http/Request")
```

### Instance Serialization: Reference vs Value

For instances found in module namespaces, the serializer checks:

- **Has a module path tag?** → serialize as `InstanceRef` (identity semantics — deserialize gives you the same exported object)
- **No tag?** → serialize as `Instance` with class ref + properties (snapshot semantics — deserialize reconstructs a new object)

**Identity vs snapshot semantics:**
- Enum members, sentinels, singleton services → identity (use `InstanceRef`)
- Mutable objects where state matters → snapshot (use `Instance` with state)
- Future consideration: classes could declare `serializes_by_ref` or `serializes_by_value` for explicit control

### Deserialization with Module Auto-Import

When deserializing a `ClassRef`, `FunctionRef`, `EnumRef`, or `InstanceRef`:

1. Parse module path + internal path from the reference
2. Check if the module is already loaded in the current namespace chain
3. If not loaded, **trigger module import** (e.g. data loaded in another thread that hasn't imported the module yet)
4. Resolve the value from the module's exported namespace
5. For `Instance`: call the class's `.deserialize(v)` method if defined

### Class-Level Deserialize Hook

Classes can define a `.deserialize(v: Value)` method to customize instance reconstruction:

```gene
(class Connection
  (ctor [host port]
    (/host = host)
    (/port = port)
    (/socket = nil))  # transient, not serialized

  (method .deserialize [v]
    (var inst (new Connection (v .get "host") (v .get "port")))
    (inst .connect)  # re-establish connection
    inst))
```

If no `.deserialize` method is defined, fall back to default behavior: create instance, copy serialized properties.

### Serializability Rules

- **Serializable**: any value whose class/function can be traced back to a module path or stdlib path
- **Not serializable**: anonymous classes, closures over local state, thread handles, futures, generators, and other inherently transient values
- Attempting to serialize a non-serializable value raises a clear error

### Summary of Changes Needed

| Component | Current | Proposed |
|-----------|---------|----------|
| `to_path` | Returns `self.name` only | Returns `module_path + internal_path` |
| Module loader | No tagging | Tags classes/functions/enums/named instances with origin info |
| Serialized refs | `(gene/ref "name")` | Typed refs: `ClassRef`, `FunctionRef`, `EnumRef`, `InstanceRef` |
| Deserialization | `path_to_value()` — loaded namespaces only | Auto-import modules, then resolve |
| Instance serialization | Copy properties blindly | Named → `InstanceRef`; anonymous → class ref + `.deserialize(v)` hook |
| Error handling | `todo("serialize ...")` for unsupported kinds | Explicit "not serializable" error |

### Thread Safety

Gene uses a **shared-nothing threading model** — each thread has its own namespace and module state. Globals are read-only in non-main threads (not yet finalized).

This simplifies serialization:
- No synchronization needed for module auto-import — each thread imports independently
- `serialize_literal` remains the safe path for thread messaging (no module concerns)
- Full serialization with module auto-import works per-thread without locks
