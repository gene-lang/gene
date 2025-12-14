# Gene Garbage Collector - Reference Counting Implementation
#
# This module implements automatic memory management via reference counting
# for all managed Value types (tags >= 0xFFF8).
#
# Design:
# - All managed types have ref_count: int32 field
# - retainManaged() increments ref_count
# - releaseManaged() decrements ref_count, destroys at 0
# - =copy/=destroy/=sink hooks in Value call these automatically

import std/atomics
import ./types

# Thread-safe reference counting using atomic operations
# (Required for multi-threaded Gene programs with shared values)

template destroyAndDealloc[T](p: ptr T) =
  ## Safely destroy and deallocate a heap object
  ## Calls Nim destructors (reset) before freeing memory
  if p != nil:
    reset(p[])   # Run Nim destructors on all fields
    dealloc(p)   # Free memory

# Destroy functions for each managed type

proc destroy_string*(s: ptr String) =
  ## Destroy a String object
  destroyAndDealloc(s)

proc destroy_array*(arr: ptr ArrayObj) =
  ## Destroy an Array object
  ## Note: seq[Value] destructor will call =destroy on each Value element
  destroyAndDealloc(arr)

proc destroy_map*(m: ptr MapObj) =
  ## Destroy a Map object
  ## Note: Table[Key, Value] destructor will call =destroy on each Value
  destroyAndDealloc(m)

proc destroy_gene*(g: ptr Gene) =
  ## Destroy a Gene S-expression
  ## Note: children and props destructors will call =destroy on Values
  destroyAndDealloc(g)

proc destroy_instance*(inst: ptr InstanceObj) =
  ## Destroy an Instance object
  ## Note: instance_props destructor will call =destroy on Values
  destroyAndDealloc(inst)

proc destroy_reference*(ref_obj: ptr Reference) =
  ## Destroy a Reference object
  ## Note: case object destructors will call =destroy on Value fields
  destroyAndDealloc(ref_obj)

# Core GC operations

proc retainManaged*(raw: uint64) {.gcsafe.} =
  ## Increment reference count for a managed value
  ## Thread-safe using atomic increment
  if raw == 0:
    return  # Null pointer, nothing to retain

  let tag = raw shr 48

  case tag:
    of 0xFFF8:  # ARRAY_TAG
      let arr = cast[ptr ArrayObj](raw and PAYLOAD_MASK)
      if arr != nil:
        atomicInc(arr.ref_count)

    of 0xFFF9:  # MAP_TAG
      let m = cast[ptr MapObj](raw and PAYLOAD_MASK)
      if m != nil:
        atomicInc(m.ref_count)

    of 0xFFFA:  # INSTANCE_TAG
      let inst = cast[ptr InstanceObj](raw and PAYLOAD_MASK)
      if inst != nil:
        atomicInc(inst.ref_count)

    of 0xFFFB:  # GENE_TAG
      let g = cast[ptr Gene](raw and PAYLOAD_MASK)
      if g != nil:
        atomicInc(g.ref_count)

    of 0xFFFC:  # REF_TAG
      let ref_obj = cast[ptr Reference](raw and PAYLOAD_MASK)
      if ref_obj != nil:
        atomicInc(ref_obj.ref_count)

    of 0xFFFD:  # STRING_TAG
      let s = cast[ptr String](raw and PAYLOAD_MASK)
      if s != nil:
        atomicInc(s.ref_count)

    else:
      # Should never reach here if isManaged() check works correctly
      discard

proc releaseManaged*(raw: uint64) {.gcsafe.} =
  ## Decrement reference count for a managed value
  ## Destroys object when ref_count reaches 0
  ## Thread-safe using atomic decrement
  if raw == 0:
    return  # Null pointer, nothing to release

  let tag = raw shr 48

  case tag:
    of 0xFFF8:  # ARRAY_TAG
      let arr = cast[ptr ArrayObj](raw and PAYLOAD_MASK)
      if arr != nil:
        let old_count = atomicDec(arr.ref_count)
        if old_count == 1:  # Was 1, now 0
          destroy_array(arr)

    of 0xFFF9:  # MAP_TAG
      let m = cast[ptr MapObj](raw and PAYLOAD_MASK)
      if m != nil:
        let old_count = atomicDec(m.ref_count)
        if old_count == 1:
          destroy_map(m)

    of 0xFFFA:  # INSTANCE_TAG
      let inst = cast[ptr InstanceObj](raw and PAYLOAD_MASK)
      if inst != nil:
        let old_count = atomicDec(inst.ref_count)
        if old_count == 1:
          destroy_instance(inst)

    of 0xFFFB:  # GENE_TAG
      let g = cast[ptr Gene](raw and PAYLOAD_MASK)
      if g != nil:
        let old_count = atomicDec(g.ref_count)
        if old_count == 1:
          destroy_gene(g)

    of 0xFFFC:  # REF_TAG
      let ref_obj = cast[ptr Reference](raw and PAYLOAD_MASK)
      if ref_obj != nil:
        let old_count = atomicDec(ref_obj.ref_count)
        if old_count == 1:
          destroy_reference(ref_obj)

    of 0xFFFD:  # STRING_TAG
      let s = cast[ptr String](raw and PAYLOAD_MASK)
      if s != nil:
        let old_count = atomicDec(s.ref_count)
        if old_count == 1:
          destroy_string(s)

    else:
      # Should never reach here if isManaged() check works correctly
      discard

# GC Statistics (optional, for debugging and profiling)

when defined(gcStats):
  var gc_retains* {.threadvar.}: int
  var gc_releases* {.threadvar.}: int
  var gc_destroys* {.threadvar.}: int

  proc gc_print_stats*() =
    echo "GC Stats:"
    echo "  Retains:  ", gc_retains
    echo "  Releases: ", gc_releases
    echo "  Destroys: ", gc_destroys
    echo "  Live objects: ", gc_retains - gc_destroys
