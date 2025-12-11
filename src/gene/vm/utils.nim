# Utility functions for VM operations

import ../types/type_defs
import ../types/value_core
import ../types/helpers

proc string_to_bytes*(s: string): seq[byte] {.inline.} =
  ## Convert a string to a byte sequence
  result = newSeq[byte](s.len)
  var i = 0
  for c in s:
    result[i] = byte(ord(c))
    inc i

proc bytes_to_string*(b: seq[byte]): string {.inline.} =
  ## Convert a byte sequence to a string
  result = newString(b.len)
  var i = 0
  for v in b:
    result[i] = char(v)
    inc i

proc jit_current_stack_ptr*(vm: VirtualMachine): ptr Value {.exportc, cdecl.} =
  ## Return pointer to the current frame's stack base (for JIT use).
  if vm.frame == nil:
    return nil
  addr vm.frame.stack[0]

proc jit_current_stack_index_ptr*(vm: VirtualMachine): ptr uint16 {.exportc, cdecl.} =
  ## Return pointer to the current frame's stack_index (for JIT use).
  if vm.frame == nil:
    return nil
  addr vm.frame.stack_index

proc jit_interpreter_trampoline(vm: VirtualMachine, fn_value: Value, args: ptr UncheckedArray[Value], arg_count: int): Value {.cdecl, importc.}
proc jit_call_function(vm: VirtualMachine, target: Value, args: ptr UncheckedArray[Value], arg_count: int): Value {.cdecl, importc.}
proc jit_call_function_with_frame(vm: VirtualMachine, target: Value, args: ptr UncheckedArray[Value], arg_count: int, reuse_frame: Frame): Value {.cdecl, importc.}

#################### JIT Helpers ####################

proc jit_stack_push_value*(vm: VirtualMachine, value: Value) {.exportc, cdecl, inline.} =
  ## Push a value onto the current frame stack.
  let stack = vm.jit_current_stack_ptr()
  let idx_ptr = vm.jit_current_stack_index_ptr()
  if stack.is_nil or idx_ptr.is_nil:
    raise new_exception(type_defs.Exception, "JIT push requires an active frame")
  if idx_ptr[] >= vm.frame.stack.len.uint16:
    raise new_exception(type_defs.Exception, "JIT stack overflow")
  let stack_arr = cast[ptr UncheckedArray[Value]](stack)
  stack_arr[idx_ptr[]] = value
  idx_ptr[] = idx_ptr[] + 1

proc jit_stack_pop_value*(vm: VirtualMachine): Value {.exportc, cdecl, inline.} =
  ## Pop and return the top value from the current frame stack.
  let stack = vm.jit_current_stack_ptr()
  let idx_ptr = vm.jit_current_stack_index_ptr()
  if stack.is_nil or idx_ptr.is_nil:
    raise new_exception(type_defs.Exception, "JIT pop requires an active frame")
  if idx_ptr[] == 0:
    raise new_exception(type_defs.Exception, "JIT pop on empty stack")
  idx_ptr[] = idx_ptr[] - 1
  let stack_arr = cast[ptr UncheckedArray[Value]](stack)
  result = stack_arr[idx_ptr[]]
  stack_arr[idx_ptr[]] = NIL

proc jit_stack_peek_value*(vm: VirtualMachine): Value {.exportc, cdecl, inline.} =
  ## Return the current top value without removing it.
  let stack = vm.jit_current_stack_ptr()
  let idx_ptr = vm.jit_current_stack_index_ptr()
  if stack.is_nil or idx_ptr.is_nil:
    raise new_exception(type_defs.Exception, "JIT peek requires an active frame")
  if idx_ptr[] == 0:
    raise new_exception(type_defs.Exception, "JIT peek on empty stack")
  let stack_arr = cast[ptr UncheckedArray[Value]](stack)
  stack_arr[idx_ptr[] - 1]

proc jit_stack_dup*(vm: VirtualMachine) {.exportc, cdecl, inline.} =
  ## Duplicate the top stack value.
  let v = vm.jit_stack_peek_value()
  vm.jit_stack_push_value(v)

