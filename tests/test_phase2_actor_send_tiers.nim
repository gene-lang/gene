import std/[tables, times, unittest]

import ../src/gene/types except Exception
import ../src/gene/stdlib/freeze
import ../src/gene/vm
import ../src/gene/vm/actor
import ../src/gene/vm/thread

proc exec_gene(code: string, trace_name: string): Value =
  VM.exec(code, trace_name)

proc raw_id(v: Value): uint64 =
  cast[uint64](v) and PAYLOAD_MASK

proc flags_of(v: Value): uint8 =
  let u = cast[uint64](v)
  if (u and NAN_MASK) != NAN_MASK:
    return 0'u8

  let tag = u and 0xFFFF_0000_0000_0000'u64
  case tag
  of ARRAY_TAG:
    let arr = cast[ptr ArrayObj](u and PAYLOAD_MASK)
    if arr == nil: 0'u8 else: arr.flags
  of MAP_TAG:
    let m = cast[ptr MapObj](u and PAYLOAD_MASK)
    if m == nil: 0'u8 else: m.flags
  of INSTANCE_TAG:
    let inst = cast[ptr InstanceObj](u and PAYLOAD_MASK)
    if inst == nil: 0'u8 else: inst.flags
  of GENE_TAG:
    let g = cast[ptr Gene](u and PAYLOAD_MASK)
    if g == nil: 0'u8 else: g.flags
  of STRING_TAG:
    let s = cast[ptr String](u and PAYLOAD_MASK)
    if s == nil: 0'u8 else: s.flags
  of REF_TAG:
    let r = cast[ptr Reference](u and PAYLOAD_MASK)
    if r == nil: 0'u8 else: r.flags
  else:
    0'u8

proc build_frozen_closure(): Value =
  let scope = new_scope(new_scope_tracker(), nil)
  scope.tracker.add("payload".to_key())
  scope.members.add(new_map_value({
    "kind".to_key(): "closure".to_value()
  }.toTable()))

  let fn_ref = new_ref(VkFunction)
  fn_ref.fn = Function(
    name: "phase2_transport_closure",
    ns: new_namespace("phase2"),
    scope_tracker: new_scope_tracker(),
    parent_scope: scope,
    matcher: nil,
    body: @[]
  )
  freeze_value(fn_ref.to_ref_value())

suite "Phase 2 actor send tiers":
  test "primitive payloads route by value":
    let routed = prepare_actor_payload_for_send(42.to_value())

    check routed.tier == AstByValue
    check routed.value == 42.to_value()

  test "deep-frozen graphs and closures reuse the shared fast path":
    let frozen_graph = freeze_value(new_map_value({
      "items".to_key(): new_array_value(1.to_value(), 2.to_value()),
      "label".to_key(): "ready".to_value()
    }.toTable()))
    let frozen_closure = build_frozen_closure()

    let routed_graph = prepare_actor_payload_for_send(frozen_graph)
    let routed_closure = prepare_actor_payload_for_send(frozen_closure)

    check routed_graph.tier == AstSharedFrozen
    check routed_graph.value == frozen_graph
    check raw_id(routed_graph.value) == raw_id(frozen_graph)

    check routed_closure.tier == AstSharedFrozen
    check routed_closure.value == frozen_closure
    check raw_id(routed_closure.value) == raw_id(frozen_closure)

  test "mutable graphs deep clone while preserving aliases and shared frozen subgraphs":
    let mutable_leaf = new_array_value("x".to_value(), "y".to_value())
    let frozen_cfg = freeze_value(new_map_value({
      "limit".to_key(): 3.to_value()
    }.toTable()))
    let frozen_closure = build_frozen_closure()

    let payload = new_map_value({
      "left".to_key(): mutable_leaf,
      "right".to_key(): mutable_leaf,
      "cfg".to_key(): frozen_cfg,
      "handler".to_key(): frozen_closure
    }.toTable())

    let routed = prepare_actor_payload_for_send(payload)
    let cloned = routed.value
    let left = map_data(cloned)["left".to_key()]
    let right = map_data(cloned)["right".to_key()]

    check routed.tier == AstClonedMutable
    check raw_id(cloned) != raw_id(payload)
    check raw_id(left) == raw_id(right)
    check raw_id(left) != raw_id(mutable_leaf)
    check raw_id(map_data(cloned)["cfg".to_key()]) == raw_id(frozen_cfg)
    check raw_id(map_data(cloned)["handler".to_key()]) == raw_id(frozen_closure)
    check (flags_of(cloned) and SharedBit) == 0'u8
    check (flags_of(left) and SharedBit) == 0'u8

  test "capability values fail clearly":
    proc native_stub(vm: ptr VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int,
                     has_keyword_args: bool): Value {.gcsafe, nimcall.} =
      discard vm
      discard args
      discard arg_count
      discard has_keyword_args
      NIL

    expect types.Exception:
      discard prepare_actor_payload_for_send(NativeFn(native_stub).to_value())

  test "full mailboxes park actor-originated sends instead of blocking the sender worker":
    init_thread_pool()
    init_app_and_vm()
    init_stdlib()
    init_actor_runtime()
    set_actor_mailbox_limit_for_test(1)

    discard exec_gene("""
      (do
        (gene/actor/enable ^workers 2)

        (var target
          (gene/actor/spawn
            ^state 0
            (fn [ctx msg state]
              (case msg/kind
              when "hold"
                (keep_alive 200)
                (+ state 1)
              when "get"
                (ctx .reply state)
                state
              else
                (+ state 1)))))

        (var forwarder
          (gene/actor/spawn
            ^state target
            (fn [ctx msg state]
              (state .send {^kind "queued"})
              (ctx .reply "continued")
              state)))

        (target .send {^kind "hold"})
        (target .send {^kind "queued"})
        true)
    """, "phase2_actor_send_tiers_setup.gene")

    let started = epochTime()
    let forward_result = exec_gene("""
      (await (forwarder .send_expect_reply {^kind "forward"}))
    """, "phase2_actor_send_tiers_forward.gene")
    let elapsed_ms = (epochTime() - started) * 1000.0

    check forward_result == "continued".to_value()
    check elapsed_ms < 150.0

    discard exec_gene("(keep_alive 300)", "phase2_actor_send_tiers_drain.gene")
    let processed = exec_gene("""
      (await (target .send_expect_reply {^kind "get"}))
    """, "phase2_actor_send_tiers_get.gene")

    check processed == 3.to_value()
