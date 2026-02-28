when defined(gene_wasm):
  import ../types
  import ../wasm_host_abi

when defined(gene_wasm):
  var THREAD_CLASS_VALUE*: Value = NIL
  var THREAD_MESSAGE_CLASS_VALUE*: Value = NIL
  var next_message_id* {.threadvar.}: int

  proc init_thread_pool*() =
    next_message_id = 0
    THREADS[0].id = 0
    THREADS[0].secret = 1
    THREADS[0].state = TsBusy
    THREADS[0].in_use = true

  proc get_free_thread*(): int =
    -1

  proc init_thread*(thread_id: int, parent_id: int = 0) =
    discard thread_id
    discard parent_id

  proc cleanup_thread*(thread_id: int) =
    discard thread_id

  proc reset_vm_state*() =
    if VM == nil:
      return

    VM.pc = 0
    VM.cu = nil
    VM.trace = false

    var current_frame = VM.frame
    while current_frame != nil:
      let caller = current_frame.caller_frame
      current_frame.free()
      current_frame = caller
    VM.frame = nil

    VM.exception_handlers.setLen(0)
    VM.current_exception = NIL
    VM.repl_exception = NIL
    VM.repl_on_error = false
    VM.repl_active = false
    VM.repl_skip_on_throw = false
    VM.repl_ran = false
    VM.repl_resume_value = NIL
    VM.current_generator = nil

  proc thread_unsupported(vm: ptr VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value {.gcsafe.} =
    discard vm
    discard args
    discard arg_count
    discard has_keyword_args
    raise_wasm_unsupported("threads")

  proc init_thread_class*() =
    if not gene_namespace_initialized:
      return

    if App.app.thread_class.kind == VkClass:
      THREAD_CLASS_VALUE = App.app.thread_class
      THREAD_MESSAGE_CLASS_VALUE = App.app.thread_message_class
      return

    let thread_class = new_class("Thread")
    if App.app.object_class.kind == VkClass:
      thread_class.parent = App.app.object_class.ref.class
    thread_class.def_native_constructor(thread_unsupported)
    thread_class.def_native_method("send", thread_unsupported)
    thread_class.def_native_method("send_expect_reply", thread_unsupported)
    thread_class.def_native_method("on_message", thread_unsupported)

    let thread_class_ref = new_ref(VkClass)
    thread_class_ref.class = thread_class
    App.app.thread_class = thread_class_ref.to_ref_value()
    THREAD_CLASS_VALUE = App.app.thread_class

    let thread_message_class = new_class("ThreadMessage")
    if App.app.object_class.kind == VkClass:
      thread_message_class.parent = App.app.object_class.ref.class
    thread_message_class.def_native_method("payload", thread_unsupported)
    thread_message_class.def_native_method("reply", thread_unsupported)

    let thread_message_class_ref = new_ref(VkClass)
    thread_message_class_ref.class = thread_message_class
    App.app.thread_message_class = thread_message_class_ref.to_ref_value()
    THREAD_MESSAGE_CLASS_VALUE = App.app.thread_message_class

    if App.app.gene_ns.kind == VkNamespace:
      App.app.gene_ns.ref.ns["Thread".to_key()] = App.app.thread_class
      App.app.gene_ns.ref.ns["ThreadMessage".to_key()] = App.app.thread_message_class
      App.app.gene_ns.ref.ns["send_expect_reply".to_key()] = thread_unsupported.to_value()

  proc keep_alive_fn*(vm: ptr VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value =
    discard vm
    discard args
    discard arg_count
    discard has_keyword_args
    raise_wasm_unsupported("threads")
else:
  include ./thread_native
