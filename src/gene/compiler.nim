import tables, strutils, streams

import ./types
import ./parser
import "./compiler/if"

const DEBUG = false

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

#################### Definitions #################
proc compile*(self: Compiler, input: Value)
proc compile_with(self: Compiler, gene: ptr Gene)
proc compile_tap(self: Compiler, gene: ptr Gene)
proc compile_if_main(self: Compiler, gene: ptr Gene)
proc compile_parse(self: Compiler, gene: ptr Gene)
proc compile_render(self: Compiler, gene: ptr Gene)
proc compile_emit(self: Compiler, gene: ptr Gene)
proc compile*(f: Function, eager_functions: bool)
proc compile*(b: Block, eager_functions: bool)
proc compile*(f: CompileFn, eager_functions: bool)

proc compile(self: Compiler, input: seq[Value]) =
  for i, v in input:
    # Set tail position for the last expression
    let old_tail = self.tail_position
    if i == input.len - 1:
      # Last expression inherits current tail position
      discard
    else:
      # Non-last expressions are never in tail position
      self.tail_position = false
    
    self.compile(v)
    
    # Restore tail position
    self.tail_position = old_tail
    
    if i < input.len - 1:
      self.emit(Instruction(kind: IkPop))

proc compile_literal(self: Compiler, input: Value) =
  self.emit(Instruction(kind: IkPushValue, arg0: input))

proc compile_unary_not(self: Compiler, operand: Value) {.inline.} =
  ## Emit bytecode for a logical not.
  self.compile(operand)
  self.emit(Instruction(kind: IkNot))

proc compileVarOpLiteral(self: Compiler, symbolVal: Value, literal: Value, opKind: InstructionKind): bool =
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
  else:
    let r = translate_symbol(input).ref
    if r.csymbol.len > 0 and r.csymbol[0].startsWith("@"):
      var segments: seq[Value] = @[]

      proc addSegment(part: string) =
        if part.len == 0:
          not_allowed("@ selector segment cannot be empty")
        try:
          let index = parseInt(part)
          segments.add(index.to_value())
        except ValueError:
          segments.add(part.to_value())

      addSegment(r.csymbol[0][1..^1])
      for part in r.csymbol[1..^1]:
        addSegment(part)

      if segments.len == 0:
        not_allowed("@ selector requires at least one segment")

      let selector_value = new_selector_value(segments)
      self.emit(Instruction(kind: IkPushValue, arg0: selector_value))
      return

    let key = r.csymbol[0].to_key()
    if r.csymbol[0] == "SPECIAL_NS":
      # Handle $ns/... specially
      self.emit(Instruction(kind: IkResolveSymbol, arg0: cast[Value](SYM_NS)))
    else:
      # Use locate to check parent scopes too
      let found = self.scope_tracker.locate(key)
      if found.local_index >= 0:
        if found.parent_index == 0:
          self.emit(Instruction(kind: IkVarResolve, arg0: found.local_index.to_value()))
        else:
          self.emit(Instruction(kind: IkVarResolveInherited, arg0: found.local_index.to_value(), arg1: found.parent_index))
      else:
        self.emit(Instruction(kind: IkResolveSymbol, arg0: cast[Value](key)))
    for s in r.csymbol[1..^1]:
      let (is_int, i) = to_int(s)
      if is_int:
        self.emit(Instruction(kind: IkGetChild, arg0: i))
      elif s.starts_with("."):
        # For method access, use IkResolveMethod to get the method
        # without calling it. The actual call will happen when the
        # gene is executed.
        self.emit(Instruction(kind: IkResolveMethod, arg0: s[1..^1].to_symbol_value()))
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
        # Special handling for super - will be handled differently when it's a function call
        self.emit(Instruction(kind: IkPushValue, arg0: input))
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
      let key = input.str.to_key()
      let found = self.scope_tracker.locate(key)
      if found.local_index >= 0:
        if found.parent_index == 0:
          self.emit(Instruction(kind: IkVarResolve, arg0: found.local_index.to_value()))
        else:
          self.emit(Instruction(kind: IkVarResolveInherited, arg0: found.local_index.to_value(), arg1: found.parent_index))
      else:
        self.emit(Instruction(kind: IkResolveSymbol, arg0: cast[Value](key)))
    elif input.kind == VkComplexSymbol:
      self.compile_complex_symbol(input)

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

proc compile_do(self: Compiler, gene: ptr Gene) =
  self.compile(gene.children)

proc start_scope(self: Compiler) =
  let scope_tracker = new_scope_tracker(self.scope_tracker)
  self.scope_trackers.add(scope_tracker)
  # ScopeStart is added when the first variable is declared
proc add_scope_start(self: Compiler) =
  if self.scope_tracker.next_index == 0:
    self.emit(Instruction(kind: IkScopeStart, arg0: self.scope_tracker.to_value()))
    # Mark that we added a scope start, even for empty scopes
    self.scope_tracker.scope_started = true

proc end_scope(self: Compiler) =
  # If we added a ScopeStart (either because we have variables or we explicitly marked it),
  # we need to add the corresponding ScopeEnd
  if self.scope_tracker.next_index > 0 or self.scope_tracker.scope_started:
    self.emit(Instruction(kind: IkScopeEnd))
  discard self.scope_trackers.pop()

proc compile_if(self: Compiler, gene: ptr Gene) =
  normalize_if(gene)

  self.start_scope()

  # Compile main condition
  self.compile(gene.props[COND_KEY.to_key()])
  var next_label = new_label()
  let end_label = new_label()
  self.emit(Instruction(kind: IkJumpIfFalse, arg0: next_label.to_value()))

  # Compile then branch (preserves tail position)
  self.start_scope()
  let old_tail = self.tail_position
  self.compile(gene.props[THEN_KEY.to_key()])
  self.tail_position = old_tail
  self.end_scope()
  self.emit(Instruction(kind: IkJump, arg0: end_label.to_value()))

  # Handle elif branches if they exist
  if gene.props.has_key(ELIF_KEY.to_key()):
    let elifs = gene.props[ELIF_KEY.to_key()]
    case elifs.kind:
      of VkArray:
        # Process elif conditions and bodies in pairs
        for i in countup(0, elifs.ref.arr.len - 1, 2):
          self.emit(Instruction(kind: IkNoop, label: next_label))
          
          if i < elifs.ref.arr.len - 1:
            # Compile elif condition
            self.compile(elifs.ref.arr[i])
            next_label = new_label()
            self.emit(Instruction(kind: IkJumpIfFalse, arg0: next_label.to_value()))
            
            # Compile elif body (preserves tail position)
            self.start_scope()
            let old_tail_elif = self.tail_position
            self.compile(elifs.ref.arr[i + 1])
            self.tail_position = old_tail_elif
            self.end_scope()
            self.emit(Instruction(kind: IkJump, arg0: end_label.to_value()))
      else:
        discard

  # Compile else branch (preserves tail position)
  self.emit(Instruction(kind: IkNoop, label: next_label))
  self.start_scope()
  let old_tail_else = self.tail_position
  self.compile(gene.props[ELSE_KEY.to_key()])
  self.tail_position = old_tail_else
  self.end_scope()

  self.emit(Instruction(kind: IkNoop, label: end_label))

  self.end_scope()

proc compile_caller_eval(self: Compiler, gene: ptr Gene)  # Forward declaration
proc compile_async(self: Compiler, gene: ptr Gene)  # Forward declaration
proc compile_await(self: Compiler, gene: ptr Gene)  # Forward declaration
proc compile_spawn(self: Compiler, gene: ptr Gene)  # Forward declaration
proc compile_yield(self: Compiler, gene: ptr Gene)  # Forward declaration
proc compile_selector(self: Compiler, gene: ptr Gene)  # Forward declaration
proc compile_at_selector(self: Compiler, gene: ptr Gene)  # Forward declaration
proc compile_set(self: Compiler, gene: ptr Gene)  # Forward declaration
proc compile_import(self: Compiler, gene: ptr Gene)  # Forward declaration

proc compile_var(self: Compiler, gene: ptr Gene) =
  let name = gene.children[0]

  # Handle namespace variables like $ns/a
  if name.kind == VkComplexSymbol:
    let parts = name.ref.csymbol
    if parts.len >= 2 and parts[0] == "$ns":
      # This is a namespace variable, store it directly in namespace
      if gene.children.len > 1:
        # Compile the value
        self.compile(gene.children[1])
      else:
        # No value, use NIL
        self.emit(Instruction(kind: IkPushValue, arg0: NIL))

      # Store in namespace
      let var_name = parts[1..^1].join("/")
      self.emit(Instruction(kind: IkNamespaceStore, arg0: var_name.to_symbol_value()))
      return

    # Handle class/instance variables like /table (which becomes ["", "table"])
    if parts.len >= 2 and parts[0] == "":
      # This is a class or instance variable, store it in namespace
      if gene.children.len > 1:
        # Compile the value
        self.compile(gene.children[1])
      else:
        # No value, use NIL
        self.emit(Instruction(kind: IkPushValue, arg0: NIL))

      # Store in namespace with the full name (e.g., "/table")
      let var_name = "/" & parts[1..^1].join("/")
      self.emit(Instruction(kind: IkNamespaceStore, arg0: var_name.to_symbol_value()))
      return

    # Handle namespace/class member variables like Record/orm
    # This stores a value in a namespace or class member
    if parts.len >= 2:
      # Resolve the first part (e.g., "Record")
      let key = parts[0].to_key()
      if self.scope_tracker.mappings.has_key(key):
        self.emit(Instruction(kind: IkVarResolve, arg0: self.scope_tracker.mappings[key].to_value()))
      else:
        self.emit(Instruction(kind: IkResolveSymbol, arg0: cast[Value](key)))

      # Navigate through intermediate parts if more than 2 parts
      for i in 1..<parts.len-1:
        let part_key = parts[i].to_key()
        self.emit(Instruction(kind: IkGetMember, arg0: cast[Value](part_key)))

      # Compile the value
      if gene.children.len > 1:
        self.compile(gene.children[1])
      else:
        self.emit(Instruction(kind: IkPushValue, arg0: NIL))

      # Set the final member (e.g., "orm")
      let last_key = parts[^1].to_key()
      self.emit(Instruction(kind: IkSetMember, arg0: last_key))
      return

  # Regular variable handling
  if name.kind != VkSymbol:
    when not defined(release):
      echo "ERROR: Variable name is not a symbol"
      echo "  name.kind = ", name.kind
      if name.kind == VkComplexSymbol:
        echo "  complex symbol parts = ", name.ref.csymbol
    not_allowed("Variable name must be a symbol")
    
  let index = self.scope_tracker.next_index
  self.scope_tracker.mappings[name.str.to_key()] = index
  if gene.children.len > 1:
    self.compile(gene.children[1])
    self.add_scope_start()
    self.scope_tracker.next_index.inc()
    self.emit(Instruction(kind: IkVar, arg0: index.to_value()))
  else:
    self.add_scope_start()
    self.scope_tracker.next_index.inc()
    self.emit(Instruction(kind: IkVarValue, arg0: NIL, arg1: index))

