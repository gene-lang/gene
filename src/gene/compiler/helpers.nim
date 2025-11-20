#################### Container Helpers #################

proc container_key(): Key {.inline.} =
  "container".to_key()

proc build_container_value(parts: seq[string]): Value =
  if parts.len == 0:
    return NIL
  if parts.len == 1:
    return parts[0].to_symbol_value()
  parts.to_complex_symbol()

proc split_container_name(name: Value): tuple[base: Value, container: Value] =
  result.base = name
  result.container = NIL

  proc normalize_prefix(prefix: seq[string]): seq[string] =
    result = @[]
    if prefix.len == 0:
      return
    result = prefix
    if result.len > 0 and result[0].len == 0:
      result[0] = "self"

  case name.kind
  of VkComplexSymbol:
    let cs = name.ref.csymbol
    if cs.len < 2:
      return
    if cs[0] == "$ns":
      return
    let prefix = cs[0..^2]
    if prefix.len == 0:
      return
    let normalized = normalize_prefix(prefix)
    let container_value = build_container_value(normalized)
    if container_value == NIL:
      return
    result.base = cs[^1].to_symbol_value()
    result.container = container_value
  of VkSymbol:
    let s = name.str
    if s.contains("/") and s != "$ns":
      let parts = s.split("/")
      if parts.len < 2:
        return
      if parts[0] == "$ns":
        return
      var prefix = parts[0..^2]
      let normalized = normalize_prefix(prefix)
      let container_value = build_container_value(normalized)
      if container_value == NIL:
        return
      result.base = parts[^1].to_symbol_value()
      result.container = container_value
  else:
    discard

proc apply_container_to_child(gene: ptr Gene, child_index: int) =
  if gene.children.len <= child_index:
    return
  if gene.props.hasKey(container_key()):
    return
  let (base, container_value) = split_container_name(gene.children[child_index])
  if container_value == NIL:
    return
  gene.props[container_key()] = container_value
  gene.children[child_index] = base

proc apply_container_to_type(gene: ptr Gene) =
  if gene.props.hasKey(container_key()):
    return
  let (base, container_value) = split_container_name(gene.type)
  if container_value == NIL:
    return
  gene.props[container_key()] = container_value
  gene.type = base

#################### Trace Helpers #################

proc current_trace(self: Compiler): SourceTrace =
  if self.trace_stack.len == 0:
    return nil
  self.trace_stack[^1]

proc push_trace(self: Compiler, trace: SourceTrace) =
  if trace.is_nil:
    return
  self.trace_stack.add(trace)

proc pop_trace(self: Compiler) =
  if self.trace_stack.len > 0:
    self.trace_stack.setLen(self.trace_stack.len - 1)

proc emit(self: Compiler, instr: Instruction) =
  if self.output.is_nil:
    return
  self.output.add_instruction(instr, self.current_trace())

#################### Symbol and Literal Helpers #################

proc compile_literal(self: Compiler, input: Value) =
  self.emit(Instruction(kind: IkPushValue, arg0: input))

proc compile_unary_not(self: Compiler, operand: Value) {.inline.} =
  ## Emit bytecode for a logical not.
  self.compile(operand)
  self.emit(Instruction(kind: IkNot))

proc compile_var_op_literal(self: Compiler, symbolVal: Value, literal: Value, opKind: InstructionKind): bool =
  ## Emit optimized instruction when a variable is operated with a literal.
  if symbolVal.kind != VkSymbol or not literal.is_literal():
    return false

  let key = symbolVal.str.to_key()
  let found = self.scope_tracker.locate(key)
  if found.local_index >= 0:
    self.emit(Instruction(
      kind: opKind,
      arg0: found.local_index.to_value(),
      arg1: found.parent_index.int32
    ))
    self.emit(Instruction(kind: IkData, arg0: literal))
    return true
  false

# Translate $x to gene/x and $x/y to gene/x/y
proc translate_symbol(input: Value): Value =
  case input.kind:
    of VkSymbol:
      let s = input.str
      if s.starts_with("$") and s.len > 1:
        # Special case for $ns - translate to special symbol
        if s == "$ns":
          result = cast[Value](SYM_NS)
        else:
          result = @["gene", s[1..^1]].to_complex_symbol()
      else:
        result = input
    of VkComplexSymbol:
      result = input
      let r = input.ref
      if r.csymbol[0] == "":
        r.csymbol[0] = "self"
      elif r.csymbol[0].starts_with("$"):
        # Special case for $ns - translate first part to special symbol
        if r.csymbol[0] == "$ns":
          r.csymbol[0] = "SPECIAL_NS"
        else:
          r.csymbol.insert("gene", 0)
          r.csymbol[1] = r.csymbol[1][1..^1]
    else:
      not_allowed($input)

