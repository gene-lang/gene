# Concurrent HTTP Request Handling

## Overview

This document explores how Gene can support concurrent HTTP request handling using threads and workers. The goal is to enable the HTTP server to process multiple requests simultaneously, improving throughput and responsiveness, especially when handlers perform blocking operations.

## Current Implementation

### Architecture

Gene's current HTTP server (`src/genex/http.nim`) uses Nim's `asynchttpserver` module with a single-threaded async event loop:

1. **Async HTTP Server**: Uses `asynchttpserver.serve()` which handles connections asynchronously
2. **Pending Request Queue**: HTTP requests are queued as `PendingHttpRequest` objects
3. **Event Loop Integration**: The scheduler calls `process_pending_http_requests()` to execute Gene handlers
4. **Sequential Processing**: Gene function handlers are executed sequentially in the main VM context

```nim
# Current flow:
HTTP Request → Async Handler → Pending Queue → Main VM Event Loop → Gene Handler
```

### Limitations

1. **Single-threaded handler execution**: All Gene handlers run on the main thread
2. **Blocking operations block everything**: A slow database query blocks all other requests
3. **No request-level concurrency**: Requests are processed one at a time for Gene function handlers
4. **CPU-bound handlers bottleneck**: Compute-heavy handlers prevent other requests from being served

## Proposed Solutions

### Option 1: Worker Thread Pool Pattern (Recommended)