proc compile_assignment(self: Compiler, gene: ptr Gene) =
  let `type` = gene.type
  let operator = gene.children[0].str
  
  if `type`.kind == VkSymbol:
    # For compound assignment, we need to load the current value first
    if operator != "=":
      let key = `type`.str.to_key()
      let found = self.scope_tracker.locate(key)
      if found.local_index >= 0:
        if found.parent_index == 0:
          self.emit(Instruction(kind: IkVarResolve, arg0: found.local_index.to_value()))
        else:
          self.emit(Instruction(kind: IkVarResolveInherited, arg0: found.local_index.to_value(), arg1: found.parent_index))
      else:
        self.emit(Instruction(kind: IkResolveSymbol, arg0: cast[Value](key)))
      
      # Compile the right-hand side value
      self.compile(gene.children[1])
      
      # Apply the operation
      case operator:
        of "+=":
          self.emit(Instruction(kind: IkAdd))
        of "-=":
          self.emit(Instruction(kind: IkSub))
        else:
          not_allowed("Unsupported compound assignment operator: " & operator)
    else:
      # Regular assignment - check for increment/decrement pattern
      let rhs = gene.children[1]
      let key = `type`.str.to_key()
      let found = self.scope_tracker.locate(key)
      
      # Check for (x = (x + 1)) or (x = (x - 1)) pattern
      # In infix notation: (x + 1) has type=x and children=[+, 1]
      if found.local_index >= 0 and found.parent_index == 0 and
         rhs.kind == VkGene and rhs.gene.children.len == 2:
        let rhs_gene = rhs.gene
        let op = rhs_gene.children[0]
        let rhs_operand = rhs_gene.children[1]
        
        # Check if it's (x + 1) or (x - 1) where x is the gene type
        if rhs_gene.type.kind == VkSymbol and rhs_gene.type.str == `type`.str and
           op.kind == VkSymbol and rhs_operand.kind == VkInt:
          if op.str == "+" and rhs_operand.int64 == 1:
            # Generate IkIncVar instead
            self.emit(Instruction(kind: IkIncVar, arg0: found.local_index.to_value()))
            return
          elif op.str == "-" and rhs_operand.int64 == 1:
            # Generate IkDecVar instead
            self.emit(Instruction(kind: IkDecVar, arg0: found.local_index.to_value()))
            return
      
      # Regular assignment - compile the value
      self.compile(gene.children[1])
    
    # Store the result
    let key = `type`.str.to_key()
    let found = self.scope_tracker.locate(key)
    if found.local_index >= 0:
      if found.parent_index == 0:
        self.emit(Instruction(kind: IkVarAssign, arg0: found.local_index.to_value()))
      else:
        self.emit(Instruction(kind: IkVarAssignInherited, arg0: found.local_index.to_value(), arg1: found.parent_index))
    else:
      self.emit(Instruction(kind: IkAssign, arg0: `type`))
  elif `type`.kind == VkComplexSymbol:
    let r = translate_symbol(`type`).ref
    let key = r.csymbol[0].to_key()
    
    # Load the target object first (for both regular and compound assignment)
    if r.csymbol[0] == "SPECIAL_NS":
      self.emit(Instruction(kind: IkResolveSymbol, arg0: cast[Value](SYM_NS)))
    elif self.scope_tracker.mappings.has_key(key):
      self.emit(Instruction(kind: IkVarResolve, arg0: self.scope_tracker.mappings[key].to_value()))
    else:
      self.emit(Instruction(kind: IkResolveSymbol, arg0: cast[Value](key)))
      
    # Navigate to parent object (if nested property access)
    if r.csymbol.len > 2:
      for s in r.csymbol[1..^2]:
        let (is_int, i) = to_int(s)
        if is_int:
          self.emit(Instruction(kind: IkGetChild, arg0: i))
        elif s.starts_with("."):
          let method_value = s[1..^1].to_symbol_value()
          self.emit(Instruction(kind: IkResolveMethod, arg0: method_value))
          self.emit(Instruction(kind: IkUnifiedMethodCall0, arg0: method_value))
        else:
          let key = s.to_key()
          self.emit(Instruction(kind: IkGetMember, arg0: cast[Value](key)))
    
    if operator != "=":
      # For compound assignment, duplicate the target object on the stack
      # Stack: [target] -> [target, target]
      self.emit(Instruction(kind: IkDup))
      
      # Get current value
      let last_segment = r.csymbol[^1]
      let (is_int, i) = to_int(last_segment)
      if is_int:
        self.emit(Instruction(kind: IkGetChild, arg0: i))
      else:
        self.emit(Instruction(kind: IkGetMember, arg0: last_segment.to_key()))
      
      # Compile the right-hand side value
      self.compile(gene.children[1])
      
      # Apply the operation
      case operator:
        of "+=":
          self.emit(Instruction(kind: IkAdd))
        of "-=":
          self.emit(Instruction(kind: IkSub))
        else:
          not_allowed("Unsupported compound assignment operator: " & operator)
      
      # Now stack should be: [target, new_value]
      # Set the property
      let last_segment2 = r.csymbol[^1]
      let (is_int2, i2) = to_int(last_segment2)
      if is_int2:
        self.emit(Instruction(kind: IkSetChild, arg0: i2))
      else:
        self.emit(Instruction(kind: IkSetMember, arg0: last_segment2.to_key()))
    else:
      # Regular assignment
      self.compile(gene.children[1])
      
      let last_segment = r.csymbol[^1]
      let (is_int, i) = to_int(last_segment)
      if is_int:
        self.emit(Instruction(kind: IkSetChild, arg0: i))
      else:
        self.emit(Instruction(kind: IkSetMember, arg0: last_segment.to_key()))
  else:
    not_allowed($`type`)

proc compile_loop(self: Compiler, gene: ptr Gene) =
  let start_label = new_label()
  let end_label = new_label()
  
  # Track this loop
  self.loop_stack.add(LoopInfo(start_label: start_label, end_label: end_label))
  
  self.emit(Instruction(kind: IkLoopStart, label: start_label))
  self.compile(gene.children)
  self.emit(Instruction(kind: IkContinue, arg0: start_label.to_value()))
  self.emit(Instruction(kind: IkLoopEnd, label: end_label))
  
  # Pop loop from stack
  discard self.loop_stack.pop()

proc compile_while(self: Compiler, gene: ptr Gene) =
  if gene.children.len < 1:
    not_allowed("while expects at least 1 argument (condition)")
  
  let label = new_label()
  let end_label = new_label()
  
  # Track this loop
  self.loop_stack.add(LoopInfo(start_label: label, end_label: end_label))
  
  # Mark loop start
  self.emit(Instruction(kind: IkLoopStart, label: label))
  
  # Compile and test condition
  self.compile(gene.children[0])
  self.emit(Instruction(kind: IkJumpIfFalse, arg0: end_label.to_value()))
  
  # Compile body (remaining children)
  if gene.children.len > 1:
    # Use the seq compile method which handles popping correctly
    self.compile(gene.children[1..^1])
    # Pop the final value from the loop body since we don't need it
    self.emit(Instruction(kind: IkPop))
  
  # Jump back to condition
  self.emit(Instruction(kind: IkContinue, arg0: label.to_value()))
  
  # Mark loop end
  self.emit(Instruction(kind: IkLoopEnd, label: end_label))
  
  # Push NIL as the result of the while loop
  self.emit(Instruction(kind: IkPushNil))
  
  # Pop loop from stack
  discard self.loop_stack.pop()

proc compile_repeat(self: Compiler, gene: ptr Gene) =
  if gene.children.len < 1:
    not_allowed("repeat expects at least 1 argument (count)")
  
  # For now, implement a simple version without index/total variables
  if gene.props.has_key(INDEX_KEY.to_key()) or gene.props.has_key(TOTAL_KEY.to_key()):
    not_allowed("repeat with index/total variables not yet implemented in VM")
  
  let start_label = new_label()
  let end_label = new_label()
  
  # Track this loop
  self.loop_stack.add(LoopInfo(start_label: start_label, end_label: end_label))
  
  # Compile count expression
  self.compile(gene.children[0])

  # Initialize repeat loop
  self.emit(Instruction(kind: IkRepeatInit, arg0: end_label.to_value()))

  # Mark the start of loop body
  self.emit(Instruction(kind: IkNoop, label: start_label))

  if gene.children.len > 1:
    self.start_scope()
    for i in 1..<gene.children.len:
      self.compile(gene.children[i])
      self.emit(Instruction(kind: IkPop))
    self.end_scope()

  self.emit(Instruction(kind: IkRepeatDecCheck, arg0: start_label.to_value()))

  # Push nil as the result, mark loop end
  self.emit(Instruction(kind: IkPushNil, label: end_label))
  
  # Pop loop from stack
  discard self.loop_stack.pop()

proc compile_for(self: Compiler, gene: ptr Gene) =
  # (for var in collection body...)
  if gene.children.len < 2:
    not_allowed("for expects at least 2 arguments (variable and collection)")
  
  let var_node = gene.children[0]
  if var_node.kind != VkSymbol:
    not_allowed("for loop variable must be a symbol")
  
  # Check for 'in' keyword
  if gene.children.len < 3 or gene.children[1].kind != VkSymbol or gene.children[1].str != "in":
    not_allowed("for loop requires 'in' keyword")
  
  let var_name = var_node.str
  let collection = gene.children[2]
  
  # Create a scope for the entire for loop to hold temporary variables
  self.start_scope()
  
  # Store collection in a temporary variable
  self.compile(collection)
  let collection_index = self.scope_tracker.next_index
  self.scope_tracker.mappings["$for_collection".to_key()] = collection_index
  self.add_scope_start()
  self.scope_tracker.next_index.inc()
  self.emit(Instruction(kind: IkVar, arg0: collection_index.to_value()))
  
  # Store index in a temporary variable, initialized to 0
  self.emit(Instruction(kind: IkPushValue, arg0: 0.to_value()))
  let index_var = self.scope_tracker.next_index
  self.scope_tracker.mappings["$for_index".to_key()] = index_var
  self.scope_tracker.next_index.inc()
  self.emit(Instruction(kind: IkVar, arg0: index_var.to_value()))
  
  let start_label = new_label()
  let end_label = new_label()
  
  # Track this loop
  self.loop_stack.add(LoopInfo(start_label: start_label, end_label: end_label))
  
  # Mark loop start
  self.emit(Instruction(kind: IkLoopStart, label: start_label))
  
  # Check if index < collection.length
  # Load index
  self.emit(Instruction(kind: IkVarResolve, arg0: index_var.to_value()))
  # Load collection
  self.emit(Instruction(kind: IkVarResolve, arg0: collection_index.to_value()))
  # Get length
  self.emit(Instruction(kind: IkLen))
  # Compare
  self.emit(Instruction(kind: IkLt))
  self.emit(Instruction(kind: IkJumpIfFalse, arg0: end_label.to_value()))
  
  # Create scope for loop iteration
  self.start_scope()
  
  # Get current element: collection[index]
  # Load collection
  self.emit(Instruction(kind: IkVarResolve, arg0: collection_index.to_value()))
  # Load index
  self.emit(Instruction(kind: IkVarResolve, arg0: index_var.to_value()))
  # Get element
  self.emit(Instruction(kind: IkGetChildDynamic))
  
  # Store element in loop variable
  let var_index = self.scope_tracker.next_index
  self.scope_tracker.mappings[var_name.to_key()] = var_index
  self.add_scope_start()
  self.scope_tracker.next_index.inc()
  self.emit(Instruction(kind: IkVar, arg0: var_index.to_value()))
  
  # Compile body (remaining children after 'in' and collection)
  if gene.children.len > 3:
    for i in 3..<gene.children.len:
      self.compile(gene.children[i])
      # Pop the result (we don't need it)
      self.emit(Instruction(kind: IkPop))
  
  # End the iteration scope
  self.end_scope()
  
  # Increment index
  # Load current index
  self.emit(Instruction(kind: IkVarResolve, arg0: index_var.to_value()))
  # Add 1
  self.emit(Instruction(kind: IkPushValue, arg0: 1.to_value()))
  self.emit(Instruction(kind: IkAdd))
  # Store back
  self.emit(Instruction(kind: IkVarAssign, arg0: index_var.to_value()))
  
  # Jump back to condition check
  self.emit(Instruction(kind: IkContinue, arg0: start_label.to_value()))
  
  # Mark loop end
  self.emit(Instruction(kind: IkLoopEnd, label: end_label))
  
  # End the for loop scope
  self.end_scope()
  
  # Push nil as the result
  self.emit(Instruction(kind: IkPushNil))
  
  # Pop loop from stack
  discard self.loop_stack.pop()

