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

proc stop_handler(vm: ptr VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int,
                  has_keyword_args: bool): Value {.gcsafe, nimcall.} =
  discard arg_count
  let ctx = get_positional_arg(args, 0, has_keyword_args)
  let msg = get_positional_arg(args, 1, has_keyword_args)
  let state = get_positional_arg(args, 2, has_keyword_args)

  case actor_message_kind(msg)
  of "hold":
    sleep(200)
    (state.int64 + 1).to_value()
  of "get":
    actor_reply_for_test(ctx, state)
    state
  else:
    state

suite "Actor stop semantics":
  setup:
    init_thread_pool()
    init_app_and_vm()
    init_stdlib()
    init_actor_runtime()

  test "external stop drops queued reply work and rejects later sends":
    actor_enable_for_test(1)
    let actor = actor_spawn_value(NativeFn(stop_handler).to_value(), 0.to_value())
    App.app.gene_ns.ref.ns["stop_target".to_key()] = actor
    App.app.global_ns.ref.ns["stop_target".to_key()] = actor

    discard actor_send_value(VM, actor, actor_message("hold"))
    let queued_one = actor_send_value(VM, actor, actor_message("get"), true)
    let queued_two = actor_send_value(VM, actor, actor_message("get"), true)

    discard exec_gene("(stop_target .stop)", "actor_stop_external.gene")

    let failure_one = await_vm_future_failure(queued_one)
    let failure_two = await_vm_future_failure(queued_two)

    check "Actor is stopped" in exception_message(failure_one)
    check "Actor is stopped" in exception_message(failure_two)

    expect types.Exception:
      discard actor_send_value(VM, actor, actor_message("get"))

  test "ctx.stop fails the in-flight reply and rejects later sends":
    let actor = exec_gene("""
      (do
        (gene/actor/enable ^workers 1)
        (gene/actor/spawn
          ^state 0
          (fn [ctx msg state]
            (case msg/kind
            when "stop"
              (ctx .stop)
              state
            when "get"
              (ctx .reply state)
              state
            else
              state))))
    """, "actor_ctx_stop_spawn.gene")

    let stopped = await_vm_future_failure(actor_send_value(VM, actor, actor_message("stop"), true))
    check "Actor is stopped" in exception_message(stopped)

    expect types.Exception:
      discard actor_send_value(VM, actor, actor_message("get"))