Inspired by the [Mummy web server](https://github.com/guzba/mummy) architecture, this approach separates I/O handling from request processing:

#### Architecture

```
                    ┌─────────────────────────────┐
                    │   I/O Thread (Main)         │
                    │   - Accept connections      │
                    │   - Read/Write sockets      │
                    │   - Dispatch to workers     │
                    └─────────────┬───────────────┘
                                  │
                    ┌─────────────┴───────────────┐
                    ▼                             ▼
        ┌───────────────────┐         ┌───────────────────┐
        │   Worker Thread 1 │         │   Worker Thread N │
        │   - Own VM        │   ...   │   - Own VM        │
        │   - Gene handlers │         │   - Gene handlers │
        │   - Blocking OK   │         │   - Blocking OK   │
        └───────────────────┘         └───────────────────┘
```

#### Implementation Plan

**Phase 1: Worker Pool Infrastructure**

```nim
# New file: src/gene/vm/http_worker.nim

type
  HttpWorker = object
    thread: Thread[int]
    channel: Channel[HttpJob]
    vm: ptr VirtualMachine

  HttpJob = object
    request: Value              # Gene ServerRequest object
    response_channel: Channel[Value]  # Channel to send response back
    handler: Value              # The Gene handler function/instance

  HttpWorkerPool = object
    workers: seq[HttpWorker]
    job_queue: Channel[HttpJob]
    num_workers: int

var http_worker_pool: HttpWorkerPool
```

**Phase 2: Worker Thread Initialization**

Each worker thread needs its own VM instance but shares the App/global state:

```nim
proc http_worker_handler(worker_id: int) {.thread.} =
  # Initialize thread-local VM (similar to spawn threads)
  setup_thread_vm(worker_id + HTTP_WORKER_OFFSET)
  
  while true:
    let job = http_worker_pool.job_queue.recv()
    
    if job.shutdown:
      break
    
    # Execute handler in this thread's VM
    let response = VM.exec_function(job.handler, @[job.request])
    
    # Send response back to I/O thread
    job.response_channel.send(response)
```

**Phase 3: Integration with HTTP Server**

Modify `handle_request` to dispatch to worker pool:

```nim
proc handle_request(req: asynchttpserver.Request) {.async, gcsafe.} =
  let gene_req = create_server_request(req)
  
  # Instead of processing in main thread, dispatch to worker pool
  var response_channel: Channel[Value]
  response_channel.open(1)
  
  let job = HttpJob(
    request: gene_req,
    response_channel: response_channel,
    handler: gene_handler_global
  )
  
  http_worker_pool.job_queue.send(job)
  
  # Await response (async-friendly polling)
  let response = await poll_channel(response_channel)
  
  # Send HTTP response...
```

#### Gene API

```gene
# Start server with worker pool
(start_server 8080 my_handler ^workers 4)

# Or configure globally
(http/config ^worker_threads 4)
(start_server 8080 my_handler)
```

### Option 2: Spawn-per-Request Pattern (Detailed Analysis)

This option leverages Gene's existing threading infrastructure (`spawn`/`spawn_return`) to handle each HTTP request in a separate thread. This section provides a detailed feasibility analysis.

#### How Gene Threading Works

Gene's threading is implemented in `src/gene/vm/thread.nim` and `src/gene/vm/runtime_helpers.nim`:

1. **Thread Pool**: Gene maintains a pool of up to 64 threads (`MAX_THREADS`)
2. **Thread-local VMs**: Each thread has its own `VirtualMachine` instance
3. **Shared App**: All threads share the `App` global (classes, namespaces, global state)
4. **Message Passing**: Threads communicate via channels with serialized messages
5. **spawn_return**: Returns a `Future` that resolves when the spawned code completes

```nim
# From runtime_helpers.nim - spawn creates a thread and sends code to execute
proc spawn_thread(code: ptr Gene, return_value: bool): Value =
  let thread_id = get_free_thread()
  init_thread(thread_id, parent_id)
  createThread(THREAD_DATA[thread_id].thread, thread_handler, thread_id)
  # Send code to execute via channel
  THREAD_DATA[thread_id].channel.send(msg)
```

#### The Serialization Constraint Challenge

**Critical Issue**: Gene thread messages can only contain "literal" values. This is enforced by `serialize_literal()` in `src/gene/serdes.nim`:

**Allowed Types:**
- Primitives: `nil`, `bool`, `int`, `float`, `char`, `string`, `symbol`
- Binary: `byte`, `bytes`
- Temporal: `date`, `datetime`
- Containers: `array`, `map`, `gene` (if all contents are also literal)

**NOT Allowed:**
- Functions, closures
- Classes
- Instances (including `ServerRequest` objects!)
- Threads, Futures
- Namespaces

This means you **cannot directly pass a ServerRequest instance** to a spawned thread:

```gene
# This WILL NOT work - ServerRequest is an instance
(fn handler [req]
  (spawn_return
    (process req)))  # ERROR: Can't serialize Instance
```

#### Feasibility: Can We Work Around This?

**Yes, with modifications.** Here are the approaches:

##### Approach A: Convert Request to Literal Map

Convert the `ServerRequest` instance to a plain map before spawning:

```gene
(fn request_to_map [req]
  {
    ^method (req .method)
    ^path (req .path)
    ^url (req .url)
    ^params (req .params)
    ^headers (req .headers)
    ^body (req .body)
    ^body_params (req .body_params)
  })

(fn concurrent_handler [req]
  (var req_data (request_to_map req))
  (spawn_return
    (do
      # req_data is a map - can be serialized
      (var path req_data/path)
      (var method req_data/method)
      # Process and return response data as a map
      {^status 200 ^body "Hello" ^headers {^Content-Type "text/plain"}})))

(start_server 8080 concurrent_handler)
```

**Implementation Required:**
```nim
# In http.nim - Add helper to convert ServerRequest to map
proc server_request_to_map(req: Value): Value =
  let result = new_map_value()
  map_data(result)["method".to_key()] = instance_props(req)["method".to_key()]
  map_data(result)["path".to_key()] = instance_props(req)["path".to_key()]
  map_data(result)["url".to_key()] = instance_props(req)["url".to_key()]
  map_data(result)["params".to_key()] = instance_props(req)["params".to_key()]
  map_data(result)["headers".to_key()] = instance_props(req)["headers".to_key()]
  map_data(result)["body".to_key()] = instance_props(req)["body".to_key()]
  map_data(result)["body_params".to_key()] = instance_props(req)["body_params".to_key()]
  result
```

##### Approach B: Native Integration in HTTP Module

Modify `genex/http.nim` to handle spawning internally:

```nim
proc vm_start_server_concurrent(vm: ptr VirtualMachine, args: ...): Value =
  # Store handler globally
  gene_handler_global = handler
  
  # When request comes in:
  # 1. Convert ServerRequest to literal map
  # 2. Spawn thread with the map
  # 3. Await the future
  # 4. Convert result back to response
```

```gene
# Gene API would be simple
(start_server 8080 my_handler ^concurrent true)
```

##### Approach C: Keep-Alive Worker Threads

Instead of spawning per request, maintain persistent worker threads:

```gene
# Main thread
(var workers [])
(for i (range 4)
  (var worker (spawn
    (do
      ($thread .on_message (fn [msg]
        # Process request data from msg
        (var req_data (msg .payload))
        (var response (process_request req_data))
        # Reply with response
        (msg .reply response)))
      (keep_alive))))
  (workers .add worker))

# Round-robin dispatch
(var current_worker 0)
(fn concurrent_handler [req]
  (var req_data (request_to_map req))
  (var future (workers/[current_worker] .send req_data ^reply true))
  (current_worker = (% (+ current_worker 1) 4))
  (await future))

(start_server 8080 concurrent_handler)
```

#### Implementation Plan for Option 2

**Phase 1: Request/Response Serialization Helpers**

Add to `src/genex/http.nim`:

```nim
# Convert ServerRequest to serializable map
proc server_request_to_literal(req: Value): Value {.gcsafe.} =
  let result = new_map_value()
  for key in ["method", "path", "url", "params", "headers", "body", "body_params"]:
    let k = key.to_key()
    let val = instance_props(req).getOrDefault(k, NIL)
    # Ensure nested values are also literal
    if val.kind in {VkString, VkInt, VkBool, VkNil, VkMap, VkArray}:
      map_data(result)[k] = val
  result

# Convert literal map response back to ServerResponse instance
proc literal_to_server_response(data: Value): Value {.gcsafe.} =
  let instance = new_instance_value(server_response_class_global)
  instance_props(instance)["status".to_key()] = 
    map_data(data).getOrDefault("status".to_key(), 200.to_value())
  instance_props(instance)["body".to_key()] = 
    map_data(data).getOrDefault("body".to_key(), "".to_value())
  instance_props(instance)["headers".to_key()] = 
    map_data(data).getOrDefault("headers".to_key(), new_map_value())
  instance
```

**Phase 2: Concurrent Handler Wrapper**

```nim
proc handle_request_concurrent(req: asynchttpserver.Request) {.async, gcsafe.} =
  let gene_req = create_server_request(req)
  
  # Convert to literal map for thread safety
  let req_literal = server_request_to_literal(gene_req)
  
  # Create spawn message with the literal data
  # The handler code will receive this as input
  let spawn_code = create_spawn_wrapper(gene_handler_global, req_literal)
  
  # Spawn and await
  let future = spawn_thread(spawn_code, return_value=true)
  
  # Poll until complete
  while future.state == FsPending:
    await sleepAsync(1)
    poll_thread_messages()
  
  # Convert result back
  let response = literal_to_server_response(future.value)
  await send_http_response(req, response)
```

**Phase 3: Gene API**

```gene
# Simple concurrent server
(fn handle [req_data]
  # req_data is a map, not an instance
  (var path req_data/path)
  (case path
    "/" {^status 200 ^body "Welcome"}
    "/api" {^status 200 ^body (to_json (get_data))}
    {^status 404 ^body "Not Found"}))

(start_server 8080 handle ^concurrent true)
```

#### Performance Considerations

| Metric | Spawn-per-Request | Persistent Workers | Direct Approach |
|--------|-------------------|-------------------|-----------------|
| Thread creation | Per request | Once at startup | Once at startup |
| Serialization | 2x per request | 2x per request | None |
| Max concurrency | 63 (64-1 main) | Configurable | Configurable |
| Memory per request | ~1MB (thread stack) | Shared | Shared |
| Latency overhead | ~1-5ms | ~0.5ms | ~0.1ms |

#### Benchmark Estimate

For a typical web request:
- Thread creation: ~1ms
- Request serialization: ~0.1ms  
- Response deserialization: ~0.1ms
- Handler execution: varies

**Realistic throughput**: ~500-1000 req/sec with 8 workers (vs ~2000-5000 with worker pool)

#### When to Use Option 2

**Good fit:**
- Prototyping concurrent HTTP handling
- Low-to-medium traffic applications
- When you need maximum isolation between requests
- Testing threading infrastructure

**Not recommended:**
- High-traffic production servers (>1000 req/sec)
- Latency-sensitive applications
- When handlers are very fast (<1ms)

#### Complete Example

```gene
# concurrent_http_example.gene

# Helper to convert request to literal
(fn req_to_map [req]
  {
    ^method (req .method)
    ^path (req .path)
    ^params (req .params)
    ^headers (req .headers)
    ^body (req .body)
  })

# Process request in spawned thread
(fn process_request [req_data]
  (var path req_data/path)
  (var method req_data/method)
  
  # Simulate slow database query - this blocks only THIS thread
  (sleep 100)
  
  (case path
    "/"
      {^status 200 ^body "Welcome to concurrent server!"}
    "/api/data"
      {^status 200 
       ^body (gene/json_stringify {^items [1 2 3] ^count 3})
       ^headers {^Content-Type "application/json"}}
    {^status 404 ^body "Not Found"}))

# Main handler - spawns new thread for each request
(fn concurrent_handler [req]
  (var req_data (req_to_map req))
  (var future (spawn_return (process_request req_data)))
  (var result (await future))
  
  # Convert map result to response
  (respond result/status result/body result/headers))

(start_server 8080 concurrent_handler)
(println "Server running on port 8080 with spawn-per-request concurrency")
(run_forever)
```

#### Summary: Feasibility Assessment

| Criterion | Status | Notes |
|-----------|--------|-------|
| Uses existing infrastructure | ✅ | spawn/spawn_return already work |
| Serialization workaround | ✅ | Convert to/from literal maps |
| Implementation effort | Low | ~100 lines of new code |
| Performance | ⚠️ | Good enough for many use cases |
| Thread limit | ⚠️ | 63 concurrent requests max |
| Production ready | ⚠️ | Suitable for low-medium traffic |

**Verdict**: Option 2 is **feasible** and can be implemented with minimal changes. The main work is adding request/response serialization helpers. It's a good stepping stone before implementing the more complex worker pool (Option 1).

### Option 3: Async Handler Execution

For I/O-bound operations, leverage async within handlers:

```gene
(fn async_handler [req]
  (async
    (var db_result (await (db/query "SELECT ...")))
    (respond 200 (to_json db_result))))
```

This keeps the single-thread model but allows other handlers to run during I/O waits.

#### Limitations
- Only helps for I/O-bound work
- CPU-bound operations still block
- Requires handlers to be written in async style

## Recommended Implementation Approach

### Phase 1: Worker Pool Foundation

1. **Create `src/gene/vm/http_worker.nim`** with:
   - `HttpWorkerPool` type with configurable worker count
   - Worker thread initialization (each with own VM)
   - Job queue using Nim channels
   - Response channel per request

2. **Modify `src/genex/http.nim`**:
   - Add `^workers` option to `start_server`
   - Create worker pool on server start
   - Dispatch requests to worker queue instead of pending queue

3. **Handle serialization concerns**:
   - ServerRequest objects need thread-safe representation
   - Response values need safe transfer back to I/O thread

### Phase 2: Integration

1. **Update VM initialization**:
   - Ensure worker threads can access App/global namespaces
   - Thread-local storage for VM instance

2. **Connection handling**:
   - I/O thread manages all socket operations
   - Workers only execute Gene code

3. **Error handling**:
   - Worker crashes shouldn't affect other workers
   - Timeout handling for slow handlers

### Phase 3: Testing & Optimization

1. **Benchmark tests**:
   - Concurrent request throughput
   - Latency under load
   - Memory usage patterns

2. **Configuration tuning**:
   - Auto-detect optimal worker count
   - Queue depth limits
   - Request timeouts

## Example Usage

### Basic Concurrent Server

```gene
# http_server_concurrent.gene

(import http)

(fn handle_request [req]
  # This can block - each request runs in its own worker thread
  (var result (slow_database_query req/params/id))
  (respond 200 (to_json result)))

# Start server with 4 worker threads
(start_server 8080 handle_request ^workers 4)
(run_forever)
```

### Advanced Configuration

```gene
(import http)

# Configure worker pool
(http/configure {
  ^worker_threads 8
  ^max_queue_depth 1000
  ^request_timeout 30000  # 30 seconds
  ^shutdown_timeout 5000  # 5 seconds for graceful shutdown
})

# Class-based handler with middleware
(class App
  (method call [req]
    (if (not (auth/check req))
      (respond 401 "Unauthorized")
      (self/.route req)))
  
  (method route [req]
    (case req/path
      "/" (respond 200 "Welcome")
      "/api/users" (self/.get_users req)
      (respond 404 "Not Found")))
  
  (method get_users [req]
    # Blocking database call - runs in worker thread
    (var users (db/query "SELECT * FROM users"))
    (respond 200 (to_json users) {^Content-Type "application/json"})))

(var app (new App))
(start_server 8080 app ^workers 4)
(run_forever)
```

## Implementation Notes

### Thread Safety Considerations

1. **Request Object Creation**: Create in I/O thread, transfer as immutable data
2. **Response Object**: Create in worker, transfer serialized to I/O thread
3. **Shared State**: Global namespaces are read-only during request handling
4. **Database Connections**: Each worker should have its own connection pool

### Memory Management

1. **VM per Worker**: Thread-local VMs with separate frame pools
2. **Request Lifecycle**: Request objects freed after response sent
3. **GC Coordination**: Each worker thread has independent GC

### Graceful Shutdown

```nim
proc shutdown_worker_pool() =
  # Stop accepting new requests
  http_server.close()
  
  # Signal workers to finish current work
  for i in 0..<http_worker_pool.num_workers:
    http_worker_pool.job_queue.send(HttpJob(shutdown: true))
  
  # Wait for workers with timeout
  for worker in http_worker_pool.workers:
    worker.thread.joinThread()
```

## Comparison with Other Approaches

| Approach | Concurrency | Blocking OK | Memory | Complexity |
|----------|-------------|-------------|--------|------------|
| Current (async single-thread) | Limited | No | Low | Low |
| Worker Pool | High | Yes | Medium | Medium |
| Spawn-per-Request | Medium | Yes | High | Low |
| Async Handlers | Medium | I/O only | Low | Medium |

## Future Enhancements

1. **Connection Pooling**: Share database connections across workers
2. **Request Prioritization**: VIP lanes for specific endpoints
3. **Load Balancing**: Distribute across multiple server instances
4. **Metrics & Monitoring**: Request counts, latencies, queue depths
5. **Hot Reload**: Update handlers without server restart

## Files to Create/Modify

### New Files
- `src/gene/vm/http_worker.nim` - Worker pool implementation
- `tests/test_http_concurrent.nim` - Concurrency tests

### Modified Files
- `src/genex/http.nim` - Add worker pool integration
- `src/gene/vm/runtime_helpers.nim` - HTTP worker initialization
- `src/gene/types/type_defs.nim` - New types for worker pool

## References

- [Mummy Web Server](https://github.com/guzba/mummy) - Multi-threaded HTTP/WebSocket server for Nim
- [Nim Threading Docs](https://nim-lang.org/docs/threads.html)
- [Nim Channels](https://nim-lang.org/docs/channels_builtin.html)
- Gene threading docs: `docs/threading.md`
- Gene HTTP server docs: `docs/http_server_and_client.md`