proc compile_enum(self: Compiler, gene: ptr Gene) =
  # (enum Color red green blue)
  # (enum Status ^values [ok error pending])
  if gene.children.len < 1:
    not_allowed("enum expects at least a name")
  
  let name_node = gene.children[0]
  if name_node.kind != VkSymbol:
    not_allowed("enum name must be a symbol")
  
  let enum_name = name_node.str
  
  # Create the enum
  self.emit(Instruction(kind: IkPushValue, arg0: enum_name.to_value()))
  self.emit(Instruction(kind: IkCreateEnum))
  
  # Check if ^values prop is used
  var start_idx = 1
  if gene.props.has_key("values".to_key()):
    # Values are provided in the ^values property
    let values_array = gene.props["values".to_key()]
    if values_array.kind != VkArray:
      not_allowed("enum ^values must be an array")
    
    var value = 0
    for member in values_array.ref.arr:
      if member.kind != VkSymbol:
        not_allowed("enum member must be a symbol")
      # Push member name and value
      self.emit(Instruction(kind: IkPushValue, arg0: member.str.to_value()))
      self.emit(Instruction(kind: IkPushValue, arg0: value.to_value()))
      self.emit(Instruction(kind: IkEnumAddMember))
      value.inc()
  else:
    # Members are provided as children
    var value = 0
    var i = start_idx
    while i < gene.children.len:
      let member = gene.children[i]
      if member.kind != VkSymbol:
        not_allowed("enum member must be a symbol")
      
      # Check if next child is '=' for custom value
      if i + 2 < gene.children.len and 
         gene.children[i + 1].kind == VkSymbol and 
         gene.children[i + 1].str == "=":
        # Custom value provided
        i += 2
        if gene.children[i].kind != VkInt:
          not_allowed("enum member value must be an integer")
        value = gene.children[i].int
      
      # Push member name and value
      self.emit(Instruction(kind: IkPushValue, arg0: member.str.to_value()))
      self.emit(Instruction(kind: IkPushValue, arg0: value.to_value()))
      self.emit(Instruction(kind: IkEnumAddMember))
      
      value.inc()
      i.inc()
  
  # Store the enum in the namespace  
  let index = self.scope_tracker.next_index
  self.scope_tracker.mappings[enum_name.to_key()] = index
  self.add_scope_start()
  self.scope_tracker.next_index.inc()
  self.emit(Instruction(kind: IkVar, arg0: index.to_value()))

proc compile_break(self: Compiler, gene: ptr Gene) =
  if gene.children.len > 0:
    self.compile(gene.children[0])
  else:
    self.emit(Instruction(kind: IkPushNil))
  
  if self.loop_stack.len == 0:
    # Emit a break with label -1 to indicate no loop
    # This will be checked at runtime
    self.emit(Instruction(kind: IkBreak, arg0: (-1).to_value()))
  else:
    # Get the current loop's end label
    let current_loop = self.loop_stack[^1]
    self.emit(Instruction(kind: IkBreak, arg0: current_loop.end_label.to_value()))

proc compile_continue(self: Compiler, gene: ptr Gene) =
  if gene.children.len > 0:
    self.compile(gene.children[0])
  else:
    self.emit(Instruction(kind: IkPushNil))
  
  if self.loop_stack.len == 0:
    # Emit a continue with label -1 to indicate no loop
    # This will be checked at runtime
    self.emit(Instruction(kind: IkContinue, arg0: (-1).to_value()))
  else:
    # Get the current loop's start label
    let current_loop = self.loop_stack[^1]
    self.emit(Instruction(kind: IkContinue, arg0: current_loop.start_label.to_value()))

proc compile_throw(self: Compiler, gene: ptr Gene) =
  if gene.children.len > 0:
    # Throw with a value
    self.compile(gene.children[0])
  else:
    # Throw without a value (re-throw current exception)
    self.emit(Instruction(kind: IkPushNil))
  self.emit(Instruction(kind: IkThrow))

proc compile_try(self: Compiler, gene: ptr Gene) =
  let catch_end_label = new_label()
  let finally_label = new_label()
  let end_label = new_label()
  
  # Check if there's a finally block
  var has_finally = false
  var finally_idx = -1
  for idx in 0..<gene.children.len:
    if gene.children[idx].kind == VkSymbol and gene.children[idx].str == "finally":
      has_finally = true
      finally_idx = idx
      break
  
  # Mark start of try block
  # If we have a finally, catch handler should point to finally_label
  if has_finally:
    self.emit(Instruction(kind: IkTryStart, arg0: catch_end_label.to_value(), arg1: finally_label))
  else:
    self.emit(Instruction(kind: IkTryStart, arg0: catch_end_label.to_value()))
  
  # Compile try body
  var i = 0
  while i < gene.children.len:
    let child = gene.children[i]
    if child.kind == VkSymbol and (child.str == "catch" or child.str == "finally"):
      break
    self.compile(child)
    inc i
  
  # Mark end of try block
  self.emit(Instruction(kind: IkTryEnd))
  
  # If we have a finally block, we need to preserve the try block's value
  if has_finally:
    # The try block's value is on the stack - we'll handle it in the finally section
    self.emit(Instruction(kind: IkJump, arg0: finally_label.to_value()))
  else:
    self.emit(Instruction(kind: IkJump, arg0: end_label.to_value()))
  
  # Handle catch blocks
  self.emit(Instruction(kind: IkNoop, label: catch_end_label))
  var catch_count = 0
  while i < gene.children.len:
    let child = gene.children[i]
    if child.kind == VkSymbol and child.str == "catch":
      inc i
      if i < gene.children.len:
        # Get the catch pattern
        let pattern = gene.children[i]
        inc i
        
        var next_catch_label: Label
        let is_catch_all = pattern.kind == VkSymbol and pattern.str == "*"
        
        # Generate catch matching code
        if is_catch_all:
          # Catch all - no need to check type
          self.emit(Instruction(kind: IkCatchStart))
        else:
          # Type-specific catch
          next_catch_label = new_label()
          
          # Check if exception matches this type
          self.emit(Instruction(kind: IkCatchStart))
          
          # Load the current exception and check its type
          self.emit(Instruction(kind: IkPushValue, arg0: App.app.gene_ns))
          self.emit(Instruction(kind: IkGetMember, arg0: "ex".to_key().to_value()))
          
          # Get the class of the exception
          self.emit(Instruction(kind: IkGetClass))
          
          # Load the expected exception type
          self.compile(pattern)
          
          # Check if they match (including inheritance)
          self.emit(Instruction(kind: IkIsInstance))
          
          # If not a match, jump to next catch
          self.emit(Instruction(kind: IkJumpIfFalse, arg0: next_catch_label.to_value()))
        
        # Compile catch body
        while i < gene.children.len:
          let body_child = gene.children[i]
          if body_child.kind == VkSymbol and (body_child.str == "catch" or body_child.str == "finally"):
            break
          self.compile(body_child)
          inc i
        
        self.emit(Instruction(kind: IkCatchEnd))
        # Jump to finally if exists, otherwise to end
        if has_finally:
          self.emit(Instruction(kind: IkJump, arg0: finally_label.to_value()))
        else:
          self.emit(Instruction(kind: IkJump, arg0: end_label.to_value()))
        
        # Add label for next catch if this was a type-specific catch
        if not is_catch_all:
          self.emit(Instruction(kind: IkNoop, label: next_catch_label))
          # Pop the exception handler and push it back for the next catch
          self.emit(Instruction(kind: IkCatchRestore))
        
        catch_count.inc
    elif child.kind == VkSymbol and child.str == "finally":
      break
    else:
      inc i
  
  # If no catch blocks handled the exception, re-throw
  if catch_count > 0:
    self.emit(Instruction(kind: IkThrow))
  
  # Handle finally block
  if has_finally:
    self.emit(Instruction(kind: IkNoop, label: finally_label))
    self.emit(Instruction(kind: IkFinally))
    
    # Compile finally body
    i = finally_idx + 1
    while i < gene.children.len:
      self.compile(gene.children[i])
      inc i
    
    self.emit(Instruction(kind: IkFinallyEnd))
  
  self.emit(Instruction(kind: IkNoop, label: end_label))

proc compile_fn(self: Compiler, input: Value) =
  self.emit(Instruction(kind: IkFunction, arg0: input))
  let tracker_copy = copy_scope_tracker(self.scope_tracker)

  var compiled_body: CompilationUnit = nil
  if self.eager_functions:
    var fn_obj = to_function(input)
    fn_obj.scope_tracker = tracker_copy
    compile(fn_obj, true)
    compiled_body = fn_obj.body_compiled

  let info = new_function_def_info(tracker_copy, compiled_body)
  self.emit(Instruction(kind: IkData, arg0: info.to_value()))

proc compile_return(self: Compiler, gene: ptr Gene) =
  if gene.children.len > 0:
    self.compile(gene.children[0])
  else:
    self.emit(Instruction(kind: IkPushNil))
  self.emit(Instruction(kind: IkReturn))

proc compile_block(self: Compiler, input: Value) =
  self.emit(Instruction(kind: IkBlock, arg0: input))
  var r = new_ref(VkScopeTracker)
  r.scope_tracker = self.scope_tracker
  self.emit(Instruction(kind: IkData, arg0: r.to_ref_value()))

proc compile_compile(self: Compiler, input: Value) =
  self.emit(Instruction(kind: IkCompileFn, arg0: input))
  var r = new_ref(VkScopeTracker)
  r.scope_tracker = self.scope_tracker
  self.emit(Instruction(kind: IkData, arg0: r.to_ref_value()))

proc compile_ns(self: Compiler, gene: ptr Gene) =
  self.emit(Instruction(kind: IkNamespace, arg0: gene.children[0]))
  if gene.children.len > 1:
    let body = new_stream_value(gene.children[1..^1])
    self.emit(Instruction(kind: IkPushValue, arg0: body))
    self.emit(Instruction(kind: IkCompileInit))
    self.emit(Instruction(kind: IkCallInit))

proc compile_method_definition(self: Compiler, gene: ptr Gene) =
  # Method definition: (.fn name args body...) or (.fn name arg body...)
  if gene.children.len < 2:
    not_allowed("Method definition requires at least name and args")
  
  let name = gene.children[0]
  if name.kind != VkSymbol:
    not_allowed("Method name must be a symbol")
  
  # Create a function from the method definition
  # The method is similar to (fn name args body...) but bound to the class
  var fn_value = new_gene_value()
  fn_value.gene.type = "fn".to_symbol_value()
  
  # Add the method name
  fn_value.gene.children.add(gene.children[0])
  
  # Handle args - check if self is already the first parameter
  let args = gene.children[1]
  var method_args: Value
  
  if args.kind == VkArray:
    if args.ref.arr.len == 0:
      method_args = new_array_value()
      method_args.ref.arr.add("self".to_symbol_value())
    elif args.ref.arr[0].kind == VkSymbol and args.ref.arr[0].str == "self":
      method_args = new_array_value()
      for arg in args.ref.arr:
        method_args.ref.arr.add(arg)
    else:
      method_args = new_array_value()
      method_args.ref.arr.add("self".to_symbol_value())
      for arg in args.ref.arr:
        method_args.ref.arr.add(arg)
  elif args.kind == VkSymbol and args.str == "_":
    # _ means no arguments, but methods need self
    method_args = new_array_value()
    method_args.ref.arr.add("self".to_symbol_value())
  elif args.kind == VkSymbol and args.str == "self":
    # Just self
    method_args = new_array_value()
    method_args.ref.arr.add(args)
  else:
    # Single argument that's not self - add self first
    method_args = new_array_value()
    method_args.ref.arr.add("self".to_symbol_value())
    method_args.ref.arr.add(args)
  
  fn_value.gene.children.add(method_args)

  # Add the body
  if gene.children.len == 2:
    # No body provided - default to nil
    fn_value.gene.children.add(NIL)
  else:
    for i in 2..<gene.children.len:
      fn_value.gene.children.add(gene.children[i])
  
  # Compile the function definition
  self.compile_fn(fn_value)
  
  # Add the method to the class
  self.emit(Instruction(kind: IkDefineMethod, arg0: name))

