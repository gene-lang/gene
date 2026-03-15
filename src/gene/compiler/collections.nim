## Collection compilation: arrays, maps, streams, ranges.
## Included from compiler.nim — shares its scope (emit, compile, etc.).

proc compile_array(self: Compiler, input: Value) =
  # Use call base approach: push base, compile elements onto stack, collect at end
  self.emit(Instruction(kind: IkArrayStart))

  var i = 0
  let arr = array_data(input)
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
  self.emit(Instruction(kind: IkArrayEnd, arg1: if array_is_frozen(input): 1 else: 0))

proc compile_stream(self: Compiler, input: Value, allow_vmstmt_last = false) =
  # For simple streams (used by if/elif/else branches), just compile the children directly
  # Don't emit StreamStart/StreamEnd as they're not needed for control flow
  let stream_values = input.ref.stream

  if stream_values.len == 0:
    self.emit(Instruction(kind: IkPushValue, arg0: NIL))
    return

  var i = 0
  while i < stream_values.len:
    let child = stream_values[i]
    let old_tail = self.tail_position
    let is_last = i == stream_values.len - 1
    if is_last:
      # Last expression preserves tail position
      discard
    else:
      self.tail_position = false

    if is_vmstmt_form(child):
      if is_last and not allow_vmstmt_last:
        not_allowed("$vmstmt is statement-only")
      self.compile_vmstmt(child.gene)
    else:
      self.compile(child)

    self.tail_position = old_tail
    if i < stream_values.len - 1 and not is_vmstmt_form(child):
      self.emit(Instruction(kind: IkPop))

    i += 1

proc compile_map(self: Compiler, input: Value) =
  self.emit(Instruction(kind: IkMapStart))
  for k, v in map_data(input):
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
  self.emit(Instruction(kind: IkMapEnd, arg1: if map_is_frozen(input): 1 else: 0))

proc compile_range(self: Compiler, gene: ptr Gene) =
  # (range start end) or (range start end step)
  if gene.children.len < 2:
    not_allowed("range requires at least 2 arguments")

  self.compile(gene.children[0])  # start
  self.compile(gene.children[1])  # end

  if gene.children.len >= 3:
    self.compile(gene.children[2])  # step
  else:
    self.emit(Instruction(kind: IkPushValue, arg0: NIL))  # default step

  self.emit(Instruction(kind: IkCreateRange))

proc compile_range_operator(self: Compiler, gene: ptr Gene) =
  # (a .. b) -> (range a b)
  if gene.children.len != 2:
    not_allowed(".. operator requires exactly 2 arguments")

  self.compile(gene.children[0])  # start
  self.compile(gene.children[1])  # end
  self.emit(Instruction(kind: IkPushValue, arg0: NIL))  # default step
  self.emit(Instruction(kind: IkCreateRange))
