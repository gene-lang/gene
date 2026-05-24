when defined(gene_wasm):
  import ../types
  import ../wasm_host_abi

  type
    ActorSendTier* = enum
      AstByValue
      AstSharedFrozen
      AstClonedMutable

    ActorTrySendStatus* = enum
      AtsAccepted
      AtsFull
      AtsStopped
      AtsInvalidTarget

    ActorTrySendResult* = object
      status*: ActorTrySendStatus
      future*: Value

    ActorQueueSnapshot* = object
      exists*: bool
      stopped*: bool
      dispatched*: bool
      mailbox_len*: int
      pending_len*: int
      mailbox_limit*: int

  const DEFAULT_ACTOR_MAILBOX_LIMIT* = 10_000

  proc raise_actor_unsupported() {.noreturn.} =
    raise_wasm_unsupported("actors")

  proc actor_runtime_active*(): bool =
    false

  proc prepare_actor_payload_for_send*(payload: Value): tuple[tier: ActorSendTier, value: Value] {.gcsafe.} =
    (AstByValue, payload)

  proc set_actor_mailbox_limit_for_test*(limit: int) =
    discard limit
    raise_actor_unsupported()

  proc actor_spawn_value*(handler: Value, state: Value = NIL, mailbox_limit = 0): Value =
    discard handler
    discard state
    discard mailbox_limit
    raise_actor_unsupported()

  proc actor_queue_snapshot*(actor_value: Value): ActorQueueSnapshot {.gcsafe.} =
    discard actor_value
    ActorQueueSnapshot(exists: false, stopped: false, dispatched: false,
                       mailbox_len: 0, pending_len: 0, mailbox_limit: 0)

  proc actor_send_value*(vm: ptr VirtualMachine, actor_value: Value, payload: Value,
                         reply_requested = false): Value =
    discard vm
    discard actor_value
    discard payload
    discard reply_requested
    raise_actor_unsupported()

  proc actor_try_send_value*(vm: ptr VirtualMachine, actor_value: Value, payload: Value,
                             reply_requested = false): ActorTrySendResult =
    discard vm
    discard actor_value
    discard payload
    discard reply_requested
    ActorTrySendResult(status: AtsInvalidTarget, future: NIL)

  proc actor_enable_native*(vm: ptr VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int,
                            has_keyword_args: bool): Value {.gcsafe, nimcall.} =
    discard vm
    discard args
    discard arg_count
    discard has_keyword_args
    raise_actor_unsupported()

  proc actor_enable_for_test*(workers: int) =
    discard workers
    raise_actor_unsupported()

  proc actor_spawn_native*(vm: ptr VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int,
                           has_keyword_args: bool): Value {.gcsafe, nimcall.} =
    discard vm
    discard args
    discard arg_count
    discard has_keyword_args
    raise_actor_unsupported()

  proc actor_reply_for_test*(ctx: Value, value: Value) {.gcsafe.} =
    discard ctx
    discard value
    raise_actor_unsupported()

  proc init_actor_runtime*() =
    discard

  proc shutdown_actor_runtime*() =
    discard

  proc init_actor_class*() =
    if not gene_namespace_initialized:
      return
    if App.app.actor_class.kind == VkClass and App.app.actor_context_class.kind == VkClass:
      return

    let actor_class = new_class("Actor")
    if App.app.object_class.kind == VkClass:
      actor_class.parent = App.app.object_class.ref.class
    let actor_class_ref = new_ref(VkClass)
    actor_class_ref.class = actor_class
    App.app.actor_class = actor_class_ref.to_ref_value()

    let actor_context_class = new_class("ActorContext")
    if App.app.object_class.kind == VkClass:
      actor_context_class.parent = App.app.object_class.ref.class
    let actor_context_class_ref = new_ref(VkClass)
    actor_context_class_ref.class = actor_context_class
    App.app.actor_context_class = actor_context_class_ref.to_ref_value()

    if App.app.gene_ns.kind == VkNamespace:
      App.app.gene_ns.ref.ns["Actor".to_key()] = App.app.actor_class
      App.app.gene_ns.ref.ns["ActorContext".to_key()] = App.app.actor_context_class
else:
  include ./actor_native