proc compile_constructor_definition(self: Compiler, gene: ptr Gene) =
  # Constructor definition: (.ctor args body...), (.ctor arg body...), (.ctor! args body...)
  if gene.children.len < 2:
    not_allowed("Constructor definition requires at least args and body")

  # Check if this is a macro constructor (.ctor!)
  let is_macro_ctor = gene.type.kind == VkSymbol and gene.type.str == ".ctor!"

  # Create a function from the constructor definition
  # The constructor is similar to (fn new args body...) but bound to the class
  var fn_value = new_gene_value()
  if is_macro_ctor:
    fn_value.gene.type = "fn!".to_symbol_value()  # Create macro-like function
  else:
    fn_value.gene.type = "fn".to_symbol_value()
  # Add "new" as the function name
  fn_value.gene.children.add("new".to_symbol_value())
  
  # Handle args - if it's not an array and there's more than 1 child (arg, body+),
  # wrap the single arg in an array (unless it's _ which means no args)
  let args = gene.children[0]
  if args.kind != VkArray and gene.children.len >= 2:
    # Check if it's _ (no arguments)
    if args.kind == VkSymbol and args.str == "_":
      # _ means no arguments - use it as is
      fn_value.gene.children.add(args)
    else:
      # Single argument without brackets - wrap it in an array
      var args_array = new_array_value()
      args_array.ref.arr.add(args)
      fn_value.gene.children.add(args_array)
  else:
    # Already an array or no body after it
    fn_value.gene.children.add(args)
  
  # Add remaining body
  for i in 1..<gene.children.len:
    fn_value.gene.children.add(gene.children[i])
  
  # Compile the function definition
  self.compile_fn(fn_value)
  
  # Set as constructor for the class
  self.emit(Instruction(kind: IkDefineConstructor))

proc compile_class(self: Compiler, gene: ptr Gene) =
  var body_start = 1
  if gene.children.len >= 3 and gene.children[1] == "<".to_symbol_value():
    body_start = 3
    self.compile(gene.children[2])
    self.emit(Instruction(kind: IkSubClass, arg0: gene.children[0]))
  else:
    self.emit(Instruction(kind: IkClass, arg0: gene.children[0]))

  if gene.children.len > body_start:
    let body = new_stream_value(gene.children[body_start..^1])
    self.emit(Instruction(kind: IkPushValue, arg0: body))
    self.emit(Instruction(kind: IkCompileInit))
    self.emit(Instruction(kind: IkCallInit))

# Construct a Gene object whose type is the class
# The Gene object will be used as the arguments to the constructor
proc compile_new(self: Compiler, gene: ptr Gene) =
  if gene.children.len < 1:
    raise new_exception(types.Exception, "new requires at least a class name")

  # Check if this is a macro constructor call (new!)
  let is_macro_new = gene.type.kind == VkSymbol and gene.type.str == "new!"

  # Compile the class (first argument)
  self.compile(gene.children[0])

  # Compile the arguments as a Gene when necessary
  if gene.children.len > 1:
    # Create a Gene containing all arguments
    self.emit(Instruction(kind: IkGeneStart))

    if is_macro_new:
      # For macro constructor, don't evaluate arguments - pass them as quoted
      self.quote_level.inc()
      for i in 1..<gene.children.len:
        self.compile(gene.children[i])
        self.emit(Instruction(kind: IkGeneAddChild))
      self.quote_level.dec()
    else:
      # For regular constructor, evaluate arguments normally
      for i in 1..<gene.children.len:
        self.compile(gene.children[i])
        self.emit(Instruction(kind: IkGeneAddChild))

    self.emit(Instruction(kind: IkGeneEnd))

  # Emit appropriate instruction based on constructor type
  if is_macro_new:
    self.emit(Instruction(kind: IkNewMacro))
  else:
    self.emit(Instruction(kind: IkNew))

proc compile_super(self: Compiler, gene: ptr Gene) =
  # Super: returns the parent class
  # Usage: (super .method args...)
  if gene.children.len > 0:
    not_allowed("super takes no arguments")
  
  # Push the parent class
  self.emit(Instruction(kind: IkSuper))

proc compile_match(self: Compiler, gene: ptr Gene) =
  # Match statement: (match pattern value)
  if gene.children.len != 2:
    not_allowed("match expects exactly 2 arguments: pattern and value")
  
  let pattern = gene.children[0]
  let value = gene.children[1]
  
  # Compile the value expression
  self.compile(value)
  
  # For now, handle simple variable binding: (match a [1])
  if pattern.kind == VkSymbol:
    # Simple variable binding - match doesn't create a new scope
    let var_name = pattern.str
    
    # Check if we're in a scope
    if self.scope_trackers.len == 0:
      not_allowed("match must be used within a scope")
    
    let var_index = self.scope_tracker.next_index
    self.scope_tracker.mappings[var_name.to_key()] = var_index
    self.add_scope_start()
    self.scope_tracker.next_index.inc()
    
    # Store the value in the variable
    self.emit(Instruction(kind: IkVar, arg0: var_index.to_value()))
    
    # Push nil as the result of match
    self.emit(Instruction(kind: IkPushNil))
  elif pattern.kind == VkArray:
    # Array pattern matching: (match [a b] [1 2])
    # For now, handle simple array destructuring
    
    # Store the value temporarily
    self.emit(Instruction(kind: IkDup))
    
    for i, elem in pattern.ref.arr:
      if elem.kind == VkSymbol:
        # Extract element at index i
        self.emit(Instruction(kind: IkDup))  # Duplicate the array
        self.emit(Instruction(kind: IkPushValue, arg0: i.to_value()))
        self.emit(Instruction(kind: IkGetMember))
        
        # Store in variable
        let var_name = elem.str
        let var_index = self.scope_tracker.next_index
        self.scope_tracker.mappings[var_name.to_key()] = var_index
        self.add_scope_start()
        self.scope_tracker.next_index.inc()
        self.emit(Instruction(kind: IkVar, arg0: var_index.to_value()))
    
    # Pop the original array
    self.emit(Instruction(kind: IkPop))
    
    # Push nil as the result of match
    self.emit(Instruction(kind: IkPushNil))
  else:
    not_allowed("Unsupported pattern type: " & $pattern.kind)

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

proc compile_gene_default(self: Compiler, gene: ptr Gene) {.inline.} =
  self.emit(Instruction(kind: IkGeneStart))
  self.compile(gene.type)
  self.emit(Instruction(kind: IkGeneSetType))

  # Handle properties with spread support
  for k, v in gene.props:
    let key_str = $k
    # Check for spread property: ^..., ^...1, ^...2, etc.
    if key_str.startsWith("..."):
      # Spread map into properties
      self.compile(v)
      self.emit(Instruction(kind: IkGenePropsSpread))
    else:
      # Normal property
      self.compile(v)
      self.emit(Instruction(kind: IkGeneSetProp, arg0: k))

  # Handle children with spread support
  var i = 0
  let children = gene.children
  while i < children.len:
    let child = children[i]

    # Check for standalone postfix spread: expr ...
    if i + 1 < children.len and children[i + 1].kind == VkSymbol and children[i + 1].str == "...":
      # Compile the expression and add with spread
      self.compile(child)
      self.emit(Instruction(kind: IkGeneAddSpread))
      i += 2  # Skip both the expr and the ... symbol
      continue

    # Check for suffix spread: a...
    if child.kind == VkSymbol and child.str.endsWith("...") and child.str.len > 3:
      # Compile the base symbol and add with spread
      let base_symbol = child.str[0..^4].to_symbol_value()  # Remove "..."
      self.compile(base_symbol)
      self.emit(Instruction(kind: IkGeneAddSpread))
      i += 1
      continue

    # Normal child - compile and add
    self.compile(child)
    self.emit(Instruction(kind: IkGeneAddChild))
    i += 1

  # Use IkTailCall when in tail position
  if self.tail_position:
    when DEBUG:
      echo "DEBUG: Generating IkTailCall in compile_gene_default"
    self.emit(Instruction(kind: IkTailCall))
  else:
    self.emit(Instruction(kind: IkGeneEnd))

