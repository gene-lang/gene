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

#################### JIT Helpers ####################

proc jit_stack_push_value*(vm: VirtualMachine, value: Value) {.exportc, cdecl.} =
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

proc jit_stack_pop_value*(vm: VirtualMachine): Value {.exportc, cdecl.} =
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

proc jit_stack_peek_value*(vm: VirtualMachine): Value {.exportc, cdecl.} =
  ## Return the current top value without removing it.
  let stack = vm.jit_current_stack_ptr()
  let idx_ptr = vm.jit_current_stack_index_ptr()
  if stack.is_nil or idx_ptr.is_nil:
    raise new_exception(type_defs.Exception, "JIT peek requires an active frame")
  if idx_ptr[] == 0:
    raise new_exception(type_defs.Exception, "JIT peek on empty stack")
  let stack_arr = cast[ptr UncheckedArray[Value]](stack)
  stack_arr[idx_ptr[] - 1]

proc jit_stack_dup*(vm: VirtualMachine) {.exportc, cdecl.} =
  ## Duplicate the top stack value.
  let v = vm.jit_stack_peek_value()
  vm.jit_stack_push_value(v)

proc jit_stack_swap*(vm: VirtualMachine) {.exportc, cdecl.} =
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

proc jit_stack_pop_discard*(vm: VirtualMachine) {.exportc, cdecl.} =
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

proc jit_add_ints*(vm: VirtualMachine): Value {.exportc, cdecl.} =
  ## Pop two ints, add them, and push the result.
  let rhs = vm.jit_stack_pop_value()
  let lhs = vm.jit_stack_pop_value()
  if lhs.kind != VkInt or rhs.kind != VkInt:
    raise new_exception(type_defs.Exception, "JIT add supports integers only")
  let sum = (lhs.int64 + rhs.int64).to_value()
  vm.jit_stack_push_value(sum)
  sum

proc jit_compare_lt*(vm: VirtualMachine): Value {.exportc, cdecl.} =
  let rhs = vm.jit_stack_pop_value()
  let lhs = vm.jit_stack_pop_value()
  if lhs.kind != VkInt or rhs.kind != VkInt:
    raise new_exception(type_defs.Exception, "JIT < supports integers only")
  let res = (lhs.int64 < rhs.int64).to_value()
  vm.jit_stack_push_value(res)
  res

proc jit_compare_le*(vm: VirtualMachine): Value {.exportc, cdecl.} =
  let rhs = vm.jit_stack_pop_value()
  let lhs = vm.jit_stack_pop_value()
  if lhs.kind != VkInt or rhs.kind != VkInt:
    raise new_exception(type_defs.Exception, "JIT <= supports integers only")
  let res = (lhs.int64 <= rhs.int64).to_value()
  vm.jit_stack_push_value(res)
  res

proc jit_compare_gt*(vm: VirtualMachine): Value {.exportc, cdecl.} =
  let rhs = vm.jit_stack_pop_value()
  let lhs = vm.jit_stack_pop_value()
  if lhs.kind != VkInt or rhs.kind != VkInt:
    raise new_exception(type_defs.Exception, "JIT > supports integers only")
  let res = (lhs.int64 > rhs.int64).to_value()
  vm.jit_stack_push_value(res)
  res

proc jit_compare_ge*(vm: VirtualMachine): Value {.exportc, cdecl.} =
  let rhs = vm.jit_stack_pop_value()
  let lhs = vm.jit_stack_pop_value()
  if lhs.kind != VkInt or rhs.kind != VkInt:
    raise new_exception(type_defs.Exception, "JIT >= supports integers only")
  let res = (lhs.int64 >= rhs.int64).to_value()
  vm.jit_stack_push_value(res)
  res

proc jit_compare_eq*(vm: VirtualMachine): Value {.exportc, cdecl.} =
  let rhs = vm.jit_stack_pop_value()
  let lhs = vm.jit_stack_pop_value()
  if lhs.kind != VkInt or rhs.kind != VkInt:
    raise new_exception(type_defs.Exception, "JIT == supports integers only")
  let res = (lhs.int64 == rhs.int64).to_value()
  vm.jit_stack_push_value(res)
  res

proc jit_sub_ints*(vm: VirtualMachine): Value {.exportc, cdecl.} =
  ## Pop two ints, subtract rhs from lhs, and push the result.
  let rhs = vm.jit_stack_pop_value()
  let lhs = vm.jit_stack_pop_value()
  if lhs.kind != VkInt or rhs.kind != VkInt:
    raise new_exception(type_defs.Exception, "JIT sub supports integers only")
  let diff = (lhs.int64 - rhs.int64).to_value()
  vm.jit_stack_push_value(diff)
  diff

proc jit_pop_is_false*(vm: VirtualMachine): bool {.exportc, cdecl.} =
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
  ## Prepare call frame for a regular function invocation (minimal subset).
  let gene_type = vm.jit_stack_pop_value()
  case gene_type.kind
  of VkFunction:
    let f = gene_type.ref.fn
    var scope: Scope
    if f.matcher.is_empty():
      scope = f.parent_scope
      if scope != nil:
        scope.ref_count.inc()
    else:
      scope = new_scope(f.scope_tracker, f.parent_scope)

    var r = new_ref(VkFrame)
    r.frame = new_frame()
    r.frame.kind = FkFunction
    r.frame.target = gene_type
    r.frame.scope = scope
    vm.jit_stack_push_value(r.to_ref_value())
  else:
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
  ## Finalize a gene or frame; for functions, call via the interpreter trampoline.
  let current = vm.jit_stack_pop_value()
  case current.kind
  of VkFrame:
    let frame = current.ref.frame
    let target = frame.target
    var args_seq: seq[Value] = @[]
    if frame.args.kind == VkGene:
      args_seq = frame.args.gene.children
    let res = jit_call_function(
      vm,
      target,
      if args_seq.len > 0: cast[ptr UncheckedArray[Value]](args_seq[0].addr) else: nil,
      args_seq.len
    )
    vm.jit_stack_push_value(res)
    result = res
  of VkGene:
    vm.jit_stack_push_value(current)
    result = current
  else:
    raise new_exception(type_defs.Exception, "GeneEnd unsupported for " & $current.kind)

proc jit_tail_call*(vm: VirtualMachine): Value {.exportc, cdecl.} =
  ## Simplified tail-call handling: treat as GeneEnd for now.
  jit_gene_end(vm)

proc jit_throw*(vm: VirtualMachine) {.exportc, cdecl.} =
  ## Minimal throw implementation for JIT paths.
  let value = vm.jit_stack_pop_value()
  raise new_exception(type_defs.Exception, "Gene exception: " & $value)
