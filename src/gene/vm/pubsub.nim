import tables

import ../types

type
  SubscriptionHandleData = ref object of CustomValue
    subscription_id: int
    owner_vm: uint64

var subscription_handle_class {.threadvar.}: Class

proc append_encoded_segment(result: var string, segment: string) {.inline.} =
  result.add($segment.len)
  result.add(':')
  result.add(segment)
  result.add(';')

proc pubsub_event_key(event_type: Value): string =
  case event_type.kind
  of VkSymbol:
    result = "S:"
    result.append_encoded_segment(event_type.str)
  of VkComplexSymbol:
    result = "C:"
    for segment in event_type.ref.csymbol:
      result.append_encoded_segment(segment)
  else:
    raise new_exception(types.Exception,
      "genex/pub and genex/sub require a symbol or complex symbol event type")

proc validate_pubsub_keywords(args: ptr UncheckedArray[Value], has_keyword_args: bool) =
  if not has_keyword_args or args.is_nil or args[0].kind != VkMap:
    return
  for key, _ in map_data(args[0]):
    if key != "combine".to_key():
      raise new_exception(types.Exception, "genex/pub only supports ^combine keyword argument")

proc pubsub_payload_equal(a, b: Value): bool {.inline.} =
  cast[uint64](a) == cast[uint64](b) or a == b

proc expect_subscription_handle(value: Value, context: string): SubscriptionHandleData =
  if value.kind != VkCustom or value.ref.custom_data.is_nil:
    raise new_exception(types.Exception, context)
  if not (value.ref.custom_data of SubscriptionHandleData):
    raise new_exception(types.Exception, context)
  SubscriptionHandleData(value.ref.custom_data)

proc ensure_subscription_handle_class() =
  if subscription_handle_class != nil:
    return
  subscription_handle_class = new_class("Subscription")
  if App != NIL and App.kind == VkApplication and App.app.object_class.kind == VkClass:
    subscription_handle_class.parent = App.app.object_class.ref.class

proc detach_subscription(vm: ptr VirtualMachine, subscription_id: int) =
  if not vm.pubsub_subscriptions.hasKey(subscription_id):
    return

  let subscription = vm.pubsub_subscriptions[subscription_id]
  if subscription == nil or not subscription.active:
    vm.pubsub_subscriptions.del(subscription_id)
    return

  subscription.active = false
  if vm.pubsub_subscribers_by_event.hasKey(subscription.event_key):
    var ids = vm.pubsub_subscribers_by_event[subscription.event_key]
    var i = 0
    while i < ids.len:
      if ids[i] == subscription_id:
        ids.delete(i)
        continue
      i.inc()
    if ids.len == 0:
      vm.pubsub_subscribers_by_event.del(subscription.event_key)
    else:
      vm.pubsub_subscribers_by_event[subscription.event_key] = ids

  vm.pubsub_subscriptions.del(subscription_id)

proc snapshot_pubsub_callbacks(vm: ptr VirtualMachine, event_key: string): seq[Value] =
  if not vm.pubsub_subscribers_by_event.hasKey(event_key):
    return @[]

  let ids = vm.pubsub_subscribers_by_event[event_key]
  for subscription_id in ids:
    if not vm.pubsub_subscriptions.hasKey(subscription_id):
      continue
    let subscription = vm.pubsub_subscriptions[subscription_id]
    if subscription == nil or not subscription.active:
      continue
    result.add(subscription.callback)

proc execute_pubsub_callback(vm: ptr VirtualMachine, callback: Value, arg: Value) {.gcsafe.} =
  {.cast(gcsafe).}:
    try:
      discard vm_exec_callable(vm, callback, @[arg])
    except CatchableError:
      vm.current_exception = NIL

proc queue_payloadless_pubsub_event(vm: ptr VirtualMachine, event_type: Value, event_key: string) =
  if vm.pubsub_payloadless_index.hasKey(event_key):
    vm.poll_enabled = true
    return

  let queue_index = vm.pending_pubsub_events.len
  vm.pending_pubsub_events.add(
    PubSubEvent(
      event_type: event_type,
      event_key: event_key,
      payload: NIL,
      has_payload: false,
      combine: false,
    )
  )
  vm.pubsub_payloadless_index[event_key] = queue_index
  vm.poll_enabled = true

proc queue_payloaded_pubsub_event(vm: ptr VirtualMachine, event_type: Value, event_key: string,
                                  payload: Value, combine: bool) =
  if combine and vm.pubsub_combinable_index.hasKey(event_key):
    for queue_index in vm.pubsub_combinable_index[event_key]:
      if queue_index < 0 or queue_index >= vm.pending_pubsub_events.len:
        continue
      let pending = vm.pending_pubsub_events[queue_index]
      if pending == nil or not pending.has_payload:
        continue
      if pubsub_payload_equal(pending.payload, payload):
        vm.poll_enabled = true
        return

  let queue_index = vm.pending_pubsub_events.len
  vm.pending_pubsub_events.add(
    PubSubEvent(
      event_type: event_type,
      event_key: event_key,
      payload: payload,
      has_payload: true,
      combine: combine,
    )
  )
  if combine:
    if not vm.pubsub_combinable_index.hasKey(event_key):
      vm.pubsub_combinable_index[event_key] = @[]
    vm.pubsub_combinable_index[event_key].add(queue_index)
  vm.poll_enabled = true