# For a call that is unsure whether it is a function call or a macro call,
# we need to handle both cases and decide at runtime:
# * Compile type (use two labels to mark boundaries of two branches)
# * GeneCheckType Update code in place, remove incompatible branch
# * GeneStartMacro(fail if the type is not a macro)
# * Compile arguments assuming it is a macro call
# * FnLabel: GeneStart(fail if the type is not a function)
# * Compile arguments assuming it is a function call
# * GeneLabel: GeneEnd
# Similar logic is used for regular method calls and macro-method calls
proc compile_gene_unknown(self: Compiler, gene: ptr Gene) {.inline.} =
  # Special case: handle method calls like (obj .method ...)
  # These are parsed as genes with type obj/.method
  if gene.type.kind == VkComplexSymbol:
    let csym = gene.type.ref.csymbol
    # Check if this is a method access (second part starts with ".")
    if csym.len >= 2 and csym[1].starts_with("."):
      # This is a method call - compile it specially
      # The object will be on the stack after compiling the type
      # We need to ensure it's passed as the first argument
      self.compile(gene.type)  # This pushes object and method
      
      # After compiling obj/.method, stack has [obj, method]
      # IkGeneStartDefault will pop the method
      # We need to ensure obj is used as an argument
      let fn_label = new_label()
      let end_label = if gene.children.len == 0 and gene.props.len == 0: fn_label else: new_label()
      self.emit(Instruction(kind: IkGeneStartDefault, arg0: fn_label.to_value()))
      
      # The object is still on the stack - add it as the first child
      self.emit(Instruction(kind: IkGeneAddChild))
      
      # Add any explicit arguments
      self.quote_level.inc()

      # Handle properties with spread support
      for k, v in gene.props:
        let key_str = $k
        if key_str.startsWith("..."):
          self.compile(v)
          self.emit(Instruction(kind: IkGenePropsSpread))
        else:
          self.compile(v)
          self.emit(Instruction(kind: IkGeneSetProp, arg0: k))

      # Handle children with spread support
      var i = 0
      let children = gene.children
      while i < children.len:
        let child = children[i]

        # Check for standalone postfix spread: expr ...
        if i + 1 < children.len and children[i + 1].kind == VkSymbol and children[i + 1].str == "...":
          self.compile(child)
          self.emit(Instruction(kind: IkGeneAddSpread))
          i += 2
          continue

        # Check for suffix spread: a...
        if child.kind == VkSymbol and child.str.endsWith("...") and child.str.len > 3:
          let base_symbol = child.str[0..^4].to_symbol_value()
          self.compile(base_symbol)
          self.emit(Instruction(kind: IkGeneAddSpread))
          i += 1
          continue

        # Normal child
        self.compile(child)
        self.emit(Instruction(kind: IkGeneAddChild))
        i += 1

      self.quote_level.dec()
      
      self.emit(Instruction(kind: IkNoop, label: fn_label))
      self.emit(Instruction(kind: IkGeneEnd, label: end_label))
      return
  # Check for selector syntax: (target ./ property) or (target ./property)
  if DEBUG:
    echo "DEBUG: compile_gene_unknown: gene.type = ", gene.type
    echo "DEBUG: compile_gene_unknown: gene.children.len = ", gene.children.len
    if gene.children.len > 0:
      echo "DEBUG: compile_gene_unknown: first child = ", gene.children[0]
      if gene.children[0].kind == VkComplexSymbol:
        echo "DEBUG: compile_gene_unknown: first child csymbol = ", gene.children[0].ref.csymbol
  if gene.children.len >= 1:
    let first_child = gene.children[0]
    if first_child.kind == VkSymbol and first_child.str == "./":
      # Syntax: (target ./ property [default])
      if gene.children.len < 2 or gene.children.len > 3:
        not_allowed("(target ./ property [default]) expects 2 or 3 arguments")
      
      # Compile the target
      self.compile(gene.type)
      
      # Compile the property
      self.compile(gene.children[1])
      
      # If there's a default value, compile it
      if gene.children.len == 3:
        self.compile(gene.children[2])
        self.emit(Instruction(kind: IkGetMemberDefault))
      else:
        self.emit(Instruction(kind: IkGetMemberOrNil))
      return
    elif first_child.kind == VkComplexSymbol and first_child.ref.csymbol.len >= 2 and first_child.ref.csymbol[0] == ".":
      # Syntax: (target ./property) where ./property is a complex symbol
      if DEBUG:
        echo "DEBUG: Handling selector with complex symbol"
      # Compile the target
      self.compile(gene.type)
      
      # The property is the second part of the complex symbol
      let prop_name = first_child.ref.csymbol[1]
      # Check if property is numeric
      try:
        let idx = prop_name.parse_int()
        if DEBUG:
          echo "DEBUG: Property is numeric: ", idx
        self.emit(Instruction(kind: IkPushValue, arg0: idx.to_value()))
      except ValueError:
        if DEBUG:
          echo "DEBUG: Property is symbolic: ", prop_name
        self.emit(Instruction(kind: IkPushValue, arg0: prop_name.to_symbol_value()))
      
      # Check for default value (second child of gene)
      if gene.children.len == 2:
        self.compile(gene.children[1])
        self.emit(Instruction(kind: IkGetMemberDefault))
      else:
        self.emit(Instruction(kind: IkGetMemberOrNil))
      return
  
  let start_pos = self.output.instructions.len
  self.compile(gene.type)

  # if gene.args_are_literal():
  #   self.emit(Instruction(kind: IkGeneStartDefault))
  #   for k, v in gene.props:
  #     self.compile(v)
  #     self.emit(Instruction(kind: IkGeneSetProp, arg0: k))
  #   for child in gene.children:
  #     self.compile(child)
  #     self.emit(Instruction(kind: IkGeneAddChild))
  #   self.emit(Instruction(kind: IkGeneEnd))
  #   return

  # Check if we can determine at compile time that this is definitely NOT a macro
  # For performance: avoid dual-branch compilation for regular function calls
  var definitely_not_macro = false
  if gene.type.kind == VkSymbol:
    let func_name = gene.type.str
    # Functions not ending with '!' are regular functions (not macro-like)
    if not func_name.ends_with("!"):
      definitely_not_macro = true
    # Exception: control flow keywords might still need special handling
    if func_name in ["return", "break", "continue", "throw"]:
      definitely_not_macro = false
  elif gene.type.kind == VkGene and gene.type.gene.type == "@".to_symbol_value():
    # Selector results are not macros
    definitely_not_macro = true
  elif gene.type.kind == VkComplexSymbol:
    let parts = gene.type.ref.csymbol
    if parts.len > 0 and parts[0].startsWith("@"):
      # Selector results are not macros
      definitely_not_macro = true

  # Fast path optimizations for regular function calls (no properties)
  if definitely_not_macro and gene.props.len == 0:
    # Zero-argument optimization
    if gene.children.len == 0:
      self.emit(Instruction(kind: IkUnifiedCall0))
      return

    # Single-argument optimization
    if gene.children.len == 1:
      self.compile(gene.children[0])
      self.emit(Instruction(kind: IkUnifiedCall1))
      return

    # Multi-argument optimization (only if no spreads)
    var has_spread = false
    var i = 0
    while i < gene.children.len:
      let child = gene.children[i]
      if (i + 1 < gene.children.len and gene.children[i + 1].kind == VkSymbol and gene.children[i + 1].str == "...") or
         (child.kind == VkSymbol and child.str.endsWith("...") and child.str.len > 3):
        has_spread = true
        break
      i += 1

    if not has_spread:
      # Compile all arguments onto stack
      for child in gene.children:
        self.compile(child)
      # Single unified call instruction with argument count
      self.emit(Instruction(kind: IkUnifiedCall, arg1: gene.children.len.int32))
      return

  # Dual-branch compilation:
  # - Macro branch (quoted args): for VkFunction with is_macro_like=true - continues to next instruction
  # - Function branch (evaluated args): for VkFunction with is_macro_like=false - jumps to fn_label
  # Runtime dispatch checks is_macro_like flag to determine which branch to use

  let fn_label = new_label()
  let end_label = if gene.children.len == 0 and gene.props.len == 0: fn_label else: new_label()
  self.emit(Instruction(kind: IkGeneStartDefault, arg0: fn_label.to_value()))

  # Macro branch: compile arguments as quoted (for macro-like functions)
  self.quote_level.inc()

  for k, v in gene.props:
    let key_str = $k
    if key_str.startsWith("..."):
      self.compile(v)
      self.emit(Instruction(kind: IkGenePropsSpread))
    else:
      self.compile(v)
      self.emit(Instruction(kind: IkGeneSetProp, arg0: k))

  block:
    var i = 0
    let children = gene.children
    while i < children.len:
      let child = children[i]
      if i + 1 < children.len and children[i + 1].kind == VkSymbol and children[i + 1].str == "...":
        self.compile(child)
        self.emit(Instruction(kind: IkGeneAddSpread))
        i += 2
        continue
      if child.kind == VkSymbol and child.str.endsWith("...") and child.str.len > 3:
        let base_symbol = child.str[0..^4].to_symbol_value()
        self.compile(base_symbol)
        self.emit(Instruction(kind: IkGeneAddSpread))
        i += 1
        continue
      self.compile(child)
      self.emit(Instruction(kind: IkGeneAddChild))
      i += 1

  self.emit(Instruction(kind: IkJump, arg0: end_label.to_value()))
  self.quote_level.dec()

  # Function branch: compile arguments as evaluated (for VkFunction)
  if fn_label != end_label:
    self.emit(Instruction(kind: IkNoop, label: fn_label))

  for k, v in gene.props:
    let key_str = $k
    if key_str.startsWith("..."):
      self.compile(v)
      self.emit(Instruction(kind: IkGenePropsSpread))
    else:
      self.compile(v)
      self.emit(Instruction(kind: IkGeneSetProp, arg0: k))

  block:
    var i = 0
    let children = gene.children
    while i < children.len:
      let child = children[i]
      if i + 1 < children.len and children[i + 1].kind == VkSymbol and children[i + 1].str == "...":
        self.compile(child)
        self.emit(Instruction(kind: IkGeneAddSpread))
        i += 2
        continue
      if child.kind == VkSymbol and child.str.endsWith("...") and child.str.len > 3:
        let base_symbol = child.str[0..^4].to_symbol_value()
        self.compile(base_symbol)
        self.emit(Instruction(kind: IkGeneAddSpread))
        i += 1
        continue
      self.compile(child)
      self.emit(Instruction(kind: IkGeneAddChild))
      i += 1

  let gene_end_label = if fn_label == end_label: fn_label else: end_label
  self.emit(Instruction(kind: IkGeneEnd, arg0: start_pos, label: gene_end_label))
  # echo fmt"Added GeneEnd with label {end_label} at position {self.output.instructions.len - 1}"

# TODO: handle special cases:
# 1. No arguments
# 2. All arguments are primitives or array/map of primitives
#
# self, method_name, arguments
# self + method_name => bounded_method_object (is composed of self, class, method_object(is composed of name, logic))
# (bounded_method_object ...arguments)
proc compile_method_call(self: Compiler, gene: ptr Gene) {.inline.} =
  var method_name: string
  var method_value: Value
  var start_index = 0

  if gene.type.kind == VkSymbol and gene.type.str.starts_with("."):
    # (.method_name args...) - self is implicit
    method_name = gene.type.str[1..^1]
    method_value = method_name.to_symbol_value()
    self.emit(Instruction(kind: IkSelf))
  else:
    # (obj .method_name args...) - obj is explicit
    self.compile(gene.type)
    let first = gene.children[0]
    method_name = first.str[1..^1]
    method_value = method_name.to_symbol_value()
    start_index = 1  # Skip the method name when adding arguments

  let arg_count = gene.children.len - start_index

  if gene.props.len == 0:
    # Fast path: positional arguments only
    # Compile arguments - they'll be on stack after object
    for i in start_index..<gene.children.len:
      self.compile(gene.children[i])

    # Use unified method call instructions
    if arg_count == 0:
      self.emit(Instruction(kind: IkUnifiedMethodCall0, arg0: method_value))
    elif arg_count == 1:
      self.emit(Instruction(kind: IkUnifiedMethodCall1, arg0: method_value))
    elif arg_count == 2:
      self.emit(Instruction(kind: IkUnifiedMethodCall2, arg0: method_value))
    else:
      let total_args = arg_count + 1  # include self
      self.emit(
        Instruction(
          kind: IkUnifiedMethodCall,
          arg0: method_value,
          arg1: total_args.int32,
        )
      )
    return

  # Fallback path for named properties or other complex invocations
  let initial_pos = self.output.instructions.len
  let start_pos = initial_pos
  let label = new_label()
  self.emit(Instruction(kind: IkGeneStartDefault, arg0: label.to_value()))

  # Skip the macro path - jump directly to function call
  self.emit(Instruction(kind: IkJump, arg0: label.to_value()))

  # Function call path
  self.emit(Instruction(kind: IkNoop, label: label))

  # After IkGeneStartDefault replaces method with frame, stack is [object, frame]
  # We need to swap to get [frame, object] for IkGeneAddChild
  self.emit(Instruction(kind: IkSwap))

  # Now add the object as the first argument
  self.emit(Instruction(kind: IkGeneAddChild))

  # Add properties if any
  for k, v in gene.props:
    self.compile(v)
    self.emit(Instruction(kind: IkGeneSetProp, arg0: k))

  # Add remaining arguments (skip method name if it's in children)
  for i in start_index..<gene.children.len:
    self.compile(gene.children[i])
    self.emit(Instruction(kind: IkGeneAddChild))

  # Emit the call instruction
  # Note: Tail call optimization seems to have issues with methods, disable for now
  self.emit(Instruction(kind: IkGeneEnd, arg0: start_pos, label: label))

