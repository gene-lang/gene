## Module helpers: ensure_namespace_path, namespace_from_value,
## run_module_init, maybe_run_module_init.
## Included from vm.nim — shares its scope.

proc ensure_namespace_path(root: Namespace, parts: seq[string], uptoExclusive: int): Namespace =
  ## Ensure that the namespace path exists (creating as needed) and return the target namespace.
  if root.is_nil:
    not_allowed("Cannot define class without an active namespace")
  var current = root
  for i in 0..<uptoExclusive:
    let key = parts[i].to_key()
    var value = if current.members.hasKey(key): current.members[key] else: NIL
    if value == NIL or value.kind != VkNamespace:
      let new_ns = new_namespace(current, parts[i])
      value = new_ns.to_value()
      current.members[key] = value
    current = value.ref.ns
  result = current

proc namespace_from_value(container: Value): Namespace =
  case container.kind
  of VkNamespace:
    result = container.ref.ns
  of VkClass:
    result = container.ref.class.ns
  else:
    not_allowed("Class container must be a namespace or class, got " & $container.kind)

proc init_module_namespace(module_ns: Namespace, module_path: string, compiled = false) =
  if module_ns == nil:
    return
  module_ns.members["__is_main__".to_key()] = FALSE
  module_ns.members["__module_name__".to_key()] = module_path.to_value()
  module_ns.members["gene".to_key()] = App.app.gene_ns
  module_ns.members["genex".to_key()] = App.app.genex_ns
  if compiled:
    module_ns.members["__compiled__".to_key()] = TRUE
  bind_module_package_context(module_ns, module_path)

proc ensure_runtime_module_loaded*(self: ptr VirtualMachine, module_path: string,
                                   prepared_ns: Namespace = nil,
                                   is_native = false): Namespace =
  if module_path.len == 0:
    return nil

  if self != nil and self.frame != nil and self.frame.ns != nil:
    let module_name = self.frame.ns.members.getOrDefault("__module_name__".to_key(), NIL)
    if module_name.kind in {VkString, VkSymbol} and module_name.str == module_path:
      tag_namespace_serialization_origins(self.frame.ns, module_path)
      return self.frame.ns

  if ModuleCache.hasKey(module_path):
    let cached = ModuleCache[module_path]
    tag_namespace_serialization_origins(cached, module_path)
    return cached

  if is_native:
    when not defined(noExtensions):
      let ext_ns = load_extension(self, module_path)
      if ext_ns == nil:
        not_allowed("[GENE.EXT.INIT_FAILED] Extension did not publish namespace: " & module_path)
      ModuleCache[module_path] = ext_ns
      tag_namespace_serialization_origins(ext_ns, module_path)
      return ext_ns
    else:
      not_allowed("Native extensions are not supported in this build")

  if ModuleLoadState.getOrDefault(module_path, false):
    var cycle: seq[string] = @[]
    var start = -1
    for i, entry in ModuleLoadStack:
      if entry == module_path:
        start = i
        break
    if start >= 0:
      cycle = ModuleLoadStack[start..^1] & @[module_path]
    else:
      cycle = ModuleLoadStack & @[module_path]
    not_allowed("[GENE.MODULE.CYCLE] Cyclic import detected: " & cycle.join(" -> "))

  let module_ns =
    if prepared_ns != nil:
      prepared_ns
    else:
      let created = new_namespace(App.app.global_ns.ref.ns, module_path)
      init_module_namespace(created, module_path, module_path.endsWith(".gir"))
      created

  ModuleLoadState[module_path] = true
  ModuleLoadStack.add(module_path)
  let saved_cu = self.cu
  let saved_frame = self.frame
  let saved_pc = self.pc
  var vm_state_switched = false
  try:
    let cu = compile_module(module_path)

    self.frame = new_frame()
    self.frame.ns = module_ns
    let args_gene = new_gene(NIL)
    args_gene.children.add(module_ns.to_value())
    self.frame.args = args_gene.to_gene_value()
    vm_state_switched = true

    self.cu = cu
    discard self.exec()
    discard self.run_module_init(module_ns)

    ModuleCache[module_path] = module_ns
    tag_namespace_serialization_origins(module_ns, module_path)
    return module_ns
  finally:
    if vm_state_switched:
      self.cu = saved_cu
      self.frame = saved_frame
      self.pc = saved_pc
    if ModuleLoadState.hasKey(module_path):
      ModuleLoadState.del(module_path)
    if ModuleLoadStack.len > 0 and ModuleLoadStack[^1] == module_path:
      ModuleLoadStack.setLen(ModuleLoadStack.len - 1)

proc run_module_init*(self: ptr VirtualMachine, module_ns: Namespace): tuple[ran: bool, value: Value] =
  if module_ns == nil:
    return (false, NIL)
  let ran_key = "__init_ran__".to_key()
  if module_ns.members.getOrDefault(ran_key, FALSE) == TRUE:
    return (false, NIL)
  let init_key = "__init__".to_key()
  if not module_ns.members.hasKey(init_key):
    return (false, NIL)
  let init_val = module_ns.members[init_key]
  if init_val == NIL:
    return (false, NIL)
  module_ns.members[ran_key] = TRUE

  let saved_frame = self.frame
  var frame_changed = false
  if saved_frame == nil or saved_frame.ns != module_ns:
    self.frame = new_frame(module_ns)
    frame_changed = true

  var result: Value = NIL
  let module_scope =
    if saved_frame != nil and saved_frame.ns == module_ns: saved_frame.scope else: nil

  if init_val.kind == VkFunction and module_scope != nil:
    let f = init_val.ref.fn
    if f.body_compiled == nil:
      f.compile()

    # Save current VM state
    let saved_cu = self.cu
    let saved_pc = self.pc
    let saved_frame2 = self.frame

    # Reuse module scope for init so module vars live at module scope
    module_scope.ref_count.inc()

    let args = @[module_ns.to_value()]
    if not f.matcher.is_empty():
      if args.len == 0:
        process_args_zero(f.matcher, module_scope)
      elif args.len == 1:
        process_args_one(f.matcher, args[0], module_scope)
      else:
        process_args_direct(f.matcher, cast[ptr UncheckedArray[Value]](args[0].addr), args.len, false, module_scope)

    let new_frame = new_frame()
    new_frame.kind = FkFunction
    new_frame.target = init_val
    new_frame.scope = module_scope
    new_frame.ns = f.ns
    if saved_frame2 != nil:
      saved_frame2.ref_count.inc()
    new_frame.caller_frame = saved_frame2
    new_frame.caller_address = Address(cu: saved_cu, pc: saved_pc)
    new_frame.from_exec_function = true

    let args_gene = new_gene_value()
    args_gene.gene.children.add(args[0])
    new_frame.args = args_gene

    self.frame = new_frame
    self.cu = f.body_compiled
    self.pc = 0
    result = self.exec_continue()
  else:
    result = self.exec_callable(init_val, @[module_ns.to_value()])
  if frame_changed:
    self.frame = saved_frame
  return (true, result)

proc maybe_run_module_init*(self: ptr VirtualMachine): tuple[ran: bool, value: Value] =
  if self.frame == nil or self.frame.ns == nil:
    return (false, NIL)
  let ns = self.frame.ns
  let main_key = "__is_main__".to_key()
  if ns.members.getOrDefault(main_key, FALSE) != TRUE:
    return (false, NIL)
  let init_result = self.run_module_init(ns)
  if init_result.ran:
    self.drain_pending_futures()
  return init_result
