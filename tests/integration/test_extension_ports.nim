import std/[os, tables, times, unittest]

import gene/types except Exception
import gene/vm
import gene/vm/actor
import gene/vm/extension
import gene/vm/extension_abi
import gene/vm/thread

proc port_state(count: int): Value =
  new_map_value({
    "count".to_key(): count.to_value()
  }.toTable())

proc port_message(op: string): Value =
  new_map_value({
    "op".to_key(): op.to_value()
  }.toTable())

proc port_message_op(msg: Value): string =
  if msg.kind != VkMap:
    return ""
  let op = map_data(msg).getOrDefault("op".to_key(), NIL)
  if op.kind != VkString:
    return ""
  op.str

proc await_vm_future(future_value: Value, timeout_ms = 2_000): Value =
  let deadline = epochTime() + (timeout_ms.float / 1000.0)
  let future = future_value.ref.future
  while future.state == FsPending and epochTime() < deadline:
    VM.event_loop_counter = 100
    VM.poll_event_loop()
    sleep(10)

  check future.state != FsPending
  check future.state == FsSuccess
  future.value

proc port_handler(vm: ptr VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int,
                  has_keyword_args: bool): Value {.gcsafe, nimcall.} =
  discard vm
  discard arg_count
  let ctx = get_positional_arg(args, 0, has_keyword_args)
  let msg = get_positional_arg(args, 1, has_keyword_args)
  let state = get_positional_arg(args, 2, has_keyword_args)

  case port_message_op(msg)
  of "increment":
    port_state(map_data(state)["count".to_key()].to_int + 1)
  of "get":
    actor_reply_for_test(ctx, map_data(state)["count".to_key()])
    state
  else:
    state

proc build_host(): GeneHostAbi =
  GeneHostAbi(
    abi_version: GENE_EXT_ABI_VERSION,
    user_data: cast[pointer](VM),
    app_value: App,
    symbols_data: nil,
    log_message_fn: nil,
    register_scheduler_callback_fn: nil,
    register_port_fn: host_register_port_bridge,
    call_port_fn: host_call_port_bridge,
    result_namespace: nil
  )

suite "Extension port registration":
  setup:
    init_thread_pool()
    init_app_and_vm()
    init_stdlib()
    init_actor_runtime()
    clear_registered_extension_ports_for_test()

  test "registration fails until actor runtime is enabled":
    var host = build_host()
    var handle = NIL
    let status = register_singleton_port(
      addr host,
      "test/singleton",
      NativeFn(port_handler).to_value(),
      port_state(0),
      addr handle
    )

    check status == GeneExtErr
    check handle == NIL

  test "singleton and pool ports materialize as actor-backed handles":
    actor_enable_for_test(3)

    var host = build_host()

    var singleton = NIL
    check register_singleton_port(
      addr host,
      "test/singleton",
      NativeFn(port_handler).to_value(),
      port_state(0),
      addr singleton
    ) == GeneExtOk
    check singleton.kind == VkActor

    discard actor_send_value(VM, singleton, port_message("increment"))
    check await_vm_future(actor_send_value(VM, singleton, port_message("get"), true)) == 1.to_value()

    var pool = NIL
    check register_port_pool(
      addr host,
      "test/pool",
      2,
      NativeFn(port_handler).to_value(),
      port_state(5),
      addr pool
    ) == GeneExtOk

    check pool.kind == VkArray
    check array_data(pool).len == 2
    check array_data(pool)[0].kind == VkActor
    check array_data(pool)[1].kind == VkActor

    discard actor_send_value(VM, array_data(pool)[0], port_message("increment"))
    check await_vm_future(actor_send_value(VM, array_data(pool)[0], port_message("get"), true)) == 6.to_value()
    check await_vm_future(actor_send_value(VM, array_data(pool)[1], port_message("get"), true)) == 5.to_value()

  test "host ABI can call a registered singleton port and receive a reply":
    actor_enable_for_test(1)

    var host = build_host()
    var singleton = NIL
    check register_singleton_port(
      addr host,
      "test/callable",
      NativeFn(port_handler).to_value(),
      port_state(7),
      addr singleton
    ) == GeneExtOk

    let result = call_extension_port(addr host, singleton, port_message("get"))
    check result == 7.to_value()

  test "factory registrations spawn fresh actor-backed handles on demand":
    actor_enable_for_test(2)

    var host = build_host()
    check register_port_factory(
      addr host,
      "test/factory",
      NativeFn(port_handler).to_value()
    ) == GeneExtOk

    let first = spawn_registered_extension_factory_port("test/factory", port_state(9))
    let second = spawn_registered_extension_factory_port("test/factory", port_state(2))

    check first.kind == VkActor
    check second.kind == VkActor

    discard actor_send_value(VM, first, port_message("increment"))
    check await_vm_future(actor_send_value(VM, first, port_message("get"), true)) == 10.to_value()
    check await_vm_future(actor_send_value(VM, second, port_message("get"), true)) == 2.to_value()