proc compile_gene(self: Compiler, input: Value) =
  let gene = input.gene
  
  # Special case: handle selector operator ./
  if not gene.type.is_nil():
    if DEBUG:
      echo "DEBUG: compile_gene: gene.type.kind = ", gene.type.kind
      if gene.type.kind == VkSymbol:
        echo "DEBUG: compile_gene: gene.type.str = '", gene.type.str, "'"
      elif gene.type.kind == VkComplexSymbol:
        echo "DEBUG: compile_gene: gene.type.csymbol = ", gene.type.ref.csymbol
    if gene.type.kind == VkSymbol and gene.type.str == "./":
      self.compile_selector(gene)
      return
    elif gene.type.kind == VkComplexSymbol and gene.type.ref.csymbol.len >= 2 and gene.type.ref.csymbol[0] == "." and gene.type.ref.csymbol[1] == "":
      # "./" is parsed as complex symbol @[".", ""]
      self.compile_selector(gene)
      return
  
  # Special case: handle range expressions like (0 .. 2)
  if gene.children.len == 2 and gene.children[0].kind == VkSymbol and gene.children[0].str == "..":
    # This is a range expression: (start .. end)
    self.compile(gene.type)  # start value
    self.compile(gene.children[1])  # end value
    self.emit(Instruction(kind: IkPushValue, arg0: NIL))  # default step
    self.emit(Instruction(kind: IkCreateRange))
    return
  
  # Special case: handle genes with numeric types and no children like (-1)
  if gene.children.len == 0 and gene.type.kind in {VkInt, VkFloat}:
    self.compile_literal(gene.type)
    return
  
  let is_quoted_symbol_method_call = gene.type.kind == VkQuote and gene.type.ref.quote.kind == VkSymbol and
    gene.children.len >= 1 and gene.children[0].kind == VkSymbol and gene.children[0].str.starts_with(".")

  if self.quote_level > 0 or gene.type == "_".to_symbol_value() or (gene.type.kind == VkQuote and not is_quoted_symbol_method_call):
    self.compile_gene_default(gene)
    return

  let `type` = gene.type
  
  # Check for infix notation: (value operator args...)
  # This handles cases like (6 / 2) or (i + 1)
  if gene.children.len >= 1:
    let first_child = gene.children[0]
    if first_child.kind == VkSymbol:
      if first_child.str in ["+", "-", "*", "/", "%", "**", "./", "<", "<=", ">", ">=", "==", "!="]:
        # Don't convert if the type is already an operator or special form
        if `type`.kind != VkSymbol or `type`.str notin ["var", "if", "fn", "fnx", "fnxx", "macro", "do", "loop", "while", "for", "ns", "class", "try", "throw", "$", "."]:
          # Convert infix to prefix notation and compile
          # (6 / 2) becomes (/ 6 2)
          # (i + 1) becomes (+ i 1)
          let prefix_gene = create(Gene)
          prefix_gene.type = first_child  # operator becomes the type
          prefix_gene.children = @[`type`] & gene.children[1..^1]  # value and rest of args
          self.compile_gene(prefix_gene.to_gene_value())
          return
      elif first_child.str.starts_with("."):
        # This is a method call: (obj .method args...)
        # Transform to method call format
        self.compile_method_call(gene)
        return
    elif first_child.kind == VkComplexSymbol and first_child.ref.csymbol.len >= 2 and first_child.ref.csymbol[0] == "." and first_child.ref.csymbol[1] == "":
      # Don't convert if the type is already an operator or special form
      if `type`.kind != VkSymbol or `type`.str notin ["var", "if", "fn", "fnx", "fnxx", "macro", "do", "loop", "while", "for", "ns", "class", "try", "throw", "$", "."]:
        # Convert infix to prefix notation and compile
        # (6 / 2) becomes (/ 6 2)
        # (i + 1) becomes (+ i 1)
        let prefix_gene = create(Gene)
        prefix_gene.type = first_child  # operator becomes the type
        prefix_gene.children = @[`type`] & gene.children[1..^1]  # value and rest of args
        self.compile_gene(prefix_gene.to_gene_value())
        return
  
  # Check if type is an arithmetic operator
  if `type`.kind == VkSymbol:
    case `type`.str:
      of "+":
        if gene.children.len == 0:
          # (+) with no args returns 0
          self.emit(Instruction(kind: IkPushValue, arg0: 0.to_value()))
          return
        elif gene.children.len == 1:
          # Unary + is identity
          self.compile(gene.children[0])
          return
        elif gene.children.len == 2:
          if self.compileVarOpLiteral(gene.children[0], gene.children[1], IkVarAddValue):
            return
          # Fall through to regular compilation
        # Multi-arg addition
        self.compile(gene.children[0])
        for i in 1..<gene.children.len:
          self.compile(gene.children[i])
          self.emit(Instruction(kind: IkAdd))
        return
      of "-":
        if gene.children.len == 0:
          not_allowed("- requires at least one argument")
        elif gene.children.len == 1:
          # Unary minus - use IkNeg instruction
          self.compile(gene.children[0])
          self.emit(Instruction(kind: IkNeg))
          return
        elif gene.children.len == 2:
          if self.compileVarOpLiteral(gene.children[0], gene.children[1], IkVarSubValue):
            return
          # Fall through to regular compilation
        # Multi-arg subtraction
        self.compile(gene.children[0])
        for i in 1..<gene.children.len:
          self.compile(gene.children[i])
          self.emit(Instruction(kind: IkSub))
        return
      of "*":
        if gene.children.len == 0:
          # (*) with no args returns 1
          self.emit(Instruction(kind: IkPushValue, arg0: 1.to_value()))
          return
        elif gene.children.len == 1:
          # Unary * is identity
          self.compile(gene.children[0])
          return
        elif gene.children.len == 2:
          if self.compileVarOpLiteral(gene.children[0], gene.children[1], IkVarMulValue):
            return
          # Fall through to regular compilation
        # Multi-arg multiplication
        self.compile(gene.children[0])
        for i in 1..<gene.children.len:
          self.compile(gene.children[i])
          self.emit(Instruction(kind: IkMul))
        return
      of "/":
        if gene.children.len == 0:
          not_allowed("/ requires at least one argument")
        elif gene.children.len == 1:
          # Unary / is reciprocal: 1/x
          self.emit(Instruction(kind: IkPushValue, arg0: 1.to_value()))
          self.compile(gene.children[0])
          self.emit(Instruction(kind: IkDiv))
          return
        elif gene.children.len == 2:
          if self.compileVarOpLiteral(gene.children[0], gene.children[1], IkVarDivValue):
            return
          # Fall through to regular compilation
        # Multi-arg division
        self.compile(gene.children[0])
        for i in 1..<gene.children.len:
          self.compile(gene.children[i])
          self.emit(Instruction(kind: IkDiv))
        return
      of "<":
        # Binary less than
        if gene.children.len != 2:
          not_allowed("< requires exactly 2 arguments")
        let first = gene.children[0]
        let second = gene.children[1]
        if second.kind in {VkInt, VkFloat} and self.compileVarOpLiteral(first, second, IkVarLtValue):
          return
        self.compile(first)
        self.compile(second)
        self.emit(Instruction(kind: IkLt))
        return
      of "<=":
        # Binary less than or equal
        if gene.children.len != 2:
          not_allowed("<= requires exactly 2 arguments")
        let first = gene.children[0]
        let second = gene.children[1]
        if second.kind in {VkInt, VkFloat} and self.compileVarOpLiteral(first, second, IkVarLeValue):
          return
        self.compile(first)
        self.compile(second)
        self.emit(Instruction(kind: IkLe))
        return
      of ">":
        # Binary greater than
        if gene.children.len != 2:
          not_allowed("> requires exactly 2 arguments")
        let first = gene.children[0]
        let second = gene.children[1]
        if second.kind in {VkInt, VkFloat} and self.compileVarOpLiteral(first, second, IkVarGtValue):
          return
        self.compile(first)
        self.compile(second)
        self.emit(Instruction(kind: IkGt))
        return
      of ">=":
        # Binary greater than or equal
        if gene.children.len != 2:
          not_allowed(">= requires exactly 2 arguments")
        let first = gene.children[0]
        let second = gene.children[1]
        if second.kind in {VkInt, VkFloat} and self.compileVarOpLiteral(first, second, IkVarGeValue):
          return
        self.compile(first)
        self.compile(second)
        self.emit(Instruction(kind: IkGe))
        return
      of "==":
        # Binary equality
        if gene.children.len != 2:
          not_allowed("== requires exactly 2 arguments")
        let first = gene.children[0]
        let second = gene.children[1]
        if second.kind in {VkInt, VkFloat} and self.compileVarOpLiteral(first, second, IkVarEqValue):
          return
        self.compile(first)
        self.compile(second)
        self.emit(Instruction(kind: IkEq))
        return
      of "!=":
        # Binary inequality
        if gene.children.len != 2:
          not_allowed("!= requires exactly 2 arguments")
        self.compile(gene.children[0])
        self.compile(gene.children[1])
        self.emit(Instruction(kind: IkNe))
        return
      else:
        discard  # Not an arithmetic operator, continue with normal processing
  
  if gene.children.len > 0:
    let first = gene.children[0]
    if first.kind == VkSymbol:
      case first.str:
        of "=", "+=", "-=":
          self.compile_assignment(gene)
          return
        of "&&":
          self.compile(`type`)
          self.compile(gene.children[1])
          self.emit(Instruction(kind: IkAnd))
          return
        of "||":
          self.compile(`type`)
          self.compile(gene.children[1])
          self.emit(Instruction(kind: IkOr))
          return
        of "not":
          if gene.children.len != 1:
            not_allowed("not expects exactly 1 argument")
          self.compile_unary_not(gene.children[0])
          return
        of "..":
          self.compile_range_operator(gene)
          return
        of "->":
          self.compile_block(input)
          return
        else:
          if first.str.starts_with("."):
            self.compile_method_call(gene)
            return

  if `type`.kind == VkSymbol:
    case `type`.str:
      of "do":
        self.compile_do(gene)
        return
      of "if":
        self.compile_if(gene)
        return
      of "var":
        self.compile_var(gene)
        return
      of "loop":
        self.compile_loop(gene)
        return
      of "while":
        self.compile_while(gene)
        return
      of "repeat":
        self.compile_repeat(gene)
        return
      of "for":
        self.compile_for(gene)
        return
      of "enum":
        self.compile_enum(gene)
        return
      of "..":
        self.compile_range_operator(gene)
        return
      of "not":
        if gene.children.len != 1:
          not_allowed("not expects exactly 1 argument")
        self.compile_unary_not(gene.children[0])
        return
      of "break":
        self.compile_break(gene)
        return
      of "continue":
        self.compile_continue(gene)
        return
      of "fn", "fn!", "fnx", "fnxx":
        self.compile_fn(input)
        return
      of "->":
        self.compile_block(input)
        return
      of "compile":
        self.compile_compile(input)
        return
      of "return":
        self.compile_return(gene)
        return
      of "try":
        self.compile_try(gene)
        return
      of "throw":
        self.compile_throw(gene)
        return
      of "ns":
        self.compile_ns(gene)
        return
      of "class":
        self.compile_class(gene)
        return
      of "new", "new!":
        self.compile_new(gene)
        return
      of "super":
        self.compile_super(gene)
        return
      of "match":
        self.compile_match(gene)
        return
      of "range":
        self.compile_range(gene)
        return
      of "async":
        self.compile_async(gene)
        return
      of "await":
        self.compile_await(gene)
        return
      of "spawn":
        self.compile_spawn(gene)
        return
      of "spawn_return":
        # spawn_return is an alias for (spawn return: expr)
        # Transform it by adding return: as first child
        var modified_gene = new_gene(gene.type)
        modified_gene.props = gene.props
        modified_gene.children = @["return:".to_symbol_value()] & gene.children
        self.compile_spawn(modified_gene)
        return
      of "yield":
        self.compile_yield(gene)
        return
      of "void":
        # Compile all arguments but return nil
        for child in gene.children:
          self.compile(child)
          self.emit(Instruction(kind: IkPop))
        self.emit(Instruction(kind: IkPushNil))
        return
      of ".fn":
        # Method definition inside class body
        self.compile_method_definition(gene)
        return
      of ".ctor", ".ctor!":
        # Constructor definition inside class body
        self.compile_constructor_definition(gene)
        return
      of "eval":
        # Evaluate expressions
        if gene.children.len == 0:
          self.emit(Instruction(kind: IkPushNil))
        else:
          # Compile each argument and evaluate
          for i, child in gene.children:
            self.compile(child)
            # Add eval instruction to evaluate the value
            self.emit(Instruction(kind: IkEval))
            if i < gene.children.len - 1:
              self.emit(Instruction(kind: IkPop))
        return
      of "import":
        self.compile_import(gene)
        return
      else:
        let s = `type`.str
        if s == "@":
          # Handle @ selector operator
          self.compile_at_selector(gene)
          return
        elif s.starts_with("."):
          # Check if this is a method definition (e.g., .fn, .ctor) or a method call
          if s == ".fn" or s == ".ctor":
            self.compile_method_definition(gene)
            return
          else:
            self.compile_method_call(gene)
            return
        elif s.starts_with("$"):
          # Handle $ prefixed operations
          case s:
            of "$with":
              self.compile_with(gene)
              return
            of "$tap":
              self.compile_tap(gene)
              return
            of "$parse":
              self.compile_parse(gene)
              return
            of "$caller_eval":
              self.compile_caller_eval(gene)
              return
            of "$set":
              self.compile_set(gene)
              return
            of "$render":
              self.compile_render(gene)
              return
            of "$emit":
              self.compile_emit(gene)
              return
            of "$if_main":
              self.compile_if_main(gene)
              return

  self.compile_gene_unknown(gene)

