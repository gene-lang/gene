# ========== Threading Support ==========

import times

proc current_trace(self: VirtualMachine): SourceTrace =
  if self.cu.is_nil:
    return nil
  if self.pc >= 0 and self.pc < self.cu.instruction_traces.len:
    let trace = self.cu.instruction_traces[self.pc]
    if trace.is_nil and not self.cu.trace_root.is_nil:
      return self.cu.trace_root
    return trace
  if not self.cu.trace_root.is_nil:
    return self.cu.trace_root
  nil

proc format_runtime_exception(self: VirtualMachine, value: Value): string =
  let trace = self.current_trace()
  let location = trace_location(trace)
  if location.len > 0:
    "Gene exception at " & location & ": " & $value
  else:
    "Gene exception: " & $value

# VM initialization for worker threads
proc init_vm_for_thread(thread_id: int) =
  ## Initialize VM for a worker thread
  ## Note: App is shared from main thread, only VM is thread-local

  # Set current thread ID (thread-local variable)
  current_thread_id = thread_id

  # Initialize thread-local VM (but NOT App - App is shared)
  VM = VirtualMachine(
    exception_handlers: @[],
    current_exception: NIL,
    symbols: addr SYMBOLS,
    pending_futures: @[],
    thread_futures: initTable[int, FutureObj](),
    message_callbacks: @[],
  )

  # Initialize thread-local frame pool
  if FRAMES.len == 0:
    FRAMES = newSeqOfCap[Frame](INITIAL_FRAME_POOL_SIZE)
    for i in 0..<INITIAL_FRAME_POOL_SIZE:
      FRAMES.add(cast[Frame](alloc0(sizeof(FrameObj))))
      FRAME_ALLOCS.inc()

  # Initialize thread-local ref pool
  if REF_POOL.len == 0:
    REF_POOL = newSeqOfCap[ptr Reference](INITIAL_REF_POOL_SIZE)
    for i in 0..<INITIAL_REF_POOL_SIZE:
      REF_POOL.add(cast[ptr Reference](alloc0(sizeof(Reference))))

  # App is already initialized by main thread - we just reference it
  # No need to call init_stdlib() since App already has all the functions

  # Create thread-local namespace for thread-specific variables
  # This avoids race conditions when multiple threads access $thread
  let thread_ns = new_namespace("thread_local")

  # Add $main_thread variable to thread-local namespace
  let main_thread_ref = types.Thread(
    id: 0,
    secret: THREADS[0].secret
  )
  thread_ns["$main_thread".to_key()] = main_thread_ref.to_value()
  thread_ns["main_thread".to_key()] = main_thread_ref.to_value()

  # Add $thread variable to refer to current thread
  let current_thread_ref = types.Thread(
    id: thread_id,
    secret: THREADS[thread_id].secret
  )
  thread_ns["$thread".to_key()] = current_thread_ref.to_value()
  thread_ns["thread".to_key()] = current_thread_ref.to_value()

  # Mark gene namespace as initialized for this worker thread and ensure thread classes are available
  gene_namespace_initialized = true
  init_thread_class()

  # Store thread-local namespace in VM
  VM.thread_local_ns = thread_ns