proc jit_stack_swap*(vm: VirtualMachine) {.exportc, cdecl, inline.} =
  ## Swap the top two stack values.
  let stack = vm.jit_current_stack_ptr()
  let idx_ptr = vm.jit_current_stack_index_ptr()
  if stack.is_nil or idx_ptr.is_nil:
    raise new_exception(type_defs.Exception, "JIT swap requires an active frame")
  if idx_ptr[] < 2:
    raise new_exception(type_defs.Exception, "JIT swap requires at least two values")
  let top_idx = idx_ptr[] - 1
  let second_idx = idx_ptr[] - 2
  let stack_arr = cast[ptr UncheckedArray[Value]](stack)
  let tmp = stack_arr[top_idx]
  stack_arr[top_idx] = stack_arr[second_idx]
  stack_arr[second_idx] = tmp

proc jit_stack_pop_discard*(vm: VirtualMachine) {.exportc, cdecl, inline.} =
  ## Pop and drop the top stack value.
  discard vm.jit_stack_pop_value()

proc jit_var_resolve_push*(vm: VirtualMachine, slot: int32): Value {.exportc, cdecl.} =
  ## Resolve a local variable and push it onto the stack.
  if vm.frame.is_nil or vm.frame.scope.isNil:
    raise new_exception(type_defs.Exception, "JIT VarResolve requires an active scope")
  let index = slot.int
  if index < 0 or index >= vm.frame.scope.members.len:
    raise new_exception(type_defs.Exception, "JIT VarResolve out of bounds")
  let value = vm.frame.scope.members[index]
  vm.jit_stack_push_value(value)
  result = value

proc jit_var_assign_top*(vm: VirtualMachine, slot: int32) {.exportc, cdecl.} =
  ## Assign the current top-of-stack value into a scope slot.
  if vm.frame.is_nil or vm.frame.scope.isNil:
    raise new_exception(type_defs.Exception, "JIT VarAssign requires an active scope")
  let index = slot.int
  if index < 0 or index >= vm.frame.scope.members.len:
    raise new_exception(type_defs.Exception, "JIT VarAssign out of bounds")
  vm.frame.scope.members[index] = vm.jit_stack_peek_value()

# Expose a mutable pointer to a scope slot for JIT inline access.
proc jit_scope_slot_ptr*(vm: VirtualMachine, slot: int32, parent_depth: int32): ptr Value {.exportc, cdecl.} =
  if vm.frame.is_nil or vm.frame.scope.isNil:
    return nil
  var scope = vm.frame.scope
  var depth = parent_depth.int
  while depth > 0 and not scope.parent.isNil:
    scope = scope.parent
    depth.dec()
  if slot < 0 or slot >= scope.members.len:
    return nil
  scope.members[slot].addr

proc jit_add_ints*(vm: VirtualMachine): Value {.exportc, cdecl, inline.} =
  ## Pop two ints, add them, and push the result.
  let rhs = vm.jit_stack_pop_value()
  let lhs = vm.jit_stack_pop_value()
  if lhs.kind != VkInt or rhs.kind != VkInt:
    raise new_exception(type_defs.Exception, "JIT add supports integers only")
  let sum = (lhs.int64 + rhs.int64).to_value()
  vm.jit_stack_push_value(sum)
  sum

proc jit_compare_lt*(vm: VirtualMachine): Value {.exportc, cdecl, inline.} =
  let rhs = vm.jit_stack_pop_value()
  let lhs = vm.jit_stack_pop_value()
  if lhs.kind != VkInt or rhs.kind != VkInt:
    raise new_exception(type_defs.Exception, "JIT < supports integers only")
  let res = (lhs.int64 < rhs.int64).to_value()
  vm.jit_stack_push_value(res)
  res

proc jit_compare_le*(vm: VirtualMachine): Value {.exportc, cdecl, inline.} =
  let rhs = vm.jit_stack_pop_value()
  let lhs = vm.jit_stack_pop_value()
  if lhs.kind != VkInt or rhs.kind != VkInt:
    raise new_exception(type_defs.Exception, "JIT <= supports integers only")
  let res = (lhs.int64 <= rhs.int64).to_value()
  vm.jit_stack_push_value(res)
  res