proc compile*(self: Compiler, input: Value) =
  let trace =
    if input.kind == VkGene:
      input.gene.trace
    else:
      self.current_trace()
  let should_push = input.kind == VkGene and not trace.is_nil
  if should_push:
    self.push_trace(trace)
  defer:
    if should_push:
      self.pop_trace()
  when DEBUG:
    echo "DEBUG compile: input.kind = ", input.kind
    if input.kind == VkGene:
      echo "  gene.type = ", input.gene.type
      if input.gene.type.kind == VkSymbol:
        echo "  gene.type.str = ", input.gene.type.str
  
  try:
    case input.kind:
      of VkInt, VkBool, VkNil, VkFloat, VkChar:
        self.compile_literal(input)
      of VkString:
        self.compile_literal(input) # TODO
      of VkSymbol:
        self.compile_symbol(input)
      of VkComplexSymbol:
        self.compile_complex_symbol(input)
      of VkQuote:
        self.quote_level.inc()
        self.compile(input.ref.quote)
        self.quote_level.dec()
      of VkStream:
        self.compile(input.ref.stream)
      of VkArray:
        self.compile_array(input)
      of VkMap:
        self.compile_map(input)
      of VkSelector:
        self.compile_literal(input)
      of VkGene:
        self.compile_gene(input)
      of VkUnquote:
        # Unquote values should be compiled as literals
        # They will be processed during template rendering
        self.compile_literal(input)
      of VkFunction:
        # Functions should be compiled as literals
        self.compile_literal(input)
      else:
        todo($input.kind)
  except CatchableError:
    if self.last_error_trace.is_nil:
      if not trace.is_nil:
        self.last_error_trace = trace
      else:
        self.last_error_trace = self.current_trace()
    raise

proc update_jumps(self: CompilationUnit) =
  # echo "update_jumps called, instruction count: ", self.instructions.len
  for i in 0..<self.instructions.len:
    let inst = self.instructions[i]
    case inst.kind
      of IkJump, IkJumpIfFalse, IkContinue, IkBreak, IkGeneStartDefault, IkRepeatInit, IkRepeatDecCheck:
        # Special case: -1 means no loop (for break/continue outside loops)
        if inst.kind in {IkBreak, IkContinue} and inst.arg0.int64 == -1:
          # Keep -1 as is for runtime checking
          discard
        else:
          # Labels are stored as int16 values converted to Value
          # Extract the int value and cast to Label (int16)
          # Extract the label from the NaN-boxed value
          # The label was stored as int16, so we need to extract just the low 16 bits
          when not defined(release):
            if inst.arg0.kind != VkInt:
              echo "ERROR: inst ", i, " (", inst.kind, ") arg0 is not an int: ", inst.arg0, " kind: ", inst.arg0.kind
          let label = (inst.arg0.int64.int and 0xFFFF).int16.Label
          let new_pc = self.find_label(label)
          # if inst.kind == IkGeneStartDefault:
          #   echo "  GeneStartDefault at ", i, ": label ", label, " -> PC ", new_pc
          self.instructions[i].arg0 = new_pc.to_value()
      of IkTryStart:
        # IkTryStart has arg0 for catch PC and optional arg1 for finally PC
        when not defined(release):
          if inst.arg0.kind != VkInt:
            echo "ERROR: inst ", i, " (", inst.kind, ") arg0 is not an int: ", inst.arg0, " kind: ", inst.arg0.kind
        let catch_label = (inst.arg0.int64.int and 0xFFFF).int16.Label
        let catch_pc = self.find_label(catch_label)
        self.instructions[i].arg0 = catch_pc.to_value()
        
        # Handle finally PC if present
        if inst.arg1 != 0:
          let finally_pc = self.find_label(inst.arg1.Label)
          self.instructions[i].arg1 = finally_pc.int32
      of IkJumpIfMatchSuccess:
        self.instructions[i].arg1 = self.find_label(inst.arg1.Label).int32
      else:
        discard

# Merge IkNoop instructions with following instructions before jump resolution
proc peephole_optimize(self: CompilationUnit) =
  # Apply peephole optimizations to convert common patterns to superinstructions
  self.ensure_trace_capacity()
  let old_traces = self.instruction_traces
  var new_instructions: seq[Instruction] = @[]
  var new_traces: seq[SourceTrace] = @[]
  var i = 0
  
  while i < self.instructions.len:
    let inst = self.instructions[i]
    let trace = if i < old_traces.len: old_traces[i] else: nil
    
    # Check for common patterns and replace with superinstructions
    if i + 2 < self.instructions.len:
      let next1 = self.instructions[i + 1]
      let next2 = self.instructions[i + 2]
      
      # Pattern: VAR_RESOLVE; ADD; VAR_ASSIGN -> IkAddLocal
      if inst.kind == IkVarResolve and next1.kind == IkAdd and next2.kind == IkVarAssign:
        if inst.arg0 == next2.arg0:  # Same variable
          new_instructions.add(Instruction(
            kind: IkAddLocal,
            arg0: inst.arg0,
            label: inst.label
          ))
          new_traces.add(trace)
          i += 3
          continue
    
    if i + 1 < self.instructions.len:
      let next1 = self.instructions[i + 1]
      
      # Pattern: INC_VAR (VAR_RESOLVE; ADD 1; VAR_ASSIGN)
      if inst.kind == IkVarResolve and next1.kind == IkAddValue:
        if i + 2 < self.instructions.len and self.instructions[i + 2].kind == IkVarAssign:
          if next1.arg0.kind == VkInt and next1.arg0.int64 == 1:
            new_instructions.add(Instruction(
              kind: IkIncLocal,
              arg0: inst.arg0,
              label: inst.label
            ))
            new_traces.add(trace)
            i += 3
            continue
      
      # Pattern: RETURN NIL
      if inst.kind == IkPushNil and next1.kind == IkEnd:
        new_instructions.add(Instruction(
          kind: IkReturnNil,
          label: inst.label
        ))
        new_traces.add(trace)
        i += 2
        continue
    
    # No pattern matched, keep original instruction
    new_instructions.add(inst)
    new_traces.add(trace)
    i += 1
  
  self.instructions = new_instructions
  self.instruction_traces = new_traces

proc optimize_noops(self: CompilationUnit) =
  # Move labels from Noop instructions to the next real instruction
  # This must be done BEFORE jump resolution
  self.ensure_trace_capacity()
  let old_traces = self.instruction_traces
  var new_instructions: seq[Instruction] = @[]
  var new_traces: seq[SourceTrace] = @[]
  var pending_labels: seq[Label] = @[]
  var removed_count = 0

  for i, inst in self.instructions:
    let trace = if i < old_traces.len: old_traces[i] else: nil
    if inst.kind == IkNoop:
      if inst.label != 0:
        pending_labels.add(inst.label)
        removed_count.inc()
      elif inst.arg0.kind != VkNil:
        var modified_inst = inst
        if pending_labels.len > 0 and inst.label == 0:
          modified_inst.label = pending_labels[0]
          pending_labels.delete(0)
        new_instructions.add(modified_inst)
        new_traces.add(trace)
      else:
        removed_count.inc()
    else:
      var modified_inst = inst
      if pending_labels.len > 0 and inst.label == 0:
        modified_inst.label = pending_labels[0]
        pending_labels.delete(0)
      new_instructions.add(modified_inst)
      new_traces.add(trace)

      for label in pending_labels:
        new_instructions.add(Instruction(kind: IkNoop, label: label))
        new_traces.add(nil)
      pending_labels = @[]

  for label in pending_labels:
    new_instructions.add(Instruction(kind: IkNoop, label: label))
    new_traces.add(nil)

  self.instructions = new_instructions
  self.instruction_traces = new_traces


proc compile*(input: seq[Value], eager_functions: bool): CompilationUnit =
  let self = Compiler(output: new_compilation_unit(), tail_position: false, eager_functions: eager_functions, trace_stack: @[])
  self.emit(Instruction(kind: IkStart))
  self.start_scope()

  for i, v in input:
    self.last_error_trace = nil
    try:
      self.compile(v)
    except CatchableError as e:
      var trace = self.last_error_trace
      if trace.is_nil and v.kind == VkGene:
        trace = v.gene.trace
      let location = trace_location(trace)
      let message = if location.len > 0: location & ": " & e.msg else: e.msg
      raise new_exception(types.Exception, message)
    if i < input.len - 1:
      self.emit(Instruction(kind: IkPop))

  self.end_scope()
  self.emit(Instruction(kind: IkEnd))
  self.output.optimize_noops()  # Optimize BEFORE resolving jumps
  # self.output.peephole_optimize()  # Apply peephole optimizations (temporarily disabled)
  self.output.update_jumps()
  result = self.output

proc compile*(input: seq[Value]): CompilationUnit =
  compile(input, false)

proc compile*(f: Function, eager_functions: bool) =
  if f.body_compiled != nil:
    return

  var self = Compiler(output: new_compilation_unit(), tail_position: false, eager_functions: eager_functions, trace_stack: @[])
  self.emit(Instruction(kind: IkStart))
  self.scope_trackers.add(f.scope_tracker)

  # generate code for arguments
  for i, m in f.matcher.children:
    self.scope_tracker.mappings[m.name_key] = i.int16
    let label = new_label()
    self.emit(Instruction(
      kind: IkJumpIfMatchSuccess,
      arg0: i.to_value(),
      arg1: label,
    ))
    if m.default_value != nil:
      self.compile(m.default_value)
      self.add_scope_start()
      self.emit(Instruction(kind: IkVar, arg0: m.name_key.to_value()))
      self.emit(Instruction(kind: IkPop))
    else:
      self.emit(Instruction(kind: IkThrow))
    self.emit(Instruction(kind: IkNoop, label: label))

  # Mark that we're in tail position for the function body
  self.tail_position = true
  self.compile(f.body)
  self.tail_position = false

  self.end_scope()
  self.emit(Instruction(kind: IkEnd))
  self.output.optimize_noops()  # Optimize BEFORE resolving jumps
  self.output.peephole_optimize()  # Apply peephole optimizations
  self.output.update_jumps()
  self.output.kind = CkFunction
  f.body_compiled = self.output
  f.body_compiled.matcher = f.matcher

proc compile*(f: Function) =
  compile(f, false)

