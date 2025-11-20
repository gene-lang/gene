#################### Collections #################

proc compile_array(self: Compiler, input: Value) =
  # Use call base approach: push base, compile elements onto stack, collect at end
  self.emit(Instruction(kind: IkArrayStart))

  var i = 0
  let arr = input.ref.arr
  while i < arr.len:
    let child = arr[i]

    # Check for standalone postfix spread: expr ...
    if i + 1 < arr.len and arr[i + 1].kind == VkSymbol and arr[i + 1].str == "...":
      # Compile the expression and spread its elements
      self.compile(child)
      self.emit(Instruction(kind: IkArrayAddSpread))
      i += 2  # Skip both the expr and the ... symbol
      continue

    # Check for suffix spread: a...
    if child.kind == VkSymbol and child.str.endsWith("...") and child.str.len > 3:
      # Compile the base symbol and spread its elements
      let base_symbol = child.str[0..^4].to_symbol_value()  # Remove "..."
      self.compile(base_symbol)
      self.emit(Instruction(kind: IkArrayAddSpread))
      i += 1
      continue

    # Normal element - just compile it (pushes to stack)
    self.compile(child)
    i += 1

  # Collect all elements from call base into array
  self.emit(Instruction(kind: IkArrayEnd))

proc compile_stream(self: Compiler, input: Value) =
  # Build a VkStream literal on the stack, supporting spreads just like arrays.
  self.emit(Instruction(kind: IkStreamStart))

  var i = 0
  let stream_values = input.ref.stream
  while i < stream_values.len:
    let child = stream_values[i]

    # Standalone postfix spread: expr ...
    if i + 1 < stream_values.len and stream_values[i + 1].kind == VkSymbol and stream_values[i + 1].str == "...":
      self.compile(child)
      self.emit(Instruction(kind: IkStreamAddSpread))
      i += 2
      continue

    # Suffix spread attached to a symbol: foo...
    if child.kind == VkSymbol and child.str.endsWith("...") and child.str.len > 3:
      let base_symbol = child.str[0..^4].to_symbol_value()
      self.compile(base_symbol)
      self.emit(Instruction(kind: IkStreamAddSpread))
      i.inc()
      continue

    self.compile(child)
    i.inc()

  self.emit(Instruction(kind: IkStreamEnd))

proc compile_stream_block(self: Compiler, input: Value) =
  ## Compile a stream as a sequence of expressions (used for control-flow bodies).
  let stream_values = input.ref.stream
  if stream_values.len == 0:
    self.emit(Instruction(kind: IkPushValue, arg0: NIL))
    return

  for i, child in stream_values:
    let old_tail = self.tail_position
    if i < stream_values.len - 1:
      self.tail_position = false
    self.compile(child)
    self.tail_position = old_tail
    if i < stream_values.len - 1:
      self.emit(Instruction(kind: IkPop))

proc compile_branch_value(self: Compiler, branch: Value) =
  ## Compile a branch-like value, treating streams as blocks instead of literals.
  let old_tail = self.tail_position
  if branch.kind == VkStream:
    self.compile_stream_block(branch)
  else:
    self.compile(branch)
  self.tail_position = old_tail

proc compile_map(self: Compiler, input: Value) =
  self.emit(Instruction(kind: IkMapStart))
  for k, v in input.ref.map:
    let key_str = $k
    # Check for spread key: ^..., ^...1, ^...2, etc.
    if key_str.startsWith("..."):
      # Spread map into current map
      self.compile(v)
      self.emit(Instruction(kind: IkMapSpread))
    else:
      # Normal key-value pair
      self.compile(v)
      self.emit(Instruction(kind: IkMapSetProp, arg0: k))
  self.emit(Instruction(kind: IkMapEnd))