proc jit_compare_gt*(vm: VirtualMachine): Value {.exportc, cdecl, inline.} =
  let rhs = vm.jit_stack_pop_value()
  let lhs = vm.jit_stack_pop_value()
  if lhs.kind != VkInt or rhs.kind != VkInt:
    raise new_exception(type_defs.Exception, "JIT > supports integers only")
  let res = (lhs.int64 > rhs.int64).to_value()
  vm.jit_stack_push_value(res)
  res

proc jit_compare_ge*(vm: VirtualMachine): Value {.exportc, cdecl, inline.} =
  let rhs = vm.jit_stack_pop_value()
  let lhs = vm.jit_stack_pop_value()
  if lhs.kind != VkInt or rhs.kind != VkInt:
    raise new_exception(type_defs.Exception, "JIT >= supports integers only")
  let res = (lhs.int64 >= rhs.int64).to_value()
  vm.jit_stack_push_value(res)
  res

proc jit_compare_eq*(vm: VirtualMachine): Value {.exportc, cdecl, inline.} =
  let rhs = vm.jit_stack_pop_value()
  let lhs = vm.jit_stack_pop_value()
  if lhs.kind != VkInt or rhs.kind != VkInt:
    raise new_exception(type_defs.Exception, "JIT == supports integers only")
  let res = (lhs.int64 == rhs.int64).to_value()
  vm.jit_stack_push_value(res)
  res

proc jit_sub_ints*(vm: VirtualMachine): Value {.exportc, cdecl, inline.} =
  ## Pop two ints, subtract rhs from lhs, and push the result.
  let rhs = vm.jit_stack_pop_value()
  let lhs = vm.jit_stack_pop_value()
  if lhs.kind != VkInt or rhs.kind != VkInt:
    raise new_exception(type_defs.Exception, "JIT sub supports integers only")
  let diff = (lhs.int64 - rhs.int64).to_value()
  vm.jit_stack_push_value(diff)
  diff

proc jit_pop_is_false*(vm: VirtualMachine): bool {.exportc, cdecl, inline.} =
  ## Pop the top value and report whether it is falsey.
  let v = vm.jit_stack_pop_value()
  (v == FALSE) or (v == NIL)

proc jit_jump_if_match_success*(vm: VirtualMachine, index: int32): bool {.exportc, cdecl.} =
  ## Check whether the matcher slot exists (used by JumpIfMatchSuccess).
  if vm.frame == nil or vm.frame.scope.isNil:
    return false
  vm.frame.scope.members.len > index

proc jit_resolve_symbol*(vm: VirtualMachine, key: Key): Value {.exportc, cdecl.} =
  ## Resolve a symbol using the same namespace order as the interpreter.
  let symbol_key = cast[uint64](key)
  case symbol_key:
    of SYM_UNDERSCORE:
      vm.jit_stack_push_value(PLACEHOLDER)
      return PLACEHOLDER
    of SYM_SELF:
      if vm.frame != nil and vm.frame.args.kind == VkGene and vm.frame.args.gene.children.len > 0:
        let v = vm.frame.args.gene.children[0]
        vm.jit_stack_push_value(v)
        return v
      vm.jit_stack_push_value(NIL)
      return NIL
    of SYM_GENE:
      vm.jit_stack_push_value(App.app.gene_ns)
      return App.app.gene_ns
    of SYM_NS:
      if vm.frame != nil:
        let r = new_ref(VkNamespace)
        r.ns = vm.frame.ns
        let v = r.to_ref_value()
        vm.jit_stack_push_value(v)
        return v
      vm.jit_stack_push_value(NIL)
      return NIL
    else:
      discard

  var value = if vm.frame != nil and vm.frame.ns != nil: vm.frame.ns[key] else: NIL
  var found_ns = if vm.frame != nil: vm.frame.ns else: nil
  if value == NIL and vm.thread_local_ns != nil:
    value = vm.thread_local_ns[key]
    if value != NIL:
      found_ns = vm.thread_local_ns
  if value == NIL:
    let global_ns = App.app.global_ns.ref.ns
    value = global_ns[key]
    if value != NIL:
      found_ns = global_ns
  if value == NIL:
    let gene_ns = App.app.gene_ns.ref.ns
    value = gene_ns[key]
    if value != NIL:
      found_ns = gene_ns
  if value == NIL:
    let genex_ns = App.app.genex_ns.ref.ns
    value = genex_ns[key]
    if value != NIL:
      found_ns = genex_ns

  # Update inline cache if present
  if vm.cu != nil and vm.pc < vm.cu.inline_caches.len:
    let cache = vm.cu.inline_caches[vm.pc].addr
    cache.ns = found_ns
    if found_ns != nil:
      cache.version = found_ns.version
    cache.value = value

  vm.jit_stack_push_value(value)
  value