proc subscription_handle_unsub(vm: ptr VirtualMachine, args: ptr UncheckedArray[Value],
                               arg_count: int, has_keyword_args: bool): Value {.gcsafe.} =
  if get_positional_count(arg_count, has_keyword_args) < 1:
    raise new_exception(types.Exception, "Subscription.unsub requires self")
  let self_value = get_positional_arg(args, 0, has_keyword_args)
  let handle = expect_subscription_handle(self_value, "Subscription.unsub requires a subscription handle")
  if handle.owner_vm != cast[uint64](vm):
    return NIL
  detach_subscription(vm, handle.subscription_id)
  NIL

proc pubsub_callback_supported(callback: Value): bool {.inline.} =
  callback.kind in {VkFunction, VkNativeFn, VkNativeMethod, VkBoundMethod, VkBlock}

proc genex_sub(vm: ptr VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int,
               has_keyword_args: bool): Value {.gcsafe.} =
  validate_pubsub_keywords(args, has_keyword_args)
  let positional = get_positional_count(arg_count, has_keyword_args)
  if positional != 2:
    raise new_exception(types.Exception, "genex/sub requires exactly 2 arguments (event_type and callback)")

  let event_type = get_positional_arg(args, 0, has_keyword_args)
  let callback = get_positional_arg(args, 1, has_keyword_args)
  if not pubsub_callback_supported(callback):
    raise new_exception(types.Exception,
      "genex/sub callback must be a function, native function, native method, bound method, or block")

  let event_key = pubsub_event_key(event_type)
  vm.next_pubsub_subscription_id.inc()
  let subscription_id = vm.next_pubsub_subscription_id

  let subscription = PubSubSubscription(
    id: subscription_id,
    event_key: event_key,
    callback: callback,
    active: true,
  )
  vm.pubsub_subscriptions[subscription_id] = subscription
  if not vm.pubsub_subscribers_by_event.hasKey(event_key):
    vm.pubsub_subscribers_by_event[event_key] = @[]
  vm.pubsub_subscribers_by_event[event_key].add(subscription_id)

  ensure_subscription_handle_class()
  new_custom_value(
    subscription_handle_class,
    SubscriptionHandleData(subscription_id: subscription_id, owner_vm: cast[uint64](vm))
  )

proc genex_unsub(vm: ptr VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int,
                 has_keyword_args: bool): Value {.gcsafe.} =
  validate_pubsub_keywords(args, has_keyword_args)
  let positional = get_positional_count(arg_count, has_keyword_args)
  if positional != 1:
    raise new_exception(types.Exception, "genex/unsub requires exactly 1 argument (subscription_handle)")

  let handle_value = get_positional_arg(args, 0, has_keyword_args)
  let handle = expect_subscription_handle(handle_value, "genex/unsub requires a subscription handle")
  if handle.owner_vm != cast[uint64](vm):
    return NIL
  detach_subscription(vm, handle.subscription_id)
  NIL

proc genex_pub(vm: ptr VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int,
               has_keyword_args: bool): Value {.gcsafe.} =
  validate_pubsub_keywords(args, has_keyword_args)
  let positional = get_positional_count(arg_count, has_keyword_args)
  if positional < 1 or positional > 2:
    raise new_exception(types.Exception, "genex/pub requires an event_type and optional payload")

  let event_type = get_positional_arg(args, 0, has_keyword_args)
  let event_key = pubsub_event_key(event_type)
  let has_payload = positional == 2
  let combine = has_keyword_args and has_keyword_arg(args, "combine") and get_keyword_arg(args, "combine").to_bool()

  if has_payload:
    let payload = get_positional_arg(args, 1, has_keyword_args)
    queue_payloaded_pubsub_event(vm, event_type, event_key, payload, combine)
  else:
    queue_payloadless_pubsub_event(vm, event_type, event_key)

  NIL

proc init_pubsub_namespace*() =
  if App == NIL or App.kind != VkApplication:
    return
  if App.app.genex_ns.kind != VkNamespace:
    return

  ensure_subscription_handle_class()
  subscription_handle_class.def_native_method("unsub", subscription_handle_unsub)

  let genex_ns = App.app.genex_ns.ref.ns
  genex_ns["pub".to_key()] = NativeFn(genex_pub).to_value()
  genex_ns["sub".to_key()] = NativeFn(genex_sub).to_value()
  genex_ns["unsub".to_key()] = NativeFn(genex_unsub).to_value()

proc drain_pending_pubsub_events*(vm: ptr VirtualMachine) {.gcsafe.} =
  if vm.pubsub_draining or vm.pending_pubsub_events.len == 0:
    if vm.pending_pubsub_events.len == 0 and vm.pending_futures.len == 0 and vm.thread_futures.len == 0:
      vm.poll_enabled = false
    return

  vm.pubsub_draining = true
  let batch = vm.pending_pubsub_events
  vm.pending_pubsub_events = @[]
  vm.pubsub_payloadless_index = initTable[string, int]()
  vm.pubsub_combinable_index = initTable[string, seq[int]]()

  for pending_event in batch:
    if pending_event == nil:
      continue
    let callbacks = snapshot_pubsub_callbacks(vm, pending_event.event_key)
    let arg = if pending_event.has_payload: pending_event.payload else: NIL
    for callback in callbacks:
      execute_pubsub_callback(vm, callback, arg)

  vm.pubsub_draining = false
  if vm.pending_pubsub_events.len == 0 and vm.pending_futures.len == 0 and vm.thread_futures.len == 0:
    vm.poll_enabled = false
