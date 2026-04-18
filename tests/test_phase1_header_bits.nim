import unittest

import gene/types except Exception

proc flags_of(v: Value): uint8 =
  let u = cast[uint64](v)
  if (u and NAN_MASK) != NAN_MASK:
    return 0'u8

  let tag = u and 0xFFFF_0000_0000_0000u64
  case tag:
    of ARRAY_TAG:
      let arr = cast[ptr ArrayObj](u and PAYLOAD_MASK)
      return if arr == nil: 0'u8 else: arr.flags
    of MAP_TAG:
      let m = cast[ptr MapObj](u and PAYLOAD_MASK)
      return if m == nil: 0'u8 else: m.flags
    of INSTANCE_TAG:
      let inst = cast[ptr InstanceObj](u and PAYLOAD_MASK)
      return if inst == nil: 0'u8 else: inst.flags
    of GENE_TAG:
      let g = cast[ptr Gene](u and PAYLOAD_MASK)
      return if g == nil: 0'u8 else: g.flags
    of STRING_TAG:
      let s = cast[ptr String](u and PAYLOAD_MASK)
      return if s == nil: 0'u8 else: s.flags
    of REF_TAG:
      let r = cast[ptr Reference](u and PAYLOAD_MASK)
      return if r == nil: 0'u8 else: r.flags
    else:
      return 0'u8

proc clear_flags(v: Value) =
  let u = cast[uint64](v)
  if (u and NAN_MASK) != NAN_MASK:
    return

  let tag = u and 0xFFFF_0000_0000_0000u64
  case tag:
    of ARRAY_TAG:
      let arr = cast[ptr ArrayObj](u and PAYLOAD_MASK)
      if arr != nil:
        arr.flags = 0
    of MAP_TAG:
      let m = cast[ptr MapObj](u and PAYLOAD_MASK)
      if m != nil:
        m.flags = 0
    of INSTANCE_TAG:
      let inst = cast[ptr InstanceObj](u and PAYLOAD_MASK)
      if inst != nil:
        inst.flags = 0
    of GENE_TAG:
      let g = cast[ptr Gene](u and PAYLOAD_MASK)
      if g != nil:
        g.flags = 0
    of STRING_TAG:
      let s = cast[ptr String](u and PAYLOAD_MASK)
      if s != nil:
        s.flags = 0
    of REF_TAG:
      let r = cast[ptr Reference](u and PAYLOAD_MASK)
      if r != nil:
        r.flags = 0
    else:
      discard

proc expect_managed_bits(v: Value) =
  clear_flags(v)
  check flags_of(v) == 0'u8
  check deep_frozen(v) == false
  check shared(v) == false

  setDeepFrozen(v)
  check (flags_of(v) and DeepFrozenBit) != 0
  check deep_frozen(v)
  check shared(v) == false

  setShared(v)
  check (flags_of(v) and DeepFrozenBit) != 0
  check (flags_of(v) and SharedBit) != 0
  check deep_frozen(v)
  check shared(v)

  clear_flags(v)
  check flags_of(v) == 0'u8
  check deep_frozen(v) == false
  check shared(v) == false

suite "Phase 1 header bits":
  test "direct managed headers expose deep-frozen and shared flags":
    expect_managed_bits(new_array_value())
    expect_managed_bits(new_map_value())
    expect_managed_bits(new_gene_value())
    expect_managed_bits("header-bits".to_value())
    expect_managed_bits(new_bytes_value(@[1'u8, 2, 3, 4, 5, 6, 7]))
    expect_managed_bits(new_instance_value(nil))

  test "reference-backed managed headers expose deep-frozen and shared flags":
    expect_managed_bits(new_hash_map_value())
    expect_managed_bits(new_ref(VkClass).to_ref_value())
    expect_managed_bits(new_ref(VkFunction).to_ref_value())
    expect_managed_bits(new_ref(VkBlock).to_ref_value())
    expect_managed_bits(new_ref(VkBoundMethod).to_ref_value())
    expect_managed_bits(new_ref(VkNativeFn).to_ref_value())

  test "non-heap values default to deep-frozen and reject shared bit writes":
    let non_heap_values = @[
      42.to_value(),
      3.14.to_value(),
      TRUE,
      NIL,
      'z'.to_value(),
      "phase1-symbol".to_symbol_value(),
      EMPTY_STRING,
      new_bytes_value(@[1'u8, 2, 3, 4, 5]),
      new_bytes_value(@[1'u8, 2, 3, 4, 5, 6]),
    ]

    for v in non_heap_values:
      check deep_frozen(v)
      check shared(v) == false
      setDeepFrozen(v)
      check deep_frozen(v)
      expect CatchableError:
        setShared(v)
