## exec_continue, exec_function, exec_method_impl, exec_method, exec_method_kw_impl,
## exec_method_kw, exec_callable, exec_generator_impl.
## Included from vm.nim — shares its scope.

proc exec_continue*(self: ptr VirtualMachine): Value =
  # Call the main exec loop which now uses self.pc
  return self.exec()

# Execute a Gene function with given arguments and return the result
# This preserves the VM state and can be called from async contexts
proc exec_function*(self: ptr VirtualMachine, fn: Value, args: seq[Value]): Value {.exportc.} =
  if fn.kind != VkFunction:
    return NIL

  let f = fn.ref.fn

  var native_result: Value
  if self.try_native_call(f, args, native_result):
    return native_result

  # Compile if needed
  if f.body_compiled == nil:
    f.compile()

  # Save current VM state
  let saved_cu = self.cu
  let saved_pc = self.pc
  let saved_frame = self.frame

  # Create a new scope for the function
  var scope: Scope
  if f.matcher.is_empty():
    scope = f.parent_scope
    # Increment ref_count since the frame will own this reference
    if scope != nil:
      scope.ref_count.inc()
  else:
    scope = new_scope(f.scope_tracker, f.parent_scope)

  # Create a new frame for the function
  let new_frame = new_frame()
  new_frame.kind = FkFunction
  new_frame.target = fn
  new_frame.scope = scope
  new_frame.ns = f.ns
  # Increment ref_count when storing caller_frame
  if saved_frame != nil:
    saved_frame.ref_count.inc()
  new_frame.caller_frame = saved_frame  # Set the caller frame so return works
  new_frame.caller_address = Address(cu: saved_cu, pc: saved_pc)
  # Mark this frame as coming from exec_function
  new_frame.from_exec_function = true

  # OPTIMIZATION: Direct argument processing for exec_function
  if not f.matcher.is_empty():
    if args.len == 0:
      process_args_zero(f.matcher, scope, callable_argument_guard_context())
    elif args.len == 1:
      process_args_one(f.matcher, args[0], scope, callable_argument_guard_context())
    else:
      process_args_direct(f.matcher, cast[ptr UncheckedArray[Value]](args[0].addr), args.len, false, scope, callable_argument_guard_context())

  # Set frame.args so IkSelf can access arguments (especially self in methods)
  let args_gene = new_gene_value()
  for arg in args:
    args_gene.gene.children.add(arg)
  new_frame.args = args_gene

  # Set up VM for function execution
  self.frame = new_frame
  self.cu = f.body_compiled
  self.pc = 0

  # Execute the function
  # exec_continue will run until the function returns or completes
  # The return instruction or IkEnd will detect from_exec_function and stop exec
  let result = self.exec_continue()

  # The VM state should already be restored by return or IkEnd
  return result

proc exec_function_kw*(self: ptr VirtualMachine, fn: Value, args: seq[Value],
                       kw_pairs: seq[(Key, Value)]): Value {.exportc.} =
  ## Execute a standalone Gene function with keyword arguments.
  ## Mirrors exec_method_kw_impl without injecting a synthetic self argument.
  if fn.kind != VkFunction:
    return NIL

  let f = fn.ref.fn
  if f.body_compiled == nil:
    f.compile()

  let saved_cu = self.cu
  let saved_pc = self.pc
  let saved_frame = self.frame

  var scope: Scope
  if f.matcher.is_empty():
    scope = f.parent_scope
    if scope != nil:
      scope.ref_count.inc()
  else:
    scope = new_scope(f.scope_tracker, f.parent_scope)
    let args_ptr =
      if args.len > 0:
        cast[ptr UncheckedArray[Value]](args[0].addr)
      else:
        cast[ptr UncheckedArray[Value]](nil)
    process_args_direct_kw(f.matcher, args_ptr, args.len, kw_pairs, scope, callable_argument_guard_context())

  let new_frame = new_frame()
  new_frame.kind = FkFunction
  new_frame.target = fn
  new_frame.scope = scope
  new_frame.ns = f.ns
  if saved_frame != nil:
    saved_frame.ref_count.inc()
  new_frame.caller_frame = saved_frame
  new_frame.caller_address = Address(cu: saved_cu, pc: saved_pc)
  new_frame.from_exec_function = true

  let args_gene = new_gene_value()
  for arg in args:
    args_gene.gene.children.add(arg)
  new_frame.args = args_gene

  self.frame = new_frame
  self.cu = f.body_compiled
  self.pc = 0

  let result = self.exec_continue()
  return result

