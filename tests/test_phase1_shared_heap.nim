import std/[atomics, os, strutils, tables, unittest]

import ../src/gene/types except Exception
import ../src/gene/stdlib/freeze

type
  SharedSlot = object
    raw: Atomic[uint64]

  WorkerJob = object
    slot: ptr SharedSlot
    loops: int
    expected_leaf_sum: int
    observed_checksum: int

proc ref_count_of(v: Value): int =
  let u = cast[uint64](v)
  let tag = u and 0xFFFF_0000_0000_0000'u64

  case tag
  of ARRAY_TAG:
    let arr = cast[ptr ArrayObj](u and PAYLOAD_MASK)
    if arr == nil: 0 else: arr.ref_count
  of MAP_TAG:
    let m = cast[ptr MapObj](u and PAYLOAD_MASK)
    if m == nil: 0 else: m.ref_count
  of GENE_TAG:
    let g = cast[ptr Gene](u and PAYLOAD_MASK)
    if g == nil: 0 else: g.ref_count
  of STRING_TAG:
    let s = cast[ptr String](u and PAYLOAD_MASK)
    if s == nil: 0 else: s.ref_count
  of REF_TAG:
    let r = cast[ptr Reference](u and PAYLOAD_MASK)
    if r == nil: 0 else: r.ref_count
  else:
    0

proc parse_env_int(name: string, default: int): int =
  let raw = getEnv(name)
  if raw.len == 0:
    return default
  try:
    parseInt(raw)
  except ValueError:
    default

proc read_payload(v: Value): int {.gcsafe.}

proc read_array_payload(v: Value): int {.gcsafe.} =
  var total = 0
  for item in array_data(v):
    total += read_payload(item)
  total

proc read_map_payload(v: Value): int {.gcsafe.} =
  var total = 0
  for _, value in map_data(v):
    total += read_payload(value)
  total

proc read_hash_map_payload(v: Value): int {.gcsafe.} =
  var total = 0
  for item in hash_map_items(v):
    total += read_payload(item)
  total

proc read_gene_payload(v: Value): int {.gcsafe.} =
  var total = 0
  if not v.gene.type.is_nil:
    total += read_payload(v.gene.type)
  for _, value in v.gene.props:
    total += read_payload(value)
  for child in v.gene.children:
    total += read_payload(child)
  total

proc read_payload(v: Value): int {.gcsafe.} =
  doAssert deep_frozen(v)
  if isManaged(v):
    doAssert shared(v)

  case v.kind
  of VkInt:
    v.to_int().int
  of VkString:
    v.str.len
  of VkBytes:
    var total = 0
    for i in 0 ..< bytes_len(v):
      total += bytes_at(v, i).int
    total
  of VkArray:
    read_array_payload(v)
  of VkMap:
    read_map_payload(v)
  of VkHashMap:
    read_hash_map_payload(v)
  of VkGene:
    read_gene_payload(v)
  of VkSymbol:
    get_symbol((cast[uint64](v) and PAYLOAD_MASK).int).len
  else:
    0

proc build_shared_value(depth: int): Value =
  var leaf = new_array_value()
  for i in 0 ..< depth:
    array_data(leaf).add((i + 1).to_value())

  var payload_map = new_map_value({
    "numbers".to_key(): leaf,
    "bytes".to_key(): new_bytes_value(@[1'u8, 3, 5, 7, 9, 11, 13, 15]),
    "label".to_key(): "phase1-shared-heap".to_value()
  }.toTable())

  var props = new_map_value({
    "payload".to_key(): payload_map,
    "meta".to_key(): new_hash_map_value(@[
      "status".to_value(), "ready".to_value(),
      "depth".to_value(), depth.to_value()
    ])
  }.toTable())

  var root = new_gene_value("SharedRoot".to_symbol_value())
  root.gene.props["config".to_key()] = props
  root.gene.children.add(new_array_value(
    payload_map,
    new_gene_value("Leaf".to_symbol_value())
  ))
  array_data(root.gene.children[0])[1].gene.props["value".to_key()] = new_map_value({
    "checksum".to_key(): depth.to_value()
  }.toTable())
  root

proc worker_read(job: ptr WorkerJob) {.thread, gcsafe.} =
  var total = 0
  for _ in 0 ..< job.loops:
    var raw = 0'u64
    while raw == 0'u64:
      raw = load(job.slot.raw)
    retainManaged(raw)
    let value = cast[Value](raw)
    total += read_payload(value)
    releaseManaged(raw)
  job.observed_checksum = total

suite "Phase 1 shared heap":
  test "frozen values are safely readable across threads with exact refcount":
    let threads = parse_env_int("GENE_SHARED_HEAP_THREADS", 8)
    let loops = parse_env_int("GENE_SHARED_HEAP_LOOPS", 200)
    let depth = parse_env_int("GENE_SHARED_HEAP_DEPTH", 8)

    check threads > 0
    check loops > 0
    check depth > 0

    var shared_root = freeze_value(build_shared_value(depth))
    let expected_leaf_sum = read_payload(shared_root)
    let baseline_refcount = ref_count_of(shared_root)

    check deep_frozen(shared_root)
    check shared(shared_root)
    check baseline_refcount >= 1

    var slot: SharedSlot
    slot.raw.store(shared_root.raw)

    var jobs = newSeq[WorkerJob](threads)
    var workers = newSeq[system.Thread[ptr WorkerJob]](threads)

    for i in 0 ..< threads:
      jobs[i] = WorkerJob(
        slot: addr slot,
        loops: loops,
        expected_leaf_sum: expected_leaf_sum,
        observed_checksum: 0
      )
      createThread(workers[i], worker_read, addr jobs[i])

    for worker in workers.mitems:
      joinThread(worker)

    for job in jobs:
      check job.observed_checksum == job.expected_leaf_sum * loops

    check ref_count_of(shared_root) == baseline_refcount
    check read_payload(shared_root) == expected_leaf_sum