proc jit_gene_start*(vm: VirtualMachine) {.exportc, cdecl.} =
  ## Push a fresh Gene value.
  vm.jit_stack_push_value(new_gene_value())

proc jit_gene_start_default*(vm: VirtualMachine) {.exportc, cdecl.} =
  ## Prepare a gene-like value for function call. We don't allocate frames here
  ## to avoid double allocation - let exec_function handle frame pooling efficiently.
  let gene_type = vm.jit_stack_pop_value()
  var g = new_gene_value()
  g.gene.type = gene_type
  vm.jit_stack_push_value(g)

proc jit_gene_set_type*(vm: VirtualMachine) {.exportc, cdecl.} =
  ## Set the type on the current gene-like value.
  let value = vm.jit_stack_pop_value()
  let current = vm.jit_stack_peek_value()
  case current.kind
  of VkGene:
    current.gene.type = value
  of VkFrame:
    if current.ref.frame.args.kind != VkGene:
      current.ref.frame.args = new_gene_value()
    current.ref.frame.args.gene.type = value
  else:
    raise new_exception(type_defs.Exception, "GeneSetType unsupported for " & $current.kind)

proc jit_gene_add_child*(vm: VirtualMachine) {.exportc, cdecl.} =
  ## Add a child value to the current gene/frame args.
  let child = vm.jit_stack_pop_value()
  let current = vm.jit_stack_peek_value()
  case current.kind
  of VkFrame:
    if current.ref.frame.args.kind != VkGene:
      current.ref.frame.args = new_gene_value()
    current.ref.frame.args.gene.children.add(child)
  of VkNativeFrame:
    if current.ref.native_frame.args.kind != VkGene:
      current.ref.native_frame.args = new_gene_value()
    current.ref.native_frame.args.gene.children.add(child)
  of VkGene:
    current.gene.children.add(child)
  of VkNil:
    discard
  else:
    raise new_exception(type_defs.Exception, "GeneAddChild unsupported for " & $current.kind)

proc jit_gene_end*(vm: VirtualMachine): Value {.exportc, cdecl.} =
  ## Finalize a gene: if it's a function call, invoke via interpreter.
  let current = vm.jit_stack_pop_value()
  case current.kind
  of VkGene:
    let target = current.gene.type
    if target.kind == VkFunction:
      # Function call: invoke via interpreter for efficient frame pooling
      let args = current.gene.children
      let args_ptr = if args.len > 0: cast[ptr UncheckedArray[Value]](args[0].unsafeAddr) else: nil
      result = jit_call_function(vm, target, args_ptr, args.len)
    else:
      # Not a function call, just push the gene value
      vm.jit_stack_push_value(current)
      result = current
  of VkFrame:
    # Legacy frame handling - should rarely be used now
    var frame = current.ref.frame
    let target = frame.target
    var args_seq: seq[Value] = @[]
    if frame.args.kind == VkGene:
      args_seq = frame.args.gene.children
    result = jit_call_function_with_frame(
      vm,
      target,
      if args_seq.len > 0: cast[ptr UncheckedArray[Value]](args_seq[0].addr) else: nil,
      args_seq.len,
      frame
    )
    frame.free()
  else:
    raise new_exception(type_defs.Exception, "GeneEnd unsupported for " & $current.kind)

proc jit_tail_call*(vm: VirtualMachine): Value {.exportc, cdecl.} =
  ## Simplified tail-call handling: treat as GeneEnd for now.
  jit_gene_end(vm)

proc jit_throw*(vm: VirtualMachine) {.exportc, cdecl.} =
  ## Minimal throw implementation for JIT paths.
  let value = vm.jit_stack_pop_value()
  raise new_exception(type_defs.Exception, "Gene exception: " & $value)