proc exec_method_impl(self: ptr VirtualMachine, fn: Value, instance: Value, args: seq[Value],
                      caller_context: Frame): Value =
  ## Execute a Gene method with given instance (self) and arguments.
  ## This properly sets up a method frame with self bound in scope.
  if fn.kind != VkFunction:
    return NIL

  let f = fn.ref.fn

  # Compile if needed
  if f.body_compiled == nil:
    f.compile()

  # Save VM state
  let saved_cu = self.cu
  let saved_pc = self.pc
  let saved_frame = self.frame

  # Create a new scope for the method
  var scope: Scope
  if f.matcher.is_empty():
    scope = f.parent_scope
    if scope != nil:
      scope.ref_count.inc()
  else:
    scope = new_scope(f.scope_tracker, f.parent_scope)
    var all_args = newSeq[Value](args.len + 1)
    all_args[0] = instance
    for i, arg in args:
      all_args[i + 1] = arg
    process_args_direct(f.matcher, cast[ptr UncheckedArray[Value]](all_args[0].addr), all_args.len, false, scope, callable_argument_guard_context())

  # Create a new frame for the method
  let new_frame = new_frame()
  new_frame.kind = if f.is_macro_like: FkMacroMethod else: FkMethod
  new_frame.target = fn
  new_frame.scope = scope
  new_frame.ns = f.ns
  if f.is_macro_like:
    let ctx = if caller_context != nil: caller_context else: saved_frame
    if ctx != nil:
      new_frame.caller_context = ctx
  if saved_frame != nil:
    saved_frame.ref_count.inc()
  new_frame.caller_frame = saved_frame
  new_frame.caller_address = Address(cu: saved_cu, pc: saved_pc)
  new_frame.from_exec_function = true

  # Set frame.args so IkSelf can access arguments (especially self in methods)
  let args_gene = new_gene_value()
  args_gene.gene.children.add(instance)
  for arg in args:
    args_gene.gene.children.add(arg)
  new_frame.args = args_gene

  # Set up VM for method execution
  self.frame = new_frame
  self.cu = f.body_compiled
  self.pc = 0

  # Execute the method
  let result = self.exec_continue()

  return result

proc exec_method*(self: ptr VirtualMachine, fn: Value, instance: Value, args: seq[Value]): Value {.exportc.} =
  return self.exec_method_impl(fn, instance, args, self.frame)

proc exec_method_kw_impl(self: ptr VirtualMachine, fn: Value, instance: Value, args: seq[Value],
                         kw_pairs: seq[(Key, Value)], caller_context: Frame): Value =
  ## Execute a Gene method with keyword arguments.
  if fn.kind != VkFunction:
    return NIL

  let f = fn.ref.fn
  if f.body_compiled == nil:
    f.compile()

  let saved_cu = self.cu
  let saved_pc = self.pc
  let saved_frame = self.frame

  var scope: Scope
  if f.matcher.is_empty():
    scope = f.parent_scope
    if scope != nil:
      scope.ref_count.inc()
  else:
    scope = new_scope(f.scope_tracker, f.parent_scope)

  var all_args = newSeq[Value](args.len + 1)
  all_args[0] = instance
  for i, arg in args:
    all_args[i + 1] = arg

  if not f.matcher.is_empty():
    let args_ptr = cast[ptr UncheckedArray[Value]](all_args[0].addr)
    process_args_direct_kw(f.matcher, args_ptr, all_args.len, kw_pairs, scope, callable_argument_guard_context())

  let new_frame = new_frame()
  new_frame.kind = if f.is_macro_like: FkMacroMethod else: FkMethod
  new_frame.target = fn
  new_frame.scope = scope
  new_frame.ns = f.ns
  if f.is_macro_like:
    let ctx = if caller_context != nil: caller_context else: saved_frame
    if ctx != nil:
      new_frame.caller_context = ctx
  if saved_frame != nil:
    saved_frame.ref_count.inc()
  new_frame.caller_frame = saved_frame
  new_frame.caller_address = Address(cu: saved_cu, pc: saved_pc)
  new_frame.from_exec_function = true

  let args_gene = new_gene_value()
  args_gene.gene.children.add(instance)
  for arg in args:
    args_gene.gene.children.add(arg)
  new_frame.args = args_gene

  self.frame = new_frame
  self.cu = f.body_compiled
  self.pc = 0

  let result = self.exec_continue()
  return result

