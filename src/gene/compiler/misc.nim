## Miscellaneous compile procs: with, tap, if_main, parse, render, emit,
## caller_eval, selector, at_selector, set, vm, vmstmt.
## Included from compiler.nim — shares its scope (emit, compile, etc.).

proc compile_vmstmt(self: Compiler, gene: ptr Gene) =
  if gene.props.len > 0:
    not_allowed("$vmstmt does not accept properties")
  if gene.children.len != 1:
    not_allowed("$vmstmt expects exactly 1 argument")
  let name_val = gene.children[0]
  if name_val.kind != VkSymbol:
    not_allowed("$vmstmt builtin name must be a symbol")
  if name_val.str != "duration_start":
    not_allowed("Unknown $vmstmt builtin: " & name_val.str)
  self.emit(Instruction(kind: IkVmDurationStart))

proc compile_vm(self: Compiler, gene: ptr Gene) =
  if gene.props.len > 0:
    not_allowed("$vm does not accept properties")
  if gene.children.len != 1:
    not_allowed("$vm expects exactly 1 argument")
  let name_val = gene.children[0]
  if name_val.kind != VkSymbol:
    not_allowed("$vm builtin name must be a symbol")
  if name_val.str != "duration":
    not_allowed("Unknown $vm builtin: " & name_val.str)
  self.emit(Instruction(kind: IkVmDuration))

proc compile_with(self: Compiler, gene: ptr Gene) =
  # ($with target body...) - evaluates body with target as self
  if gene.children.len < 1:
    not_allowed("$with expects at least 1 argument")

  # Compile the value that will become the new self
  self.compile(gene.children[0])

  # Duplicate it and save current self
  self.emit(Instruction(kind: IkDup))
  self.emit(Instruction(kind: IkSelf))
  self.emit(Instruction(kind: IkSwap))

  # Set as new self
  self.emit(Instruction(kind: IkSetSelf))

  # Compile body - return last value
  if gene.children.len > 1:
    for i in 1..<gene.children.len:
      self.compile(gene.children[i])
      if i < gene.children.len - 1:
        self.emit(Instruction(kind: IkPop))
  else:
    self.emit(Instruction(kind: IkPushNil))

  # Restore original self (which is on stack under the result)
  self.emit(Instruction(kind: IkSwap))
  self.emit(Instruction(kind: IkSetSelf))

proc compile_tap(self: Compiler, gene: ptr Gene) =
  # ($tap value body...) or ($tap value :name body...)
  if gene.children.len < 1:
    not_allowed("$tap expects at least 1 argument")

  # Compile the value
  self.compile(gene.children[0])

  # Duplicate it (one to return, one to use)
  self.emit(Instruction(kind: IkDup))

  # Check if there's a binding name
  var start_idx = 1
  var has_binding = false
  var binding_name: string

  if gene.children.len > 1 and gene.children[1].kind == VkSymbol and gene.children[1].str.starts_with(":"):
    has_binding = true
    binding_name = gene.children[1].str[1..^1]
    start_idx = 2

  # Save current self
  self.emit(Instruction(kind: IkSelf))

  # Set as new self
  self.emit(Instruction(kind: IkRotate))  # Rotate: original_self, dup_value, value -> value, original_self, dup_value
  self.emit(Instruction(kind: IkSetSelf))

  # If has binding, create a new scope and bind the value
  if has_binding:
    self.start_scope()
    let var_index = self.scope_tracker.next_index
    self.scope_tracker.mappings[binding_name.to_key()] = var_index
    self.add_scope_start()
    self.scope_tracker.next_index.inc()

    # Duplicate the value again for binding
    self.emit(Instruction(kind: IkSelf))
    self.emit(Instruction(kind: IkVar, arg0: var_index.to_value()))

  # Compile body
  if gene.children.len > start_idx:
    for i in start_idx..<gene.children.len:
      self.compile(gene.children[i])
      # Pop all but last result
      self.emit(Instruction(kind: IkPop))

  # End scope if we created one
  if has_binding:
    self.end_scope()

  # Restore original self
  self.emit(Instruction(kind: IkSwap))  # dup_value, original_self -> original_self, dup_value
  self.emit(Instruction(kind: IkSetSelf))
  # The dup_value remains on stack as the return value

