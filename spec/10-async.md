# 10. Async & Concurrency

## 10.1 Async / Await

```gene
# Wrap a value in a completed Future
(var f (async (compute_something)))

# Retrieve the result
(var result (await f))
```

- `async` evaluates the expression **synchronously**, then wraps its result in a completed Future
- It does **not** automatically make slow operations run in the background
- Its purpose is to unify code paths — e.g., when one branch returns a Future and another returns a plain value, wrapping the plain value with `async` lets both branches be handled uniformly with `await`
- `await` blocks until the future completes, polling the event loop

### Unifying Sync and Async Branches

```gene
# fetch_data returns a Future, but fallback is a plain value.
# Wrapping the fallback with async lets both be awaited uniformly.
(var f
  (if use_network
    (fetch_data "url")       # Already a Future
  else
    (async cached_value)))   # Wrap plain value as a completed Future

(var result (await f))       # Works for both branches
```

### True Concurrent Operations

Real concurrency comes from async I/O functions that integrate with the event loop (see 10.2), not from wrapping synchronous code with `async`:

```gene
(var f1 (fetch_data "url1"))   # Returns Future, starts I/O
(var f2 (fetch_data "url2"))   # Returns Future, starts I/O
(var r1 (await f1))            # f1 and f2 execute concurrently
(var r2 (await f2))
```

## 10.2 Async I/O

Real async operations that integrate with the event loop:

```gene
# File I/O
(var text (await (gene/io/read_async "file.txt")))
(await (gene/io/write_async "out.txt" "content"))

# HTTP
(var resp (await (http_get "https://example.com")))

# Sleep
(await (gene/sleep_async 1000))   # Milliseconds
```

## 10.3 Future State & Callbacks

```gene
# Check state
future/.state     # => pending | success | failure | cancelled

# Callbacks
(f .on_success (fn [value] (println "Got:" value)))
(f .on_failure (fn [error] (println "Error:" error)))

# Manual future + timeout-aware await
(var f (new gene/Future))
(f .complete 42)
(await ^timeout 0.5 f)
```

## 10.4 Error Handling in Async

Exceptions in async blocks are captured by the future and re-thrown on `await`:

```gene
(var f (async (throw "boom")))
(try
  (await f)
catch *
  (println "Caught:" $ex))
```

## 10.5 Threads

Gene supports OS threads with message passing:

```gene
# Spawn a thread that returns a value
(var result (await (spawn_return (+ 100 23))))
# result => 123
```

### Message Passing
```gene
(var worker (spawn (do
  (thread .on_message (fn [msg]
    (msg .reply (+ (msg .payload) 1))))
  (keep_alive))))

(await (send_expect_reply worker 41))   # => 42
```

Only "literal" values can be sent between threads:
- **Allowed**: primitives, arrays, maps, Gene values (with literal contents)
- **Not allowed**: functions, classes, instances, threads, futures, namespaces

### Thread Limits
- Maximum 64 threads (IDs 0-63)
- Each thread gets its own VM and message channel

---

## Potential Improvements

- **Structured concurrency**: No built-in way to manage groups of futures (wait-all / wait-any). Must manually track and await each.
- **`async for`**: No async iteration protocol. Cannot `for` over a stream of async values.
- **Thread safety of shared state**: No mutex, lock, or atomic primitives in the language. Shared mutable state across threads is unsafe.
- **Channel type**: Message passing uses thread-specific send. A first-class Channel type (like Go channels) would enable more flexible concurrent patterns.
- **Thread pool**: The 64-thread limit is fixed. A work-stealing thread pool would better utilize resources.
- **Manual future failure API**: `Future` supports manual completion and cancellation, but there is no dedicated `.fail` / reject-style helper for constructing failed futures directly.
- **Async in constructors/methods**: Async works in functions but the interaction with class constructors and method dispatch may have edge cases.
- **Event loop visibility**: The internal polling interval (every 100 instructions) is not configurable and not visible to users.