proc exec_method_kw*(self: ptr VirtualMachine, fn: Value, instance: Value, args: seq[Value],
                     kw_pairs: seq[(Key, Value)]): Value {.exportc.} =
  return self.exec_method_kw_impl(fn, instance, args, kw_pairs, self.frame)

proc fn_proxy_param_name(proxy: FnProxy, index: int): string {.inline.} =
  if proxy != nil and index >= 0 and index < proxy.param_names.len and
      proxy.param_names[index].len > 0:
    return proxy.param_names[index]
  "argument " & $(index + 1)

proc fn_proxy_guard_context(proxy: FnProxy, phase: GuardPhase,
                            party: GuardParty): GuardContext {.inline.} =
  GuardContext(
    enabled: true,
    phase: phase,
    party: party,
    producer: if phase == GpReturn: "fn-proxy-target" else: "caller",
    consumer: if phase == GpReturn: "caller" else: "fn-proxy",
    site: if proxy == nil: "" else: proxy.site)

proc validate_fn_proxy_value(self: ptr VirtualMachine, proxy: FnProxy, value: Value,
                             type_id: TypeId, param_name: string,
                             context: GuardContext): Value {.inline.} =
  result = value
  if proxy == nil or type_id == NO_TYPE_ID or type_id == BUILTIN_TYPE_ANY_ID:
    return
  if value == NIL and not self.strict_nil:
    return
  validate_type(value, type_id, proxy.type_descriptors, param_name,
    self.runtime_type_error_location(), strict_nil = self.strict_nil,
    context = context)

proc fn_proxy_suffix_positional(params: seq[CallableParamDesc], start: int): int {.inline.} =
  for i in start..<params.len:
    if params[i].kind == CpkPositional:
      result.inc()

proc fn_proxy_keyword_name(key: Key): string {.inline.} =
  get_symbol(symbol_index(key))

proc fn_proxy_keyword_index(kw_pairs: seq[(Key, Value)], key: Key): int {.inline.} =
  result = -1
  for i, pair in kw_pairs:
    if pair[0] == key:
      result = i

proc fn_proxy_mark_keyword_used(used: var seq[int], index: int) {.inline.} =
  if index >= 0 and index notin used:
    used.add(index)

proc validate_fn_proxy_args(self: ptr VirtualMachine, proxy: FnProxy,
                            args: seq[Value],
                            kw_pairs: seq[(Key, Value)] = @[]): tuple[
                              positional: seq[Value],
                              keywords: seq[(Key, Value)]] =
  if proxy == nil:
    result.positional = args
    result.keywords = kw_pairs
    return
  result.positional = @[]
  result.keywords = kw_pairs
  let context = fn_proxy_guard_context(proxy, GpArgument, BpNegative)
  var pos_index = 0
  var used_keyword_indices: seq[int] = @[]
  var has_keyword_rest = false
  for param_index, param in proxy.params:
    case param.kind
    of CpkPositional:
      if pos_index >= args.len:
        not_allowed("Fn proxy expected " & $(pos_index + 1) & " arguments, got " & $args.len)
      result.positional.add(self.validate_fn_proxy_value(proxy, args[pos_index], param.type_id,
        fn_proxy_param_name(proxy, param_index), context))
      pos_index.inc()
    of CpkPositionalRest:
      let suffix_slots = fn_proxy_suffix_positional(proxy.params, param_index + 1)
      var rest_count = args.len - pos_index - suffix_slots
      if rest_count < 0:
        rest_count = 0
      while rest_count > 0:
        result.positional.add(self.validate_fn_proxy_value(proxy, args[pos_index], param.type_id,
          fn_proxy_param_name(proxy, param_index), context))
        pos_index.inc()
        rest_count.dec()
    of CpkKeyword:
      let key = param.keyword_name.to_key()
      let kw_index = fn_proxy_keyword_index(kw_pairs, key)
      if kw_index < 0:
        not_allowed("Fn proxy missing keyword argument: " & param.keyword_name)
      let checked = self.validate_fn_proxy_value(proxy, kw_pairs[kw_index][1],
        param.type_id, param.keyword_name, context)
      result.keywords[kw_index] = (kw_pairs[kw_index][0], checked)
      fn_proxy_mark_keyword_used(used_keyword_indices, kw_index)
    of CpkKeywordRest:
      has_keyword_rest = true
      for kw_index, pair in kw_pairs:
        if kw_index in used_keyword_indices:
          continue
        let checked = self.validate_fn_proxy_value(proxy, pair[1],
          param.type_id, "keyword argument", context)
        result.keywords[kw_index] = (pair[0], checked)
        fn_proxy_mark_keyword_used(used_keyword_indices, kw_index)
  if pos_index < args.len:
    not_allowed("Fn proxy expected " & $pos_index & " arguments, got " & $args.len)
  if not has_keyword_rest:
    for kw_index, pair in kw_pairs:
      if kw_index notin used_keyword_indices:
        not_allowed("Fn proxy unexpected keyword argument: " &
          fn_proxy_keyword_name(pair[0]))

