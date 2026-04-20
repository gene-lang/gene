import std/[os, strutils, tables, times, unittest]

import gene/types except Exception
import gene/vm
import gene/vm/actor
import gene/vm/thread

proc exec_gene(code: string, trace_name: string): Value =
  VM.exec(code, trace_name)

proc actor_message(kind: string): Value =
  new_map_value({
    "kind".to_key(): kind.to_value()
  }.toTable())

proc actor_message_kind(msg: Value): string =
  if msg.kind != VkMap:
    return ""
  let kind = map_data(msg).getOrDefault("kind".to_key(), NIL)
  if kind.kind != VkString:
    return ""
  kind.str

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

proc await_vm_future_failure(future_value: Value, timeout_ms = 2_000): Value =
  let deadline = epochTime() + (timeout_ms.float / 1000.0)
  let future = future_value.ref.future
  while future.state == FsPending and epochTime() < deadline:
    VM.event_loop_counter = 100
    VM.poll_event_loop()
    sleep(10)

  check future.state != FsPending
  check future.state == FsFailure
  future.value

proc exception_message(exc: Value): string =
  if exc.kind != VkInstance:
    return $exc
  instance_props(exc).getOrDefault("message".to_key(), NIL).str

proc lifecycle_handler(vm: ptr VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int,
                       has_keyword_args: bool): Value {.gcsafe, nimcall.} =
  discard arg_count
  let ctx = get_positional_arg(args, 0, has_keyword_args)
  let msg = get_positional_arg(args, 1, has_keyword_args)
  let state = get_positional_arg(args, 2, has_keyword_args)

  case actor_message_kind(msg)
  of "get":
    actor_reply_for_test(ctx, state)
    state
  of "increment":
    (state.int64 + 1).to_value()
  of "boom":
    raise new_exception(types.Exception, "actor boom")
  of "sleep":
    sleep(200)
    state
  else:
    state

suite "Actor reply futures":
  setup:
    init_thread_pool()
    init_app_and_vm()
    init_stdlib()
    init_actor_runtime()

  test "send_expect_reply resolves success and handler failure keeps the actor alive":
    actor_enable_for_test(1)
    let actor = actor_spawn_value(NativeFn(lifecycle_handler).to_value(), 0.to_value())

    let ok = await_vm_future(actor_send_value(VM, actor, actor_message("get"), true))
    check ok == 0.to_value()

    let failure = await_vm_future_failure(actor_send_value(VM, actor, actor_message("boom"), true))
    check failure.kind == VkInstance
    check "actor boom" in exception_message(failure)

    discard actor_send_value(VM, actor, actor_message("increment"))
    let recovered = await_vm_future(actor_send_value(VM, actor, actor_message("get"), true))
    check recovered == 1.to_value()

  test "await timeout fails the actor reply future through the existing Future surface":
    actor_enable_for_test(1)
    let actor = actor_spawn_value(NativeFn(lifecycle_handler).to_value(), 7.to_value())
    App.app.gene_ns.ref.ns["reply_target".to_key()] = actor
    App.app.global_ns.ref.ns["reply_target".to_key()] = actor

    let result = exec_gene("""
      (try
        (await ^timeout 50 (reply_target .send_expect_reply {^kind "sleep"}))
        "unexpected"
      catch *
        "timed_out")
    """, "actor_reply_timeout.gene")

    check result == "timed_out".to_value()