proc compile_complex_symbol(self: Compiler, input: Value) =
  if self.quote_level > 0:
    self.emit(Instruction(kind: IkPushValue, arg0: input))
    return

  let input = translate_symbol(input)
  let r = input.ref

  if r.csymbol[0] == "SPECIAL_NS":
    self.emit(Instruction(kind: IkPushValue, arg0: cast[Value](SYM_NS)))
  elif r.csymbol[0] == "self":
    self.emit(Instruction(kind: IkPushSelf))
  else:
    let key = r.csymbol[0].to_key()
    if self.scope_tracker.mappings.has_key(key):
      self.emit(Instruction(kind: IkVarResolve, arg0: self.scope_tracker.mappings[key].to_value()))
    else:
      self.emit(Instruction(kind: IkResolveSymbol, arg0: cast[Value](key)))
    for s in r.csymbol[1..^1]:
      let (is_int, i) = to_int(s)
      if is_int:
        self.emit(Instruction(kind: IkGetChild, arg0: i))
      elif s.starts_with("."):
        let method_value = s[1..^1].to_symbol_value()
        if self.method_access_mode == MamReference:
          # Preserve legacy behavior when compiling method references
          self.emit(Instruction(kind: IkResolveMethod, arg0: method_value))
        else:
          # Default: immediately invoke zero-arg method via dot notation
          self.emit(Instruction(kind: IkUnifiedMethodCall0, arg0: method_value))
      elif s == "...":
        # Spread operator in complex symbols - not yet implemented
        # This would handle cases like a/.../b but is an edge case
        # For now, just treat it as a regular member access
        not_allowed("Spread operator (...) in complex symbols not supported")
      else:
        let key = s.to_key()
        self.emit(Instruction(kind: IkGetMember, arg0: cast[Value](key)))

proc compile_symbol(self: Compiler, input: Value) =
  if self.quote_level > 0:
    self.emit(Instruction(kind: IkPushValue, arg0: input))
  else:
    let input = translate_symbol(input)
    if input.kind == VkSymbol:
      let symbol_str = input.str
      if symbol_str == "self":
        # Check if self is a local variable (in methods compiled as functions)
        let key = symbol_str.to_key()
        let found = self.scope_tracker.locate(key)
        if found.local_index >= 0:
          # self is a parameter - resolve it as a variable
          if found.parent_index == 0:
            self.emit(Instruction(kind: IkVarResolve, arg0: found.local_index.to_value()))
          else:
            self.emit(Instruction(kind: IkVarResolveInherited, arg0: found.local_index.to_value(), arg1: found.parent_index))
        else:
          # Fall back to IkPushSelf for non-method contexts
          self.emit(Instruction(kind: IkPushSelf))
        return
      elif symbol_str == "super":
        # Push runtime super proxy (handled by IkSuper at execution time)
        self.emit(Instruction(kind: IkSuper))
        return
      elif symbol_str.startsWith("@") and symbol_str.len > 1:
        # Handle @shorthand syntax: @test -> (@ "test"), @0 -> (@ 0)
        let prop_name = symbol_str[1..^1]

        var segments: seq[Value] = @[]
        for part in prop_name.split("/"):
          if part.len == 0:
            not_allowed("@ selector segment cannot be empty")
          try:
            let index = parseInt(part)
            segments.add(index.to_value())
          except ValueError:
            segments.add(part.to_value())

        if segments.len == 0:
          not_allowed("@ selector requires at least one segment")

        let selector_value = new_selector_value(segments)
        self.emit(Instruction(kind: IkPushValue, arg0: selector_value))
        return
      elif symbol_str.endsWith("..."):
        # Spread suffix like "a..." - this should be handled by compile_array/compile_gene
        # If we get here, it's being used outside of those contexts which is an error
        not_allowed("Spread operator (...) can only be used in arrays, maps, or gene expressions")

    # Default handling for symbols not caught by special cases
    let symbol_str = input.str
    let key = symbol_str.to_key()

    let found = self.scope_tracker.locate(key)
    if found.local_index >= 0:
      if found.parent_index == 0:
        self.emit(Instruction(kind: IkVarResolve, arg0: found.local_index.to_value()))
      else:
        self.emit(Instruction(kind: IkVarResolveInherited, arg0: found.local_index.to_value(), arg1: found.parent_index))
        # self.emit(Instruction(kind: IkVarResolve, arg0: symbol_str.to_key.to_value()))
    elif symbol_str == "_":
      self.emit(Instruction(kind: IkPushValue, arg0: PLACEHOLDER))
    elif key == cast[Key](SYM_CONTAINER):
      # Should be impossible, but catch for safety
      not_allowed("Direct access to container is not allowed")
    else:
      # Regular symbol resolution
      self.emit(Instruction(kind: IkResolveSymbol, arg0: cast[Value](key)))