proc exec_fn_proxy(self: ptr VirtualMachine, callable: Value, args: seq[Value],
                   self_value: Value = NIL, with_self = false,
                   kw_pairs: seq[(Key, Value)] = @[]): Value =
  if callable.ref == nil or callable.ref.fn_proxy == nil:
    not_allowed("Fn proxy is missing target")
  let proxy = callable.ref.fn_proxy
  let checked = self.validate_fn_proxy_args(proxy, args, kw_pairs)
  if checked.keywords.len > 0:
    case proxy.target.kind
    of VkFnProxy:
      result = self.exec_fn_proxy(proxy.target, checked.positional,
        kw_pairs = checked.keywords)
    of VkFunction:
      if with_self:
        not_allowed("Fn proxy keyword calls with self are not supported")
      result = self.exec_function_kw(proxy.target, checked.positional, checked.keywords)
    of VkNativeFn, VkNativeMethod:
      var native_args = newSeq[Value](checked.positional.len + 1)
      let kw_map = new_map_value()
      for (k, v) in checked.keywords:
        map_data(kw_map)[k] = v
      native_args[0] = kw_map
      for i, arg in checked.positional:
        native_args[i + 1] = arg
      if proxy.target.kind == VkNativeFn:
        result = call_native_value(proxy.target, self, native_args, true)
      else:
        let fn = proxy.target.ref.native_method
        result = call_native_fn(fn, self, native_args, true)
    of VkBoundMethod:
      result = self.call_bound_method(proxy.target, checked.positional, checked.keywords)
    else:
      not_allowed("Fn proxy target does not support keyword calls")
  elif with_self:
    result = self.exec_callable_with_self(proxy.target, self_value, checked.positional)
  else:
    result = self.exec_callable(proxy.target, checked.positional)
  let context = fn_proxy_guard_context(proxy, GpReturn, BpPositive)
  result = self.validate_fn_proxy_value(proxy, result, proxy.return_type_id,
    "return value of fn proxy", context)

proc exec_callable*(self: ptr VirtualMachine, callable: Value, args: seq[Value]): Value {.exportc.} =
  ## Execute a callable from native code while preserving VM state.
  ## This is safe to call from native functions/methods that need to invoke Gene callables.
  case callable.kind:
  of VkFnProxy:
    return self.exec_fn_proxy(callable, args)
  of VkFunction:
    return self.exec_function(callable, args)
  of VkNativeFn:
    return call_native_value(callable, self, args)
  of VkNativeMethod:
    return call_native_fn(callable.ref.native_method, self, args)
  of VkBoundMethod:
    let bm = callable.ref.bound_method
    return self.exec_callable(bm.`method`.callable, @[bm.self] & args)
  of VkInterface:
    # Calling an interface creates an adapter
    if args.len < 1:
      raise new_exception(types.Exception, "Interface call requires at least 1 argument (the object to adapt)")
    let ctor_args = if args.len > 1: args[1..^1] else: @[]
    # Push interface and arg to frame stack and call exec_adapter
    self.frame.push(callable)
    self.frame.push(args[0])
    exec_adapter(self, ctor_args)
    return self.frame.pop()
  of VkBlock:
    let blk = callable.ref.block
    if blk.body_compiled == nil:
      blk.compile()

    let saved_cu = self.cu
    let saved_pc = self.pc
    let saved_frame = self.frame

    var scope: Scope
    if blk.matcher.is_empty():
      scope = blk.frame.scope
      if scope != nil:
        scope.ref_count.inc()
    else:
      scope = new_scope(blk.scope_tracker, blk.frame.scope)

    let new_frame = new_frame()
    new_frame.kind = FkBlock
    new_frame.target = callable
    new_frame.scope = scope
    new_frame.ns = blk.ns
    if saved_frame != nil:
      saved_frame.ref_count.inc()
    new_frame.caller_frame = saved_frame
    new_frame.caller_address = Address(cu: saved_cu, pc: saved_pc)
    new_frame.from_exec_function = true

    var args_gene = new_gene_value()
    for arg in args:
      args_gene.gene.children.add(arg)
    new_frame.args = args_gene

    if not blk.matcher.is_empty():
      # Blocks are callable values but not S02 typed Function boundaries; keep legacy no-context diagnostics.
      process_args(blk.matcher, args_gene, new_frame.scope)

    self.frame = new_frame
    self.cu = blk.body_compiled
    self.pc = 0
    return self.exec_continue()
  else:
    not_allowed("Value is not callable: " & $callable.kind)