proc compile_if_main(self: Compiler, gene: ptr Gene) =
  let cond_symbol = @["$ns", "__is_main__"].to_complex_symbol()

  # Compile the condition
  self.start_scope()
  self.compile(cond_symbol)
  let else_label = new_label()
  let end_label = new_label()
  self.emit(Instruction(kind: IkJumpIfFalse, arg0: else_label.to_value()))

  # Compile then branch (the children of $if_main)
  self.start_scope()
  if gene.children.len > 0:
    for i, child in gene.children:
      let old_tail = self.tail_position
      if i == gene.children.len - 1:
        # Last expression preserves tail position
        discard
      else:
        self.tail_position = false
      self.compile(child)
      self.tail_position = old_tail
      if i < gene.children.len - 1:
        self.emit(Instruction(kind: IkPop))
  else:
    self.emit(Instruction(kind: IkPushValue, arg0: NIL))
  self.end_scope()
  self.emit(Instruction(kind: IkJump, arg0: end_label.to_value()))

  # Compile else branch (nil)
  self.emit(Instruction(kind: IkNoop, label: else_label))
  self.start_scope()
  self.emit(Instruction(kind: IkPushValue, arg0: NIL))
  self.end_scope()

  self.emit(Instruction(kind: IkNoop, label: end_label))
  self.end_scope()

proc compile_parse(self: Compiler, gene: ptr Gene) =
  # ($parse string)
  if gene.children.len != 1:
    not_allowed("$parse expects exactly 1 argument")

  # Compile the string argument
  self.compile(gene.children[0])

  # Parse it
  self.emit(Instruction(kind: IkParse))

proc compile_render(self: Compiler, gene: ptr Gene) =
  # ($render template)
  if gene.children.len != 1:
    not_allowed("$render expects exactly 1 argument")

  # Compile the template argument
  self.compile(gene.children[0])

  # Render it
  self.emit(Instruction(kind: IkRender))

proc compile_emit(self: Compiler, gene: ptr Gene) =
  # ($emit value) - used within templates to emit values
  if gene.children.len < 1:
    not_allowed("$emit expects at least 1 argument")

  # For now, $emit just evaluates to its argument
  # The actual emission logic is handled by the template renderer
  if gene.children.len == 1:
    self.compile(gene.children[0])
  else:
    # Multiple arguments - create an array
    let arr_gene = new_gene("Array".to_symbol_value())
    for child in gene.children:
      arr_gene.children.add(child)
    self.compile(arr_gene.to_gene_value())

proc compile_caller_eval(self: Compiler, gene: ptr Gene) =
  # ($caller_eval expr)
  if gene.children.len != 1:
    not_allowed("$caller_eval expects exactly 1 argument")

  # Compile the expression argument (will be evaluated in macro context first)
  self.compile(gene.children[0])

  # Then evaluate the result in caller's context
  self.emit(Instruction(kind: IkCallerEval))

proc compile_selector(self: Compiler, gene: ptr Gene) =
  # (./ target property [default])
  # ({^a "A"} ./ "a") -> "A"
  # ({} ./ "a" 1) -> 1 (default value)
  if gene.children.len < 2 or gene.children.len > 3:
    not_allowed("./ expects 2 or 3 arguments")

  # Compile the target
  self.compile(gene.children[0])

  # Compile the property/index
  self.compile(gene.children[1])
  self.emit(Instruction(kind: IkValidateSelectorSegment))

  # If there's a default value, compile it
  if gene.children.len == 3:
    self.compile(gene.children[2])
    self.emit(Instruction(kind: IkGetMemberDefault))
  else:
    self.emit(Instruction(kind: IkGetMemberOrNil))

