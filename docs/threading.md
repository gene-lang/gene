# Threading in Gene

## Overview

Gene provides threading support through the `gene/thread` namespace. Threads allow concurrent execution of Gene code with message passing for communication.

## Thread Creation and Management

```gene
# Create a new thread
(var t (gene/thread/create (fn []
  (println "Running in thread")
)))

# Start the thread
(gene/thread/start t)

# Wait for thread to complete
(gene/thread/join t)
```

## Thread Messaging

Threads communicate via message passing. Messages are sent asynchronously and isolated across thread boundaries through serialization.

```gene
# Send a message to a thread
(gene/thread/send t "Hello from main thread")

# Send a message and wait for reply
(var reply (gene/thread/send t "Request" ^reply true))

# Receive messages in the thread
(var msg (gene/thread/receive))
```

## Message Serialization Constraint

**IMPORTANT**: Thread messages can only contain "literal" values. This is a fundamental language constraint for thread safety.

### Allowed Value Types

- **Primitives**: `nil`, `bool`, `int`, `float`, `char`, `string`, `symbol`
- **Binary data**: `byte`, `bytes`
- **Temporal**: `date`, `datetime`
- **Containers**: `array`, `map`, `gene` (if all contents are also literal values)

### NOT Allowed

- **Functions**: Functions/closures may reference thread-local state or capture variables
- **Classes**: Class objects are global singletons
- **Instances**: Object instances have complex object graphs and may contain non-literal values
- **Threads**: Thread handles are thread-specific
- **Futures**: Future handles are tied to specific execution contexts
- **Namespaces**: Namespace objects reference global state

### Examples

```gene
# ✓ Valid - primitives and containers with literal contents
(gene/thread/send t 42)
(gene/thread/send t "hello")
(gene/thread/send t [1 2 3])
(gene/thread/send t {^name "Alice" ^age 30})
(gene/thread/send t (Gene "data" [1 2 3]))

# ✗ Invalid - functions
(gene/thread/send t (fn [] (println "hi")))  # ERROR

# ✗ Invalid - class instances
(var obj (new MyClass))
(gene/thread/send t obj)  # ERROR

# ✗ Invalid - containers with non-literal contents
(gene/thread/send t [(fn [] 1) 2])  # ERROR - array contains function
(gene/thread/send t {^fn (fn [] 1)})  # ERROR - map contains function
```

### Error Messages

When you attempt to send a non-literal value, you'll receive a detailed error message:

```
Thread message payload must be a literal value. Got VkFunction.
Allowed: primitives (nil/bool/int/float/char/string/symbol/byte/bytes/date/datetime)
and containers (array/map/gene) with literal contents.
Not allowed: functions, classes, instances, threads, futures.
```

### Rationale

This constraint exists for several important reasons:

1. **Thread Isolation**: Each thread has its own memory space and stack. Sharing complex objects across threads risks data races and memory corruption.

2. **No Shared State**: Functions and closures capture variables from their defining scope. These captured variables are thread-local and cannot be safely accessed from another thread.

3. **GC Safety**: The garbage collector operates per-thread. Sharing object references across threads would require complex synchronization.

4. **Simplicity**: Limiting messages to literal values makes the threading model easier to reason about and implement correctly.

## Workarounds

If you need to pass complex data between threads, consider:

### 1. Serialize to Literal Structures

Convert your complex objects to maps/arrays:

```gene
# Instead of sending an instance
(class Person (ctor [name age] ...))
(var p (new Person "Alice" 30))

# Convert to a map
(var person_data {^name "Alice" ^age 30})
(gene/thread/send t person_data)

# Reconstruct in the receiving thread
(fn handle_message [msg]
  (var person (new Person msg/name msg/age))
  ...
)
```

### 2. Use IDs and Lookup Tables

Pass identifiers instead of objects:

```gene
# Main thread: store objects in a lookup table
(var objects {})
(var next_id 0)

(fn register_object [obj]
  (next_id += 1)
  (objects/[next_id] = obj)
  next_id
)

# Send just the ID
(var obj_id (register_object my_object))
(gene/thread/send t {^type "lookup" ^id obj_id})
```

### 3. Function Names as Symbols

Pass function names and dispatch dynamically:

```gene
# Instead of passing functions
(gene/thread/send t {^action ^process_data ^args [1 2 3]})

# Dispatch in the receiving thread
(fn handle_message [msg]
  (var action msg/action)  # Symbol like ^process_data
  (case action
    ^process_data (process_data msg/args)
    ^calculate (calculate msg/args)
    ...
  )
)
```

## Thread Pool

Gene maintains a thread pool with a maximum of 64 threads (MAX_THREADS). Thread IDs range from 0 (main thread) to 63 (worker threads).

## Implementation Details

- Threads are implemented using Nim's native threading support
- Message serialization is handled by `src/gene/serdes.nim`
- Thread management is in `src/gene/vm/thread.nim`
- The serialization constraint is enforced by `serialize_literal()` which checks `is_literal_value()`