proc exec_function_with_self*(self: ptr VirtualMachine, fn: Value, self_value: Value, args: seq[Value]): Value =
  ## Like exec_function but sets self_value as self (for IkSelf) without passing it to the matcher.
  if fn.kind != VkFunction:
    return NIL

  let f = fn.ref.fn

  if f.body_compiled == nil:
    f.compile()

  let saved_cu = self.cu
  let saved_pc = self.pc
  let saved_frame = self.frame

  var scope: Scope
  if f.matcher.is_empty():
    scope = f.parent_scope
    if scope != nil:
      scope.ref_count.inc()
  else:
    scope = new_scope(f.scope_tracker, f.parent_scope)
    # Only pass actual args to the matcher (NOT self_value)
    if args.len == 0:
      process_args_zero(f.matcher, scope, callable_argument_guard_context())
    elif args.len == 1:
      process_args_one(f.matcher, args[0], scope, callable_argument_guard_context())
    else:
      process_args_direct(f.matcher, cast[ptr UncheckedArray[Value]](args[0].addr), args.len, false, scope, callable_argument_guard_context())

  let new_frame = new_frame()
  new_frame.kind = FkFunction
  new_frame.target = fn
  new_frame.scope = scope
  new_frame.ns = f.ns
  if saved_frame != nil:
    saved_frame.ref_count.inc()
  new_frame.caller_frame = saved_frame
  new_frame.caller_address = Address(cu: saved_cu, pc: saved_pc)
  new_frame.from_exec_function = true

  # Set frame.args with self_value as first child (for IkSelf), then actual args
  let args_gene = new_gene_value()
  args_gene.gene.children.add(self_value)
  for arg in args:
    args_gene.gene.children.add(arg)
  new_frame.args = args_gene

  self.frame = new_frame
  self.cu = f.body_compiled
  self.pc = 0
  return self.exec_continue()

proc exec_callable_with_self*(self: ptr VirtualMachine, callable: Value, self_value: Value, args: seq[Value]): Value {.exportc.} =
  ## Like exec_callable but sets self_value for IkSelf without passing it to the matcher.
  case callable.kind:
  of VkFnProxy:
    return self.exec_fn_proxy(callable, args, self_value, with_self = true)
  of VkFunction:
    return self.exec_function_with_self(callable, self_value, args)
  of VkNativeFn:
    # Native functions don't use IkSelf, pass args as-is
    return call_native_value(callable, self, args)
  of VkBlock:
    let blk = callable.ref.block
    if blk.body_compiled == nil:
      blk.compile()

    let saved_cu = self.cu
    let saved_pc = self.pc
    let saved_frame = self.frame

    var scope: Scope
    if blk.matcher.is_empty():
      scope = blk.frame.scope
      if scope != nil:
        scope.ref_count.inc()
    else:
      scope = new_scope(blk.scope_tracker, blk.frame.scope)

    let new_frame = new_frame()
    new_frame.kind = FkBlock
    new_frame.target = callable
    new_frame.scope = scope
    new_frame.ns = blk.ns
    if saved_frame != nil:
      saved_frame.ref_count.inc()
    new_frame.caller_frame = saved_frame
    new_frame.caller_address = Address(cu: saved_cu, pc: saved_pc)
    new_frame.from_exec_function = true

    var args_gene = new_gene_value()
    args_gene.gene.children.add(self_value)
    for arg in args:
      args_gene.gene.children.add(arg)
    new_frame.args = args_gene

    if not blk.matcher.is_empty():
      # Blocks remain no-context for S02; only pass actual args (not self) to matcher.
      var matcher_args = new_gene_value()
      for arg in args:
        matcher_args.gene.children.add(arg)
      # Blocks remain no-context for S02; this matcher is not a typed Function boundary.
      process_args(blk.matcher, matcher_args, new_frame.scope)

    self.frame = new_frame
    self.cu = blk.body_compiled
    self.pc = 0
    return self.exec_continue()
  else:
    # Fall back to regular callable
    return self.exec_callable(callable, args)