proc compile_at_selector(self: Compiler, gene: ptr Gene) =
  # (@ "property") creates a selector
  # For now, we'll implement a simplified version
  # The full implementation would create a selector object

  # Since @ is used in contexts like ((@ "test") {^test 1}),
  # and this gets compiled as a function call where (@ "test") is the function
  # and {^test 1} is the argument, we need to handle this specially

  if gene.children.len == 0:
    not_allowed("@ expects at least 1 argument for selector creation")

  var segments: seq[Value] = @[]
  var all_literal = true
  for child in gene.children:
    case child.kind
    of VkString, VkSymbol, VkInt:
      segments.add(child)
    else:
      all_literal = false

  if all_literal:
    let selector_value = new_selector_value(segments)
    self.emit(Instruction(kind: IkPushValue, arg0: selector_value))
    return

  # Dynamic selector: evaluate non-literal segments at runtime, but treat
  # string/symbol/int children as literal selector segments (not variable lookups).
  for child in gene.children:
    case child.kind
    of VkString, VkSymbol, VkInt:
      self.emit(Instruction(kind: IkPushValue, arg0: child))
    else:
      self.compile(child)

  self.emit(Instruction(kind: IkCreateSelector, arg1: gene.children.len.int32))

proc compile_set(self: Compiler, gene: ptr Gene) =
  # ($set target @property value)
  # ($set a @test 1)
  if gene.children.len != 3:
    not_allowed("$set expects exactly 3 arguments")

  # Compile the target
  self.compile(gene.children[0])

  let selector_arg = gene.children[1]
  var segments: seq[Value] = @[]
  var dynamic_selector = false
  var dynamic_expr: Value = NIL

  if selector_arg.kind == VkSymbol and selector_arg.str.startsWith("@") and selector_arg.str.len > 1:
    let prop_name = selector_arg.str[1..^1]
    for part in prop_name.split("/"):
      if part.len == 0:
        not_allowed("$set selector segment cannot be empty")
      if part == "!":
        not_allowed("$set selector cannot contain !")
      try:
        let index = parseInt(part)
        segments.add(index.to_value())
      except ValueError:
        segments.add(part.to_value())
  elif selector_arg.kind == VkGene and selector_arg.gene.type == "@".to_symbol_value():
    if selector_arg.gene.children.len == 0:
      not_allowed("$set selector requires at least one segment")
    if selector_arg.gene.children.len == 1:
      let child = selector_arg.gene.children[0]
      case child.kind
      of VkString, VkSymbol, VkInt:
        segments.add(child)
      else:
        dynamic_selector = true
        dynamic_expr = child
    else:
      for child in selector_arg.gene.children:
        case child.kind
        of VkString, VkSymbol, VkInt:
          segments.add(child)
        else:
          not_allowed("Unsupported selector segment type: " & $child.kind)
  else:
    not_allowed("$set expects a selector (@property) as second argument")

  if dynamic_selector:
    if selector_arg.gene.children.len != 1:
      not_allowed("$set selector must have exactly one dynamic segment")
  else:
    if segments.len != 1:
      not_allowed("$set selector must have exactly one property")

  if dynamic_selector:
    # Compile dynamic selector key and value
    self.compile(dynamic_expr)
    self.compile(gene.children[2])
    self.emit(Instruction(kind: IkSetMemberDynamic))
    return

  let prop = segments[0]

  # Compile the value
  self.compile(gene.children[2])

  # Check if property is an integer (for array/gene child access)
  if prop.kind == VkInt:
    # Use SetChild for integer indices
    self.emit(Instruction(kind: IkSetChild, arg0: prop))
  else:
    # Use SetMember for string/symbol properties
    let prop_key = case prop.kind:
      of VkString: prop.str.to_key()
      of VkSymbol: prop.str.to_key()
      else:
        not_allowed("Invalid property type for $set")
        "".to_key()  # Never reached, but satisfies type checker
    self.emit(Instruction(kind: IkSetMember, arg0: prop_key.to_value()))