proc jit_unified_call0*(vm: VirtualMachine) {.exportc, cdecl.} =
  ## Zero-argument function call: target is on stack, call via interpreter and push result.
  let target = vm.jit_stack_pop_value()
  discard jit_call_function(vm, target, nil, 0)

proc jit_unified_call1*(vm: VirtualMachine) {.exportc, cdecl.} =
  ## Single-argument function call: arg and target on stack, call via interpreter and push result.
  let arg = vm.jit_stack_pop_value()
  let target = vm.jit_stack_pop_value()
  var args_arr = [arg]
  discard jit_call_function(vm, target, cast[ptr UncheckedArray[Value]](args_arr[0].addr), 1)

proc jit_unified_call*(vm: VirtualMachine, arg_count: int) {.exportc, cdecl.} =
  ## Multi-argument function call: args and target on stack, call via interpreter and push result.
  var args_seq = newSeq[Value](arg_count)
  for i in countdown(arg_count - 1, 0):
    args_seq[i] = vm.jit_stack_pop_value()
  let target = vm.jit_stack_pop_value()
  let args_ptr = if arg_count > 0: cast[ptr UncheckedArray[Value]](args_seq[0].addr) else: nil
  discard jit_call_function(vm, target, args_ptr, arg_count)

proc resolve_scope_with_parent(vm: VirtualMachine, slot: int, parent_depth: int): Value =
  ## Helper to resolve a scope slot honoring parent depth for JIT helpers.
  if vm.frame.is_nil or vm.frame.scope.isNil:
    raise new_exception(type_defs.Exception, "JIT Var op requires an active scope")
  var scope = vm.frame.scope
  for _ in 0..<parent_depth:
    if scope.parent.isNil:
      raise new_exception(type_defs.Exception, "JIT Var op parent scope missing")
    scope = scope.parent
  if slot < 0 or slot >= scope.members.len:
    raise new_exception(type_defs.Exception, "JIT Var op out of bounds")
  scope.members[slot]

proc jit_scope_start*(vm: VirtualMachine, tracker_val: Value) {.exportc, cdecl.} =
  ## Create a new scope with an optional tracker and set it on the current frame.
  if vm.frame.is_nil:
    raise new_exception(type_defs.Exception, "JIT ScopeStart requires an active frame")
  var tracker: ScopeTracker
  if tracker_val.kind == VkNil:
    tracker = new_scope_tracker()
  elif tracker_val.kind == VkScopeTracker:
    tracker = tracker_val.ref.scope_tracker
  else:
    raise new_exception(type_defs.Exception, "IkScopeStart: expected ScopeTracker or Nil, got " & $tracker_val.kind)
  vm.frame.scope = new_scope(tracker, vm.frame.scope)

proc jit_scope_end*(vm: VirtualMachine) {.exportc, cdecl.} =
  ## End the current scope, restoring the parent.
  if vm.frame.is_nil or vm.frame.scope.isNil:
    raise new_exception(type_defs.Exception, "JIT ScopeEnd requires an active scope")
  let old_scope = vm.frame.scope
  vm.frame.scope = vm.frame.scope.parent
  old_scope.free()

proc jit_var_le_value*(vm: VirtualMachine, slot: int, parent_depth: int, literal_value: Value) {.exportc, cdecl.} =
  ## Compare variable at slot (with parent depth) to a literal (<=), push true/false.
  let var_value = vm.resolve_scope_with_parent(slot, parent_depth)
  var result: bool
  case var_value.kind
  of VkInt:
    case literal_value.kind
    of VkInt:
      result = var_value.int64 <= literal_value.int64
    of VkFloat:
      result = var_value.int64.float <= literal_value.float
    else:
      result = false
  of VkFloat:
    case literal_value.kind
    of VkInt:
      result = var_value.float <= literal_value.int64.float
    of VkFloat:
      result = var_value.float <= literal_value.float
    else:
      result = false
  else:
    result = false
  vm.jit_stack_push_value(if result: TRUE else: FALSE)