proc compile*(b: Block, eager_functions: bool) =
  if b.body_compiled != nil:
    return

  var self = Compiler(output: new_compilation_unit(), tail_position: false, eager_functions: eager_functions, trace_stack: @[])
  self.emit(Instruction(kind: IkStart))
  self.scope_trackers.add(b.scope_tracker)

  # generate code for arguments
  for i, m in b.matcher.children:
    self.scope_tracker.mappings[m.name_key] = i.int16
    let label = new_label()
    self.emit(Instruction(
      kind: IkJumpIfMatchSuccess,
      arg0: i.to_value(),
      arg1: label,
    ))
    if m.default_value != nil:
      self.compile(m.default_value)
      self.add_scope_start()
      self.emit(Instruction(kind: IkVar, arg0: m.name_key.to_value()))
      self.emit(Instruction(kind: IkPop))
    else:
      self.emit(Instruction(kind: IkThrow))
    self.emit(Instruction(kind: IkNoop, label: label))

  self.compile(b.body)

  self.end_scope()
  self.emit(Instruction(kind: IkEnd))
  self.output.optimize_noops()  # Optimize BEFORE resolving jumps
  self.output.update_jumps()
  b.body_compiled = self.output
  b.body_compiled.matcher = b.matcher

proc compile*(b: Block) =
  compile(b, false)

proc compile*(f: CompileFn, eager_functions: bool) =
  if f.body_compiled != nil:
    return

  let self = Compiler(output: new_compilation_unit(), tail_position: false, eager_functions: eager_functions, trace_stack: @[])
  self.emit(Instruction(kind: IkStart))
  self.scope_trackers.add(f.scope_tracker)

  # generate code for arguments
  for i, m in f.matcher.children:
    self.scope_tracker.mappings[m.name_key] = i.int16
    let label = new_label()
    self.emit(Instruction(
      kind: IkJumpIfMatchSuccess,
      arg0: i.to_value(),
      arg1: label,
    ))
    if m.default_value != nil:
      self.compile(m.default_value)
      self.add_scope_start()
      self.emit(Instruction(kind: IkVar, arg0: m.name_key.to_value()))
      self.emit(Instruction(kind: IkPop))
    else:
      self.emit(Instruction(kind: IkThrow))
    self.emit(Instruction(kind: IkNoop, label: label))

  # Mark that we're in tail position for the function body
  self.tail_position = true
  self.compile(f.body)
  self.tail_position = false

  self.end_scope()
  self.emit(Instruction(kind: IkEnd))
  self.output.optimize_noops()  # Optimize BEFORE resolving jumps
  self.output.update_jumps()
  f.body_compiled = self.output
  f.body_compiled.kind = CkCompileFn
  f.body_compiled.matcher = f.matcher

proc compile*(f: CompileFn) =
  compile(f, false)

proc compile_with(self: Compiler, gene: ptr Gene) =
  # ($with value body...)
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
  let if_gene = new_gene("if".to_symbol_value())
  if_gene.props[COND_KEY.to_key()] = cond_symbol

  let then_stream = new_stream_value()
  if gene.children.len > 0:
    for child in gene.children:
      then_stream.ref.stream.add(child)
  else:
    then_stream.ref.stream.add(NIL)
  if_gene.props[THEN_KEY.to_key()] = then_stream

  let else_stream = new_stream_value()
  else_stream.ref.stream.add(NIL)
  if_gene.props[ELSE_KEY.to_key()] = else_stream

  self.compile_if(if_gene)

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

proc compile_async(self: Compiler, gene: ptr Gene) =
  # (async expr)
  if gene.children.len != 1:
    not_allowed("async expects exactly 1 argument")
  
  # We need to wrap the expression evaluation in exception handling
  # Generate: try expr catch e -> future.fail(e)
  
  # Push a marker for the async block
  self.emit(Instruction(kind: IkAsyncStart))
  
  # Compile the expression
  self.compile(gene.children[0])
  
  # End async block - this will handle exceptions and wrap in future
  self.emit(Instruction(kind: IkAsyncEnd))

proc compile_await(self: Compiler, gene: ptr Gene) =
  # (await future) or (await future1 future2 ...)
  if gene.children.len == 0:
    not_allowed("await expects at least 1 argument")
  
  if gene.children.len == 1:
    # Single future
    self.compile(gene.children[0])
    self.emit(Instruction(kind: IkAwait))
  else:
    # Multiple futures - await each and collect results
    self.emit(Instruction(kind: IkArrayStart))
    for child in gene.children:
      self.compile(child)
      self.emit(Instruction(kind: IkAwait))
      # Awaited value is on stack, will be collected by IkArrayEnd
    self.emit(Instruction(kind: IkArrayEnd))

proc compile_spawn(self: Compiler, gene: ptr Gene) =
  # (spawn expr) - spawn thread to execute expression
  # (spawn return: expr) - spawn and return future
  if gene.children.len == 0:
    not_allowed("spawn expects at least 1 argument")

  var return_value = false
  var expr_idx = 0

  # Check for return: keyword argument
  if gene.children.len == 2:
    let first = gene.children[0]
    if first.kind == VkSymbol and first.str == "return:":
      return_value = true
      expr_idx = 1

  let expr = gene.children[expr_idx]

  # Pass the Gene AST as-is to the thread (it will compile locally)
  # This avoids sharing CompilationUnit refs across threads
  self.emit(Instruction(kind: IkPushValue, arg0: cast[Value](expr)))

  # Push return_value flag
  self.emit(Instruction(kind: IkPushValue, arg0: if return_value: TRUE else: FALSE))

  # Emit spawn instruction
  self.emit(Instruction(kind: IkSpawnThread))

proc compile_yield(self: Compiler, gene: ptr Gene) =
  # (yield value) - suspend generator and return value
  if gene.children.len == 0:
    # Yield without argument yields nil
    self.emit(Instruction(kind: IkPushNil))
  elif gene.children.len == 1:
    # Yield single value
    self.compile(gene.children[0])
  else:
    not_allowed("yield expects 0 or 1 argument")
  
  self.emit(Instruction(kind: IkYield))

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
  for child in gene.children:
    case child.kind
    of VkString, VkSymbol, VkInt:
      segments.add(child)
    else:
      not_allowed("Unsupported selector segment type: " & $child.kind)

  let selector_value = new_selector_value(segments)
  self.emit(Instruction(kind: IkPushValue, arg0: selector_value))

proc compile_set(self: Compiler, gene: ptr Gene) =
  # ($set target @property value)
  # ($set a @test 1)
  if gene.children.len != 3:
    not_allowed("$set expects exactly 3 arguments")
  
  # Compile the target
  self.compile(gene.children[0])
  
  let selector_arg = gene.children[1]
  var segments: seq[Value] = @[]

  if selector_arg.kind == VkSymbol and selector_arg.str.startsWith("@") and selector_arg.str.len > 1:
    let prop_name = selector_arg.str[1..^1]
    for part in prop_name.split("/"):
      if part.len == 0:
        not_allowed("$set selector segment cannot be empty")
      try:
        let index = parseInt(part)
        segments.add(index.to_value())
      except ValueError:
        segments.add(part.to_value())
  elif selector_arg.kind == VkGene and selector_arg.gene.type == "@".to_symbol_value():
    if selector_arg.gene.children.len == 0:
      not_allowed("$set selector requires at least one segment")
    for child in selector_arg.gene.children:
      case child.kind
      of VkString, VkSymbol, VkInt:
        segments.add(child)
      else:
        not_allowed("Unsupported selector segment type: " & $child.kind)
  else:
    not_allowed("$set expects a selector (@property) as second argument")

  if segments.len != 1:
    not_allowed("$set selector must have exactly one property")

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

proc compile_import(self: Compiler, gene: ptr Gene) =
  # (import a b from "module")
  # (import from "module" a b)
  # (import a:alias b from "module")
  # (import n/f from "module")
  # (import n/[one two] from "module")
  
  # echo "DEBUG: compile_import called for ", gene
  # echo "DEBUG: gene.children = ", gene.children
  # echo "DEBUG: gene.props = ", gene.props
  
  # Compile a gene value for the import, but with "import" as a symbol type
  self.emit(Instruction(kind: IkGeneStart))
  self.emit(Instruction(kind: IkPushValue, arg0: "import".to_symbol_value()))
  self.emit(Instruction(kind: IkGeneSetType))
  
  # Compile the props
  for k, v in gene.props:
    self.emit(Instruction(kind: IkPushValue, arg0: v))
    self.emit(Instruction(kind: IkGeneSetProp, arg0: k))
  
  # Compile the children - they should be treated as quoted values
  for child in gene.children:
    # Import arguments are data, not code to execute
    # So compile them as literal values
    case child.kind:
    of VkSymbol, VkString:
      self.emit(Instruction(kind: IkPushValue, arg0: child))
    of VkComplexSymbol:
      # Handle n/f syntax
      self.emit(Instruction(kind: IkPushValue, arg0: child))
    of VkArray:
      # Handle [one two] part of n/[one two]
      self.emit(Instruction(kind: IkPushValue, arg0: child))
    of VkGene:
      # Handle complex forms like a:alias or n/[a b]
      self.compile_gene_default(child.gene)
    else:
      self.compile(child)
    self.emit(Instruction(kind: IkGeneAddChild))
  
  self.emit(Instruction(kind: IkGeneEnd))
  self.emit(Instruction(kind: IkImport))

proc compile_init*(input: Value): CompilationUnit =
  let self = Compiler(output: new_compilation_unit(), tail_position: false, trace_stack: @[])
  self.output.skip_return = true
  self.emit(Instruction(kind: IkStart))
  self.start_scope()

  self.last_error_trace = nil
  try:
    self.compile(input)
  except CatchableError as e:
    var trace = self.last_error_trace
    if trace.is_nil and input.kind == VkGene:
      trace = input.gene.trace
    let location = trace_location(trace)
    let message = if location.len > 0: location & ": " & e.msg else: e.msg
    raise new_exception(types.Exception, message)

  self.end_scope()
  self.emit(Instruction(kind: IkEnd))
  self.output.optimize_noops()  # Optimize BEFORE resolving jumps
  # self.output.peephole_optimize()  # Apply peephole optimizations (temporarily disabled)
  self.output.update_jumps()
  result = self.output

proc replace_chunk*(self: var CompilationUnit, start_pos: int, end_pos: int, replacement: sink seq[Instruction]) =
  let replacement_count = replacement.len
  self.replace_traces_range(start_pos, end_pos, replacement_count)
  self.instructions[start_pos..end_pos] = replacement

# Parse and compile functions - unified interface for future streaming implementation
proc parse_and_compile*(input: string, filename = "<input>"): CompilationUnit =
  ## Parse and compile Gene code from a string with streaming compilation
  ## Parse one item -> compile immediately -> repeat
  
  var parser = new_parser()
  var stream = new_string_stream(input)
  parser.open(stream, filename)
  defer: parser.close()
  
  # Initialize compilation
  let self = Compiler(output: new_compilation_unit(), tail_position: false, trace_stack: @[])
  self.emit(Instruction(kind: IkStart))
  self.start_scope()
  
  var is_first = true
  
  # Streaming compilation: parse one -> compile one -> repeat
  try:
    while true:
      let node = parser.read()
      if node != PARSER_IGNORE:
        # Pop previous result before compiling next item (except for first)
        if not is_first:
          self.emit(Instruction(kind: IkPop))

        self.last_error_trace = nil
        try:
          # Compile current item
          self.compile(node)
          is_first = false
        except CatchableError as e:
          var trace = self.last_error_trace
          if trace.is_nil and node.kind == VkGene:
            trace = node.gene.trace
          let location = trace_location(trace)
          let message = if location.len > 0: location & ": " & e.msg else: e.msg
          raise new_exception(types.Exception, message)
  except ParseEofError:
    # Expected end of input
    discard
  
  # Finalize compilation
  self.end_scope()
  self.emit(Instruction(kind: IkEnd))
  self.output.optimize_noops()
  self.output.update_jumps()
  self.output.ensure_trace_capacity()
  self.output.trace_root = parser.trace_root
  
  return self.output


# Compile methods for Function, Macro, Block, and CompileFn are defined above