# Thread handler
proc thread_handler(thread_id: int) {.thread.} =
  ## Main thread execution loop
  {.cast(gcsafe).}:
    try:
      # Initialize VM for this thread
      let spawn_start = THREADS[thread_id].spawn_start
      let start_ts = if spawn_start > 0: spawn_start else: epochTime()
      init_vm_for_thread(thread_id)
      THREADS[thread_id].last_init_ms = (epochTime() - start_ts) * 1000.0
      when not defined(release):
        let ms = THREADS[thread_id].last_init_ms
        echo "THREAD_INIT_MS thread=" & $thread_id & " ms=" & $ms

      # Message loop
      when DEBUG_VM:
        echo "DEBUG thread_handler: Starting message loop for thread ", thread_id
      while true:
        # Receive message (blocking)
        let msg = THREAD_DATA[thread_id].channel.recv()

        # Check for termination
        if msg.msg_type == MtTerminate:
          break

        # Reset VM state from previous execution
        reset_vm_state()

        # Execute based on message type
        case msg.msg_type:
        of MtRun, MtRunExpectReply:
          # Compile the Gene AST locally (thread-safe, no shared refs)
          when DEBUG_VM:
            echo "DEBUG thread_handler: Compiling code: ", msg.code
          let cu = compile_init(msg.code)

          # Set up VM with scope tracker
          let scope_tracker = new_scope_tracker()
          VM.frame = new_frame()
          VM.frame.stack_index = 0
          VM.frame.scope = new_scope(scope_tracker)
          VM.frame.ns = App.app.gene_ns.ref.ns  # Set namespace for symbol lookup
          VM.cu = cu
          VM.pc = 0

          # Execute
          let result = VM.exec()

          # Send reply if requested
          if msg.msg_type == MtRunExpectReply:
            let ser = serialize_literal(result)
            let reply = ThreadMessage(
              id: next_message_id,
              msg_type: MtReply,
              payload: NIL,
              payload_bytes: ThreadPayload(bytes: string_to_bytes(ser.to_s())),
              from_message_id: msg.id,
              from_thread_id: thread_id,
              from_thread_secret: THREADS[thread_id].secret
            )
            next_message_id += 1
            THREAD_DATA[msg.from_thread_id].channel.send(reply)

        of MtSend, MtSendExpectReply:
          # User message - invoke callbacks
          # Deserialize payload if present
          var payload = msg.payload
          if msg.payload_bytes.bytes.len > 0:
            try:
              payload = deserialize_literal(bytes_to_string(msg.payload_bytes.bytes))
            except:
              payload = NIL
          let msg_value = msg.to_value()
          msg_value.ref.thread_message.payload = payload

          # Invoke all registered message callbacks
          for callback in VM.message_callbacks:
            try:
              case callback.kind:
                of VkFunction:
                  discard VM.exec_function(callback, @[msg_value])
                of VkNativeFn:
                  discard call_native_fn(callback.ref.native_fn, VM, @[msg_value])
                of VkBlock:
                  discard VM.exec_function(callback, @[])
                else:
                  discard
            except:
              discard  # Ignore callback errors for now

          # If message requests reply and wasn't handled, send NIL reply
          if msg.msg_type == MtSendExpectReply and not msg.handled:
            var reply: ThreadMessage
            new(reply)
            reply.id = next_message_id
            reply.msg_type = MtReply
            reply.payload = NIL
            reply.payload_bytes = ThreadPayload(bytes: @[])
            reply.from_message_id = msg.id
            reply.from_thread_id = thread_id
            reply.from_thread_secret = THREADS[thread_id].secret
            next_message_id += 1
            THREAD_DATA[msg.from_thread_id].channel.send(reply)

        of MtReply:
          discard

        of MtTerminate:
          break

      # Clean up thread
      cleanup_thread(thread_id)
    except CatchableError as e:
      echo "Thread ", thread_id, " crashed: ", e.msg
      when not defined(release):
        echo e.getStackTrace()

# Spawn functions
proc spawn_thread(code: ptr Gene, return_value: bool): Value =
  ## Spawn a new thread to execute Gene AST
  ## Returns thread reference or future
  let thread_id = get_free_thread()

  if thread_id == -1:
    raise newException(ValueError, "Thread pool exhausted (max " & $MAX_THREADS & " threads)")

  # Initialize thread
  let parent_id = current_thread_id
  init_thread(thread_id, parent_id)
  THREADS[thread_id].spawn_start = epochTime()

  # Create thread
  createThread(THREAD_DATA[thread_id].thread, thread_handler, thread_id)

  # Create message - use new() to allocate to avoid GC issues with threading
  var msg: ThreadMessage
  new(msg)
  msg.id = next_message_id
  msg.msg_type = if return_value: MtRunExpectReply else: MtRun
  msg.payload = NIL
  msg.payload_bytes = ThreadPayload(bytes: @[])
  msg.code = cast[Value](code)  # Pass Gene AST as Value (thread will compile it)
  msg.from_thread_id = current_thread_id
  msg.from_thread_secret = THREADS[current_thread_id].secret
  let message_id = next_message_id
  next_message_id += 1

  # Send message to thread (send the ref directly)
  THREAD_DATA[thread_id].channel.send(msg)

  # Return value
  if return_value:
    # Create a future for the return value
    let future_obj = FutureObj(
      state: FsPending,
      value: NIL,
      success_callbacks: @[],
      failure_callbacks: @[],
      nim_future: nil
    )

    # Store future in VM's thread_futures table keyed by message ID
    VM.thread_futures[message_id] = future_obj

    # Return the future
    let future_val = new_ref(VkFuture)
    future_val.future = future_obj
    return future_val.to_ref_value()
  else:
    # Return thread reference
    let thread_ref = types.Thread(
      id: thread_id,
      secret: THREADS[thread_id].secret
    )
    return thread_ref.to_value()

# ========== End Threading Support ==========