proc jit_var_lt_value*(vm: VirtualMachine, slot: int, parent_depth: int, literal_value: Value) {.exportc, cdecl.} =
  ## Compare variable at slot (with parent depth) to a literal (<), push true/false.
  let var_value = vm.resolve_scope_with_parent(slot, parent_depth)
  var result: bool
  case var_value.kind
  of VkInt:
    case literal_value.kind
    of VkInt:
      result = var_value.int64 < literal_value.int64
    of VkFloat:
      result = var_value.int64.float < literal_value.float
    else:
      result = false
  of VkFloat:
    case literal_value.kind
    of VkInt:
      result = var_value.float < literal_value.int64.float
    of VkFloat:
      result = var_value.float < literal_value.float
    else:
      result = false
  else:
    result = false
  vm.jit_stack_push_value(if result: TRUE else: FALSE)

proc jit_var_gt_value*(vm: VirtualMachine, slot: int, parent_depth: int, literal_value: Value) {.exportc, cdecl.} =
  ## Compare variable at slot (with parent depth) to a literal (>), push true/false.
  let var_value = vm.resolve_scope_with_parent(slot, parent_depth)
  var result: bool
  case var_value.kind
  of VkInt:
    case literal_value.kind
    of VkInt:
      result = var_value.int64 > literal_value.int64
    of VkFloat:
      result = var_value.int64.float > literal_value.float
    else:
      result = false
  of VkFloat:
    case literal_value.kind
    of VkInt:
      result = var_value.float > literal_value.int64.float
    of VkFloat:
      result = var_value.float > literal_value.float
    else:
      result = false
  else:
    result = false
  vm.jit_stack_push_value(if result: TRUE else: FALSE)

proc jit_var_ge_value*(vm: VirtualMachine, slot: int, parent_depth: int, literal_value: Value) {.exportc, cdecl.} =
  ## Compare variable at slot (with parent depth) to a literal (>=), push true/false.
  let var_value = vm.resolve_scope_with_parent(slot, parent_depth)
  var result: bool
  case var_value.kind
  of VkInt:
    case literal_value.kind
    of VkInt:
      result = var_value.int64 >= literal_value.int64
    of VkFloat:
      result = var_value.int64.float >= literal_value.float
    else:
      result = false
  of VkFloat:
    case literal_value.kind
    of VkInt:
      result = var_value.float >= literal_value.int64.float
    of VkFloat:
      result = var_value.float >= literal_value.float
    else:
      result = false
  else:
    result = false
  vm.jit_stack_push_value(if result: TRUE else: FALSE)

proc jit_var_eq_value*(vm: VirtualMachine, slot: int, parent_depth: int, literal_value: Value) {.exportc, cdecl.} =
  ## Compare variable at slot (with parent depth) to a literal (==), push true/false.
  let var_value = vm.resolve_scope_with_parent(slot, parent_depth)
  var result: bool
  case var_value.kind
  of VkInt:
    case literal_value.kind
    of VkInt:
      result = var_value.int64 == literal_value.int64
    of VkFloat:
      result = var_value.int64.float == literal_value.float
    else:
      result = false
  of VkFloat:
    case literal_value.kind
    of VkInt:
      result = var_value.float == literal_value.int64.float
    of VkFloat:
      result = var_value.float == literal_value.float
    else:
      result = false
  else:
    result = false
  vm.jit_stack_push_value(if result: TRUE else: FALSE)

proc jit_var_sub_value*(vm: VirtualMachine, slot: int, parent_depth: int, literal_value: Value) {.exportc, cdecl.} =
  ## Subtract literal value from variable at slot (with parent depth), push result.
  let var_value = vm.resolve_scope_with_parent(slot, parent_depth)
  var result: Value
  case var_value.kind
  of VkInt:
    case literal_value.kind
    of VkInt:
      result = (var_value.int64 - literal_value.int64).to_value
    of VkFloat:
      result = (var_value.int64.float - literal_value.float).to_value
    else:
      result = NIL
  of VkFloat:
    case literal_value.kind
    of VkInt:
      result = (var_value.float - literal_value.int64.float).to_value
    of VkFloat:
      result = (var_value.float - literal_value.float).to_value
    else:
      result = NIL
  else:
    result = NIL
  vm.jit_stack_push_value(result)