proc exec_generator_impl*(self: ptr VirtualMachine, gen: GeneratorObj): Value {.exportc.} =
  # Check for nil generator
  if gen == nil:
    raise new_exception(types.Exception, "exec_generator_impl: generator is nil")

  # Check for nil function
  if gen.function == nil:
    raise new_exception(types.Exception, "exec_generator_impl: generator function is nil")


  # If generator hasn't started, initialize it
  if gen.state == GsPending:
    # Compile the function if needed
    if gen.function.body_compiled == nil:
      gen.function.compile()

    # Save the compilation unit
    gen.cu = gen.function.body_compiled

    # Create a new frame for the generator
    gen.frame = new_frame()
    gen.frame.kind = FkFunction
    let fn_ref = new_ref(VkFunction)
    fn_ref.fn = gen.function
    gen.frame.target = fn_ref.to_ref_value()

    # Create scope for the generator
    var scope: Scope
    if gen.function.matcher.is_empty():
      scope = gen.function.parent_scope
      if scope != nil:
        scope.ref_count.inc()
    else:
      scope = new_scope(gen.function.scope_tracker, gen.function.parent_scope)
    gen.frame.scope = scope
    gen.frame.ns = gen.function.ns

    # Process arguments if any
    if gen.stack.len > 0:
      let args_gene = new_gene(NIL)
      for arg in gen.stack:
        args_gene.children.add(arg)
      gen.frame.args = args_gene.to_gene_value()

      # Process arguments through matcher if needed
      if not gen.function.matcher.is_empty():
        process_args(gen.function.matcher, args_gene.to_gene_value(), scope, callable_argument_guard_context())

    # Initialize execution state
    gen.pc = 0
    gen.state = GsRunning

  # Check if generator is done
  if gen.done:
    return NOT_FOUND

  # Save current VM state
  let saved_cu = self.cu
  let saved_pc = self.pc
  let saved_frame = self.frame
  let saved_exception_handlers = self.exception_handlers

  # Set up generator execution context
  self.cu = gen.cu  # Use saved compilation unit
  self.pc = gen.pc
  self.frame = gen.frame
  self.exception_handlers = @[]  # Clear exception handlers for generator

  # Mark that we're in a generator
  self.frame.is_generator = true

  # Store the generator in the VM so IkYield can access it
  self.current_generator = gen

  # Execute using exec_continue which doesn't reset PC
  # The exec loop will handle IkYield specially when is_generator is true
  var result = self.exec_continue()

  # Check if generator yielded (IkYield will return a value) or completed
  # The IkYield handler already saved the state, we just need to check if done
  # Check if we hit the end of the generator function
  # After IkEnd returns, PC would be at or past the last instruction
  # Also check if the last executed instruction was IkEnd
  var is_complete = false


  if self.pc >= self.cu.instructions.len:
    is_complete = true
  elif self.pc < self.cu.instructions.len and self.cu.instructions[self.pc].kind == IkEnd:
    # IkEnd just executed (PC points to it after it returns)
    is_complete = true

  if is_complete:
    # Generator completed - don't yield the return value
    gen.done = true
    gen.state = GsDone
    result = NOT_FOUND  # Return NOT_FOUND for completed generators
  else:
    # Generator yielded a value via IkYield
    gen.state = GsRunning

  # Restore original VM state
  self.cu = saved_cu
  self.pc = saved_pc
  self.frame = saved_frame
  self.exception_handlers = saved_exception_handlers
  self.current_generator = nil

  return result
