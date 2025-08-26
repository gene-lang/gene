import tables, strutils, strformat, algorithm
import times, os

import ./types
import ./parser
import ./compiler
import ./vm/args
import ./vm/module
import ./vm/arithmetic

when not defined(noExtensions):
  import ./vm/extension

const DEBUG_VM = false

# Forward declarations from vm/core
proc init_gene_namespace*()
proc register_io_functions*()

proc enter_function(self: VirtualMachine, name: string) {.inline.} =
  if self.profiling:
    let start_time = cpuTime()
    self.profile_stack.add((name, start_time))
    
proc exit_function(self: VirtualMachine) {.inline.} =
  if self.profiling and self.profile_stack.len > 0:
    let (name, start_time) = self.profile_stack[^1]
    self.profile_stack.del(self.profile_stack.len - 1)
    
    let end_time = cpuTime()
    let elapsed = end_time - start_time
    
    # Update or create profile entry
    if name notin self.profile_data:
      self.profile_data[name] = FunctionProfile(
        name: name,
        call_count: 0,
        total_time: 0.0,
        self_time: 0.0,
        min_time: elapsed,
        max_time: elapsed
      )
    
    var profile = self.profile_data[name]
    profile.call_count.inc()
    profile.total_time += elapsed
    
    # Update min/max
    if elapsed < profile.min_time:
      profile.min_time = elapsed
    if elapsed > profile.max_time:
      profile.max_time = elapsed
    
    # Calculate self time (subtract child call times)
    var child_time = 0.0
    for i in countdown(self.profile_stack.len - 1, 0):
      if self.profile_stack[i].name == name:
        break
      # This is a simplification - proper self time calculation is more complex
    profile.self_time = profile.total_time  # For now, just use total
    
    self.profile_data[name] = profile

proc print_profile*(self: VirtualMachine) =
  if not self.profiling or self.profile_data.len == 0:
    echo "No profiling data available"
    return
  
  echo "\n=== Function Profile Report ==="
  echo "Function                       Calls      Total(ms)       Avg(μs)     Min(μs)     Max(μs)"
  echo repeat('-', 94)
  
  # Sort by total time descending
  var profiles: seq[FunctionProfile] = @[]
  for name, profile in self.profile_data:
    profiles.add(profile)
  
  profiles.sort do (a, b: FunctionProfile) -> int:
    if a.total_time > b.total_time: -1
    elif a.total_time < b.total_time: 1
    else: 0
  
  for profile in profiles:
    let total_ms = profile.total_time * 1000.0
    let avg_us = if profile.call_count > 0: (profile.total_time * 1_000_000.0) / profile.call_count.float else: 0.0
    let min_us = profile.min_time * 1_000_000.0
    let max_us = profile.max_time * 1_000_000.0
    
    # Use manual formatting for now
    var name_str = profile.name
    if name_str.len > 30:
      name_str = name_str[0..26] & "..."
    while name_str.len < 30:
      name_str = name_str & " "
    
    echo fmt"{name_str} {profile.call_count:10} {total_ms:12.3f} {avg_us:12.3f} {min_us:10.3f} {max_us:10.3f}"
  
  echo "\nTotal functions profiled: ", self.profile_data.len

proc print_instruction_profile*(self: VirtualMachine) =
  if not self.instruction_profiling:
    echo "No instruction profiling data available"
    return
  
  echo "\n=== Instruction Profile Report ==="
  echo "Instruction              Count        Total(ms)     Avg(ns)    Min(ns)    Max(ns)     %Time"
  echo repeat('-', 94)
  
  # Calculate total time
  var total_time = 0.0
  for kind in InstructionKind:
    if self.instruction_profile[kind].count > 0:
      total_time += self.instruction_profile[kind].total_time
  
  # Collect and sort instructions by total time
  type InstructionStat = tuple[kind: InstructionKind, profile: InstructionProfile]
  var stats: seq[InstructionStat] = @[]
  for kind in InstructionKind:
    if self.instruction_profile[kind].count > 0:
      stats.add((kind, self.instruction_profile[kind]))
  
  stats.sort do (a, b: InstructionStat) -> int:
    if a.profile.total_time > b.profile.total_time: -1
    elif a.profile.total_time < b.profile.total_time: 1
    else: 0
  
  # Print top instructions
  for stat in stats:
    let kind = stat.kind
    let profile = stat.profile
    let total_ms = profile.total_time * 1000.0
    let avg_ns = if profile.count > 0: (profile.total_time * 1_000_000_000.0) / profile.count.float else: 0.0
    let min_ns = profile.min_time * 1_000_000_000.0
    let max_ns = profile.max_time * 1_000_000_000.0
    let percent = if total_time > 0: (profile.total_time / total_time) * 100.0 else: 0.0
    
    # Format instruction name
    var name_str = $kind
    if name_str.startswith("Ik"):
      name_str = name_str[2..^1]  # Remove "Ik" prefix
    if name_str.len > 24:
      name_str = name_str[0..20] & "..."
    while name_str.len < 24:
      name_str = name_str & " "
    
    echo fmt"{name_str} {profile.count:12} {total_ms:12.3f} {avg_ns:10.1f} {min_ns:9.1f} {max_ns:9.1f} {percent:8.2f}%"
  
  echo fmt"Total time: {total_time * 1000.0:.3f} ms"
  echo "Instructions profiled: ", stats.len

# Forward declaration
proc exec*(self: VirtualMachine): Value

proc render_template(self: VirtualMachine, tpl: Value): Value =
  # Render a template by recursively processing quote/unquote values
  case tpl.kind:
    of VkQuote:
      # A quoted value - render its contents
      return self.render_template(tpl.ref.quote)
    
    of VkUnquote:
      # An unquoted value - evaluate it in the current context
      let expr = tpl.ref.unquote
      let discard_result = tpl.ref.unquote_discard
      
      # For now, evaluate simple cases directly without creating new frames
      # TODO: Implement full expression evaluation
      var r: Value = NIL
      
      case expr.kind:
        of VkSymbol:
          # Look up the symbol in the current scope using the scope tracker
          let key = expr.str.to_key()
          
          # Use the scope tracker to find the variable
          let var_index = self.frame.scope.tracker.locate(key)
          
          if var_index.local_index >= 0:
            # Found in scope - navigate to the correct scope
            var scope = self.frame.scope
            var parent_index = var_index.parent_index
            
            while parent_index > 0 and scope != nil:
              parent_index.dec()
              scope = scope.parent
            
            if scope != nil and var_index.local_index < scope.members.len:
              r = scope.members[var_index.local_index]
            else:
              # Not found, default to symbol
              r = expr
          else:
            # Not in scope, check namespace
            if self.frame.ns.members.hasKey(key):
              r = self.frame.ns.members[key]
            else:
              # Default to the symbol itself
              r = expr
            
        of VkGene:
          # For gene expressions, recursively render the parts
          let gene = expr.gene
          let rendered_type = self.render_template(gene.type)
          
          # Create a new gene with rendered parts
          let new_gene = new_gene(rendered_type)
          
          # Render properties
          for k, v in gene.props:
            new_gene.props[k] = self.render_template(v)
          
          # Render children
          for child in gene.children:
            new_gene.children.add(self.render_template(child))
          
          # For now, return the rendered gene without evaluating
          # TODO: Implement full expression evaluation
          r = new_gene.to_gene_value()
            
        of VkInt, VkFloat, VkBool, VkString, VkChar:
          # Literal values pass through unchanged
          r = expr
        else:
          # For other types, recursively render
          r = self.render_template(expr)
      
      if discard_result:
        # %_ means discard the r
        return NIL
      else:
        return r
    
    of VkGene:
      # Recursively render gene expressions
      let gene = tpl.gene
      let new_gene = new_gene(self.render_template(gene.type))
      
      # Render properties
      for k, v in gene.props:
        new_gene.props[k] = self.render_template(v)
      
      # Render children
      for child in gene.children:
        let rendered = self.render_template(child)
        if rendered.kind == VkExplode:
          # Handle %_ spread operator
          if rendered.ref.explode_value.kind == VkArray:
            for item in rendered.ref.explode_value.ref.arr:
              new_gene.children.add(item)
        else:
          new_gene.children.add(rendered)
      
      return new_gene.to_gene_value()
    
    of VkArray:
      # Recursively render array elements
      let new_arr = new_ref(VkArray)
      for item in tpl.ref.arr:
        let rendered = self.render_template(item)
        # Skip NIL values that come from %_ (unquote discard)
        if rendered.kind == VkNil and item.kind == VkUnquote and item.ref.unquote_discard:
          continue
        elif rendered.kind == VkExplode:
          # Handle spread in arrays
          if rendered.ref.explode_value.kind == VkArray:
            for sub_item in rendered.ref.explode_value.ref.arr:
              new_arr.arr.add(sub_item)
        else:
          new_arr.arr.add(rendered)
      return new_arr.to_ref_value()
    
    of VkMap:
      # Recursively render map values
      let new_map = new_ref(VkMap)
      for k, v in tpl.ref.map:
        new_map.map[k] = self.render_template(v)
      return new_map.to_ref_value()
    
    else:
      # Other values pass through unchanged
      return tpl

proc exec*(self: VirtualMachine): Value =
  # Initialize gene namespace if not already done
  init_gene_namespace()
  
  var pc = 0
  if pc >= self.cu.instructions.len:
    raise new_exception(types.Exception, "Empty compilation unit")
  var inst = self.cu.instructions[pc].addr

  when not defined(release):
    var indent = ""

  # Hot VM execution loop - disable checks for maximum performance
  {.push boundChecks: off, overflowChecks: off, nilChecks: off, assertions: off.}
  while true:
    when not defined(release):
      if self.trace:
        if inst.kind == IkStart: # This is part of INDENT_LOGIC
          indent &= "  "
        # self.print_stack()
        echo fmt"{indent}{pc:04X} {inst[]}"
    
    # Instruction profiling - only declare variables when needed
    when not defined(release):
      var inst_start_time: float64
      var inst_kind_for_profiling: InstructionKind
      if self.instruction_profiling:
        inst_start_time = cpuTime()
        inst_kind_for_profiling = inst.kind  # Save it now, before execution changes anything

    {.computedGoto.}
    case inst.kind:
      of IkNoop:
        when not defined(release):
          if self.trace:
            echo fmt"{indent}     [Noop at PC {pc:04X}, label: {inst.label.int:04X}]"
        discard
      
      of IkData:
        # IkData provides data for the previous instruction
        # It should not be executed directly - the previous instruction should consume it
        when not defined(release):
          if self.trace:
            echo fmt"{indent}     [Data at PC {pc:04X}, skipping]"
        discard

      of IkStart:
        when not defined(release):
          if not self.trace: # This is part of INDENT_LOGIC
            indent &= "  "
        # if self.cu.matcher != nil:
        #   self.handle_args(self.cu.matcher, self.frame.args)

      of IkEnd:
        {.push checks: off}
        when not defined(release):
          if indent.len >= 2:
            indent.delete(indent.len-2..indent.len-1)
        # TODO: validate that there is only one value on the stack
        let v = self.frame.current()
        if self.frame.caller_frame == nil:
          return v
        else:
          if self.cu.kind == CkCompileFn:
            # Replace the caller's instructions with what's returned
            # Point the caller's pc to the first of the new instructions
            var cu = self.frame.caller_address.cu
            let end_pos = self.frame.caller_address.pc
            let caller_instr = self.frame.caller_address.cu.instructions[end_pos]
            let start_pos = caller_instr.arg0.int64.int
            var new_instructions: seq[Instruction] = @[]
            for item in v.ref.arr:
              case item.kind:
                of VkInstruction:
                  new_instructions.add(item.ref.instr)
                of VkArray:
                  for item2 in item.ref.arr:
                    new_instructions.add(item2.ref.instr)
                else:
                  todo($item.kind)
            cu.replace_chunk(start_pos, end_pos, new_instructions)
            self.cu = self.frame.caller_address.cu
            pc = start_pos
            inst = self.cu.instructions[pc].addr
            self.frame.update(self.frame.caller_frame)
            self.frame.ref_count.dec()  # The frame's ref_count was incremented unnecessarily.
            continue
          elif self.cu.kind == CkMacro:
            # Return to caller who will handle macro expansion
            self.cu = self.frame.caller_address.cu
            pc = self.frame.caller_address.pc
            inst = self.cu.instructions[pc].addr
            self.frame.update(self.frame.caller_frame)
            self.frame.ref_count.dec()
            # Push the macro result for the caller to process
            self.frame.push(v)
            continue

          let skip_return = self.cu.skip_return
          # Check if we're returning from an async function before updating frame
          var result_val = v
          if self.frame.kind == FkFunction and self.frame.target.kind == VkFunction:
            let f = self.frame.target.ref.fn
            if f.async:
              # Wrap the return value in a future
              let future_val = new_future_value()
              let future_obj = future_val.ref.future
              future_obj.complete(result_val)
              result_val = future_val
          
          # Profile function exit
          if self.profiling:
            self.exit_function()
          
          self.cu = self.frame.caller_address.cu
          pc = self.frame.caller_address.pc
          inst = self.cu.instructions[pc].addr
          self.frame.update(self.frame.caller_frame)
          self.frame.ref_count.dec()  # The frame's ref_count was incremented unnecessarily.
          if not skip_return:
            self.frame.push(result_val)
          continue
        {.pop.}

      of IkScopeStart:
        if inst.arg0.kind == VkNil:
          # For GIR files, create a new scope with empty tracker
          let tracker = new_scope_tracker()
          self.frame.scope = new_scope(tracker, self.frame.scope)
        elif inst.arg0.kind == VkScopeTracker:
          self.frame.scope = new_scope(inst.arg0.ref.scope_tracker, self.frame.scope)
        else:
          not_allowed("IkScopeStart: expected ScopeTracker or Nil, got " & $inst.arg0.kind)
      of IkScopeEnd:
        var old_scope = self.frame.scope
        self.frame.scope = self.frame.scope.parent
        old_scope.free()

      of IkVar:
        {.push checks: off.}
        let index = inst.arg0.int64.int
        let value = self.frame.pop()  # Pop the value from the stack
        if self.frame.scope.isNil:
          not_allowed("IkVar: scope is nil")
        # Ensure the scope has enough space for the index
        while self.frame.scope.members.len <= index:
          self.frame.scope.members.add(NIL)
        self.frame.scope.members[index] = value
        
        # Variables are now stored in scope, not in namespace self
        # This simplifies the design
        
        # Push the value as the result of var
        self.frame.push(value)
        {.pop.}

      of IkVarValue:
        {.push checks: off}
        let index = inst.arg1.int
        let value = inst.arg0
        # Ensure the scope has enough space for the index
        while self.frame.scope.members.len <= index:
          self.frame.scope.members.add(NIL)
        self.frame.scope.members[index] = value
        
        # Variables are now stored in scope, not in namespace self
        # This simplifies the design
        
        # Also push the value to the stack (like IkVar)
        self.frame.push(value)
        {.pop.}

      of IkVarResolve:
        {.push checks: off}
        # when not defined(release):
        #   if self.trace:
        #     echo fmt"IkVarResolve: arg0={inst.arg0}, arg0.int64.int={inst.arg0.int64.int}, scope.members.len={self.frame.scope.members.len}"
        if self.frame.scope.isNil:
          raise new_exception(types.Exception, "IkVarResolve: scope is nil")
        let index = inst.arg0.int64.int
        if index >= self.frame.scope.members.len:
          raise new_exception(types.Exception, fmt"IkVarResolve: index {index} >= scope.members.len {self.frame.scope.members.len}")
        self.frame.push(self.frame.scope.members[index])
        {.pop.}

      of IkVarResolveInherited:
        var parent_index = inst.arg1.int32
        var scope = self.frame.scope
        while parent_index > 0:
          parent_index.dec()
          scope = scope.parent
        {.push checks: off}
        self.frame.push(scope.members[inst.arg0.int64.int])
        {.pop.}

      of IkVarAssign:
        {.push checks: off}
        let value = self.frame.current()
        self.frame.scope.members[inst.arg0.int64.int] = value
        {.pop.}

      of IkVarAssignInherited:
        {.push checks: off}
        let value = self.frame.current()
        {.pop.}
        var scope = self.frame.scope
        var parent_index = inst.arg1.int32
        while parent_index > 0:
          parent_index.dec()
          scope = scope.parent
        {.push checks: off}
        scope.members[inst.arg0.int64.int] = value
        {.pop.}

      of IkAssign:
        todo($IkAssign)
        # let value = self.frame.current()
        # Find the namespace where the member is defined and assign it there

      of IkCallDirect:
        {.push checks: off}
        # Fast direct function call - function is in arg0, args already on stack
        let target = inst.arg0
        if target.kind != VkFunction:
          not_allowed("IkCallDirect requires a function, got " & $target.kind)
        
        let f = target.ref.fn
        
        # Check if this is a generator function
        if f.is_generator:
          # Collect and discard arguments for now (generators will handle them on first .next)
          let arg_count = inst.arg1.int64.int
          var args_gene = new_gene(NIL)
          for i in 0..<arg_count:
            args_gene.children.insert(self.frame.pop(), 0)
          
          # Create generator instance
          var gen = new_ref(VkGenerator)
          var genObj = new(GeneratorObj)
          genObj.function = f
          genObj.state = GsPending
          genObj.frame = nil
          genObj.pc = 0
          genObj.scope = nil
          genObj.stack = @[]
          genObj.done = false
          genObj.has_peeked = false
          genObj.peeked_value = NIL
          GC_ref(genObj)  # Prevent GC from collecting
          gen.generator = cast[pointer](genObj)
          # Store arguments in the generator for later processing
          genObj.stack = args_gene.children  # Save args for when generator starts
          self.frame.push(gen.to_ref_value())
          pc.inc()
          inst = self.cu.instructions[pc].addr
          continue
        
        # Normal function call
        if f.body_compiled == nil:
          f.compile()
        
        # Collect arguments from stack (they were pushed in reverse order)
        let arg_count = inst.arg1.int64.int
        var args_gene = new_gene(NIL)
        for i in 0..<arg_count:
          args_gene.children.insert(self.frame.pop(), 0)
        
        # Create new frame
        var scope: Scope
        if f.matcher.is_empty():
          scope = f.parent_scope
        else:
          scope = new_scope(f.scope_tracker, f.parent_scope)
        
        var new_frame = new_frame()
        new_frame.kind = FkFunction
        new_frame.target = target
        new_frame.scope = scope
        new_frame.args = args_gene.to_gene_value()
        new_frame.caller_frame = self.frame
        self.frame.ref_count.inc()
        new_frame.caller_address = Address(cu: self.cu, pc: pc + 1)
        new_frame.ns = f.ns
        
        # Process arguments if needed
        if not f.matcher.is_empty():
          process_args(f.matcher, new_frame.args, new_frame.scope)
        
        # Profile function entry
        if self.profiling:
          let func_name = if f.name != "": f.name else: "<anonymous>"
          self.enter_function(func_name)
        
        # Switch to new frame and CU
        self.frame = new_frame
        self.cu = f.body_compiled
        pc = 0
        inst = self.cu.instructions[pc].addr
        continue
        {.pop}

      of IkTailCall:
        {.push checks: off}
        # IkTailCall works like IkGeneEnd but optimizes tail calls to the same function
        let value = self.frame.current()
        case value.kind:
          of VkFrame:
            let new_frame = value.ref.frame
            case new_frame.kind:
              of FkFunction:
                let f = new_frame.target.ref.fn
                if f.body_compiled == nil:
                  f.compile()
                
                # Check if this is a tail call to the same function
                if self.frame.kind == FkFunction and 
                   self.frame.target.kind == VkFunction and
                   self.frame.target.ref.fn == f:
                  # Tail call optimization - reuse current frame
                  # Pop the VkFrame value from the stack
                  discard self.frame.pop()
                  
                  # Update arguments and scope in place
                  self.frame.args = new_frame.args
                  
                  # Reset scope
                  if f.matcher.is_empty():
                    self.frame.scope = f.parent_scope
                  else:
                    self.frame.scope = new_scope(f.scope_tracker, f.parent_scope)
                    # Process arguments
                    if self.frame.current_method != nil:
                      # Method call - create args without self
                      var method_args = new_gene(NIL)
                      if self.frame.args.kind == VkGene and self.frame.args.gene.children.len > 1:
                        for i in 1..<self.frame.args.gene.children.len:
                          method_args.children.add(self.frame.args.gene.children[i])
                      process_args(f.matcher, method_args.to_gene_value(), self.frame.scope)
                    else:
                      process_args(f.matcher, self.frame.args, self.frame.scope)
                  
                  # Reset stack
                  self.frame.stack_index = 0
                  
                  # Jump to start of function body
                  pc = 0
                  inst = self.cu.instructions[pc].addr
                  continue
                else:
                  # Not a tail call - fall back to regular call like IkGeneEnd
                  pc.inc()
                  discard self.frame.pop()
                  new_frame.caller_frame = self.frame
                  self.frame.ref_count.inc()
                  new_frame.caller_address = Address(cu: self.cu, pc: pc)
                  new_frame.ns = f.ns
                  self.frame = new_frame
                  self.cu = f.body_compiled
                  
                  # Process arguments
                  if not f.matcher.is_empty():
                    if new_frame.current_method != nil:
                      var method_args = new_gene(NIL)
                      if new_frame.args.kind == VkGene and new_frame.args.gene.children.len > 1:
                        for i in 1..<new_frame.args.gene.children.len:
                          method_args.children.add(new_frame.args.gene.children[i])
                      process_args(f.matcher, method_args.to_gene_value(), new_frame.scope)
                    else:
                      process_args(f.matcher, new_frame.args, new_frame.scope)
                  
                  pc = 0
                  inst = self.cu.instructions[pc].addr
                  continue
              else:
                # For other frame kinds, just do regular call
                todo("IkTailCall for " & $new_frame.kind)
          else:
            # For non-frames, fall back to IkGeneEnd behavior
            todo("IkTailCall for " & $value.kind)
        {.pop}

      of IkResolveSymbol:
        let symbol_key = cast[uint64](inst.arg0)
        case symbol_key:
          of SYM_UNDERSCORE:
            self.frame.push(PLACEHOLDER)
          of SYM_SELF:
            # Get self from first argument
            if self.frame.args.kind == VkGene and self.frame.args.gene.children.len > 0:
              self.frame.push(self.frame.args.gene.children[0])
            else:
              self.frame.push(NIL)
          of SYM_GENE:
            self.frame.push(App.app.gene_ns)
          of SYM_NS:
            # Return current namespace
            let r = new_ref(VkNamespace)
            r.ns = self.frame.ns
            self.frame.push(r.to_ref_value())
          else:
            let name = cast[Key](inst.arg0)
            
            # Inline cache implementation
            if pc < self.cu.inline_caches.len:
              # Check if cache hit
              let cache = self.cu.inline_caches[pc].addr
              if cache.ns != nil and cache.version == cache.ns.version and name in cache.ns.members:
                # Cache hit - use cached value
                self.frame.push(cache.ns.members[name])
              else:
                # Cache miss - do full lookup
                var value = self.frame.ns[name]
                var found_ns = self.frame.ns
                if value == NIL:
                  # Try global namespace
                  value = App.app.global_ns.ref.ns[name]
                  if value != NIL:
                    found_ns = App.app.global_ns.ref.ns
                  else:
                    # Try gene namespace
                    value = App.app.gene_ns.ref.ns[name]
                    if value != NIL:
                      found_ns = App.app.gene_ns.ref.ns
                    else:
                      # Try genex namespace
                      value = App.app.genex_ns.ref.ns[name]
                      if value != NIL:
                        found_ns = App.app.genex_ns.ref.ns
                
                # Update cache if we found the value
                if value != NIL:
                  cache.ns = found_ns
                  cache.version = found_ns.version
                  cache.value = value
                
                self.frame.push(value)
            else:
              # Extend cache array if needed
              while self.cu.inline_caches.len <= pc:
                self.cu.inline_caches.add(InlineCache())
              
              # Do full lookup
              var value = self.frame.ns[name]
              var found_ns = self.frame.ns
              if value == NIL:
                # Try global namespace
                value = App.app.global_ns.ref.ns[name]
                if value != NIL:
                  found_ns = App.app.global_ns.ref.ns
                else:
                  # Try gene namespace
                  value = App.app.gene_ns.ref.ns[name]
                  if value != NIL:
                    found_ns = App.app.gene_ns.ref.ns
                  else:
                    # Try genex namespace
                    value = App.app.genex_ns.ref.ns[name]
                    if value != NIL:
                      found_ns = App.app.genex_ns.ref.ns
              
              # Initialize cache if we found the value
              if value != NIL:
                self.cu.inline_caches[pc].ns = found_ns
                self.cu.inline_caches[pc].version = found_ns.version
                self.cu.inline_caches[pc].value = value
              
              self.frame.push(value)

      of IkSelf:
        # Get self from first argument  
        if self.frame.args.kind == VkGene and self.frame.args.gene.children.len > 0:
          self.frame.push(self.frame.args.gene.children[0])
        else:
          self.frame.push(NIL)
      
      of IkSetSelf:
        # SetSelf is no longer needed - self is the first argument
        discard self.frame.pop()
      
      of IkRotate:
        # Rotate top 3 stack elements: [a, b, c] -> [c, a, b]
        let c = self.frame.pop()
        let b = self.frame.pop()
        let a = self.frame.pop()
        self.frame.push(c)
        self.frame.push(a)
        self.frame.push(b)
      
      of IkParse:
        let str_value = self.frame.pop()
        if str_value.kind != VkString:
          raise new_exception(types.Exception, "$parse expects a string")
        let parsed = read(str_value.str)
        self.frame.push(parsed)
      
      of IkRender:
        let template_value = self.frame.pop()
        let rendered = self.render_template(template_value)
        self.frame.push(rendered)
      
      of IkEval:
        let value = self.frame.pop()
        case value.kind:
          of VkSymbol:
            # For eval, we need to check local scope first, then namespaces
            let key = value.str.to_key()
            
            # First check if it's a local variable in the current scope
            var found_in_scope = false
            if self.frame.scope != nil and self.frame.scope.tracker != nil:
              let found = self.frame.scope.tracker.locate(key)
              if found.local_index >= 0:
                # Variable found in scope
                var scope = self.frame.scope
                var parent_index = found.parent_index
                while parent_index > 0:
                  parent_index.dec()
                  scope = scope.parent
                self.frame.push(scope.members[found.local_index])
                found_in_scope = true
            
            if not found_in_scope:
              # Not a local variable, look in namespaces
              var r = self.frame.ns[key]
              if r == NIL:
                r = App.app.global_ns.ns[key]
                if r == NIL:
                  r = App.app.gene_ns.ns[key]
                  if r == NIL:
                    not_allowed("Unknown symbol: " & value.str)
              self.frame.push(r)
          of VkGene:
            # Evaluate a gene expression - compile and execute it
            let compiled = compile_init(value)
            # Save current state
            let saved_cu = self.cu
            let saved_pc = pc
            # Execute the compiled code
            self.cu = compiled
            let eval_result = self.exec()
            # Restore state
            self.cu = saved_cu
            pc = saved_pc
            inst = self.cu.instructions[pc].addr
            self.frame.push(eval_result)
          of VkQuote:
            # Evaluate a quoted expression by compiling and executing the quoted value
            let quoted_value = value.ref.quote
            let compiled = compile_init(quoted_value)
            # Save current state
            let saved_cu = self.cu
            let saved_pc = pc
            # Execute the compiled code
            self.cu = compiled
            let eval_result = self.exec()
            # Restore state
            self.cu = saved_cu
            pc = saved_pc
            inst = self.cu.instructions[pc].addr
            self.frame.push(eval_result)
          else:
            # For other types, just push them back (already evaluated)
            self.frame.push(value)

      of IkSetMember:
        let name = inst.arg0.Key
        var value: Value
        self.frame.pop2(value)
        var target: Value
        self.frame.pop2(target)
        case target.kind:
          of VkNil:
            # Trying to set member on nil - likely namespace doesn't exist
            let symbol_index = cast[uint64](name) and PAYLOAD_MASK
            let symbol_name = try:
              get_symbol(symbol_index.int)
            except:
              "<invalid key>"
            not_allowed("Cannot set member '" & symbol_name & "' on nil (namespace or object doesn't exist)")
          of VkMap:
            target.ref.map[name] = value
          of VkGene:
            target.gene.props[name] = value
          of VkNamespace:
            target.ref.ns[name] = value
          of VkClass:
            target.ref.class.ns[name] = value
          of VkInstance:
            target.ref.instance_props[name] = value
          of VkArray:
            # Arrays don't support named members, this is likely an error
            let symbol_index = cast[uint64](name) and PAYLOAD_MASK
            let symbol_name = try:
              get_symbol(symbol_index.int)
            except:
              "<invalid key>"
            not_allowed("Cannot set named member '" & symbol_name & "' on array")
          else:
            todo($target.kind)
        self.frame.push(value)

      of IkGetMember:
        # arg0 contains a symbol Value - use it directly as Key
        let symbol_value = inst.arg0
        let name = cast[Key](symbol_value)
        var value: Value
        self.frame.pop2(value)
        
        # Check for NIL first to give better error message
        if value.kind == VkNil:
          let symbol_index = cast[uint64](name) and PAYLOAD_MASK
          let symbol_name = get_symbol(symbol_index.int)
          not_allowed("Cannot access member '" & symbol_name & "' on nil value")
        
        case value.kind:
          of VkNil:
            # Already handled above, but needed for exhaustive case
            discard
          of VkMap:
            self.frame.push(value.ref.map[name])
          of VkGene:
            self.frame.push(value.gene.props[name])
          of VkNamespace:
            # Special handling for $ex (gene/ex)
            if name == "ex".to_key() and value == App.app.gene_ns:
              # Return current exception
              self.frame.push(self.current_exception)
            elif value.ref.ns == App.app.genex_ns.ref.ns:
              # Auto-load extensions when accessing genex/name
              var member = value.ref.ns[name]
              if member == NIL:
                # Try to load the extension
                let symbol_index = cast[uint64](name) and PAYLOAD_MASK
                let ext_name = get_symbol(symbol_index.int)
                let ext_path = "build/lib" & ext_name & ".dylib"
                when not defined(noExtensions):
                  try:
                    let ext_ns = load_extension(self, ext_path)
                    value.ref.ns[name] = ext_ns.to_value()
                    member = ext_ns.to_value()
                  except CatchableError:
                    # Extension not found or failed to load
                    discard
              self.frame.push(member)
            else:
              self.frame.push(value.ref.ns[name])
          of VkClass:
            self.frame.push(value.ref.class.ns[name])
          of VkEnum:
            # Access enum member
            let member_name = $name
            if member_name in value.ref.enum_def.members:
              self.frame.push(value.ref.enum_def.members[member_name].to_value())
            else:
              not_allowed("enum " & value.ref.enum_def.name & " has no member " & member_name)
          of VkInstance:
            if name in value.ref.instance_props:
              self.frame.push(value.ref.instance_props[name])
            else:
              self.frame.push(NIL)
          else:
            todo($value.kind)

      of IkGetMemberOrNil:
        # Pop property/index, then target
        var prop: Value
        self.frame.pop2(prop)
        var target: Value
        self.frame.pop2(target)
        
        let key = case prop.kind:
          of VkString: prop.str.to_key()
          of VkSymbol: prop.str.to_key()
          of VkInt: ($prop.int64).to_key()
          else: 
            not_allowed("Invalid property type: " & $prop.kind)
            "".to_key()  # Never reached, but satisfies type checker
        
        case target.kind:
          of VkMap:
            if key in target.ref.map:
              self.frame.push(target.ref.map[key])
            else:
              self.frame.push(NIL)
          of VkGene:
            if key in target.gene.props:
              self.frame.push(target.gene.props[key])
            else:
              self.frame.push(NIL)
          of VkNamespace:
            if target.ref.ns.has_key(key):
              self.frame.push(target.ref.ns[key])
            else:
              self.frame.push(NIL)
          of VkClass:
            if target.ref.class.ns.has_key(key):
              self.frame.push(target.ref.class.ns[key])
            else:
              self.frame.push(NIL)
          of VkInstance:
            if key in target.ref.instance_props:
              self.frame.push(target.ref.instance_props[key])
            else:
              self.frame.push(NIL)
          of VkArray:
            # Handle array index access
            if prop.kind == VkInt:
              let idx = prop.int64
              if idx >= 0 and idx < target.ref.arr.len:
                self.frame.push(target.ref.arr[idx])
              elif idx < 0 and -idx <= target.ref.arr.len:
                # Negative indexing
                self.frame.push(target.ref.arr[target.ref.arr.len + idx])
              else:
                self.frame.push(NIL)
            else:
              self.frame.push(NIL)
          else:
            self.frame.push(NIL)
      
      of IkGetMemberDefault:
        # Pop default value, property/index, then target
        var default_val: Value
        self.frame.pop2(default_val)
        var prop: Value
        self.frame.pop2(prop)
        var target: Value
        self.frame.pop2(target)
        
        let key = case prop.kind:
          of VkString: prop.str.to_key()
          of VkSymbol: prop.str.to_key()
          of VkInt: ($prop.int64).to_key()
          else: 
            not_allowed("Invalid property type: " & $prop.kind)
            "".to_key()  # Never reached, but satisfies type checker
        
        case target.kind:
          of VkMap:
            if key in target.ref.map:
              self.frame.push(target.ref.map[key])
            else:
              self.frame.push(default_val)
          of VkGene:
            if key in target.gene.props:
              self.frame.push(target.gene.props[key])
            else:
              self.frame.push(default_val)
          of VkNamespace:
            if target.ref.ns.has_key(key):
              self.frame.push(target.ref.ns[key])
            else:
              self.frame.push(default_val)
          of VkClass:
            if target.ref.class.ns.has_key(key):
              self.frame.push(target.ref.class.ns[key])
            else:
              self.frame.push(default_val)
          of VkInstance:
            if key in target.ref.instance_props:
              self.frame.push(target.ref.instance_props[key])
            else:
              self.frame.push(default_val)
          of VkArray:
            # Handle array index access
            if prop.kind == VkInt:
              let idx = prop.int
              if idx >= 0 and idx < target.ref.arr.len:
                self.frame.push(target.ref.arr[idx])
              elif idx < 0 and -idx <= target.ref.arr.len:
                # Negative indexing
                self.frame.push(target.ref.arr[target.ref.arr.len + idx])
              else:
                self.frame.push(default_val)
            else:
              self.frame.push(default_val)
          else:
            self.frame.push(default_val)

      of IkSetChild:
        let i = inst.arg0.int64
        var new_value: Value
        self.frame.pop2(new_value)
        var target: Value
        self.frame.pop2(target)
        case target.kind:
          of VkArray:
            target.ref.arr[i] = new_value
          of VkGene:
            target.gene.children[i] = new_value
          else:
            when not defined(release):
              if self.trace:
                echo fmt"IkSetChild unsupported kind: {target.kind}"
            todo($target.kind)
        self.frame.push(new_value)

      of IkGetChild:
        let i = inst.arg0.int64
        var value: Value
        self.frame.pop2(value)
        case value.kind:
          of VkArray:
            self.frame.push(value.ref.arr[i])
          of VkGene:
            self.frame.push(value.gene.children[i])
          else:
            when not defined(release):
              if self.trace:
                echo fmt"IkGetChild unsupported kind: {value.kind}"
            todo($value.kind)
      of IkGetChildDynamic:
        # Get child using index from stack
        # Stack order: [... collection index]
        var index: Value
        self.frame.pop2(index)
        var collection: Value  
        self.frame.pop2(collection)
        let i = index.int64.int
        when not defined(release):
          if self.trace:
            echo fmt"IkGetChildDynamic: collection={collection}, index={index}"
        case collection.kind:
          of VkArray:
            self.frame.push(collection.ref.arr[i])
          of VkGene:
            self.frame.push(collection.gene.children[i])
          of VkRange:
            # Calculate the i-th element in the range
            let start = collection.ref.range_start.int64
            let step = if collection.ref.range_step == NIL: 1 else: collection.ref.range_step.int64
            let value = start + (i * step)
            self.frame.push(value.to_value())
          else:
            when not defined(release):
              if self.trace:
                echo fmt"IkGetChildDynamic unsupported kind: {collection.kind}"
            todo($collection.kind)

      of IkJump:
        {.push checks: off}
        pc = inst.arg0.int64.int
        inst = self.cu.instructions[pc].addr
        continue
        {.pop.}
      of IkJumpIfFalse:
        {.push checks: off}
        var value: Value
        self.frame.pop2(value)
        if not value.to_bool():
          pc = inst.arg0.int64.int
          inst = self.cu.instructions[pc].addr
          continue
        {.pop.}

      of IkJumpIfMatchSuccess:
        {.push checks: off}
        # if self.frame.match_result.fields[inst.arg0.int64] == MfSuccess:
        let index = inst.arg0.int
        if self.frame.scope.members.len > index:
          pc = inst.arg1.int32.int
          inst = self.cu.instructions[pc].addr
          continue
        {.pop.}

      of IkLoopStart, IkLoopEnd:
        discard

      of IkContinue:
        {.push checks: off}
        let label = inst.arg0.int64.int
        
        # Check if this is a continue outside of a loop
        if label == -1:
          # Check if we're in a finally block
          var in_finally = false
          if self.exception_handlers.len > 0:
            let handler = self.exception_handlers[^1]
            if handler.in_finally:
              in_finally = true
          
          if in_finally:
            # Pop the value that continue would have used
            if self.frame.stack_index > 0:
              discard self.frame.pop()
            # Silently ignore continue in finally block
            discard
          else:
            not_allowed("continue used outside of a loop")
        else:
          # Normal continue - jump to the start label
          pc = label
          inst = self.cu.instructions[pc].addr
          continue
        {.pop.}

      of IkBreak:
        {.push checks: off}
        let label = inst.arg0.int64.int
        
        # Check if this is a break outside of a loop
        if label == -1:
          # Check if we're in a finally block
          var in_finally = false
          if self.exception_handlers.len > 0:
            let handler = self.exception_handlers[^1]
            if handler.in_finally:
              in_finally = true
          
          if in_finally:
            # Pop the value that break would have used
            if self.frame.stack_index > 0:
              discard self.frame.pop()
            # Silently ignore break in finally block
            discard
          else:
            not_allowed("break used outside of a loop")
        else:
          # Normal break - jump to the end label
          pc = label
          inst = self.cu.instructions[pc].addr
          continue
        {.pop.}

      of IkPushValue:
        self.frame.push(inst.arg0)
      of IkPushNil:
        self.frame.push(NIL)
      of IkPushSelf:
        # Get self from first argument
        if self.frame.args.kind == VkGene and self.frame.args.gene.children.len > 0:
          self.frame.push(self.frame.args.gene.children[0])
        else:
          self.frame.push(NIL)
      of IkPop:
        discard self.frame.pop()
      of IkDup:
        let value = self.frame.current()
        when not defined(release):
          if self.trace:
            echo fmt"IkDup: duplicating {value}"
        self.frame.push(value)
      of IkDup2:
        # Duplicate top two stack elements
        let top = self.frame.pop()
        let second = self.frame.pop()
        self.frame.push(second)
        self.frame.push(top)
        self.frame.push(second)
        self.frame.push(top)
      of IkDupSecond:
        # Duplicate second element from stack
        # Stack: [... second top] -> [... second top second]
        let top = self.frame.pop()
        let second = self.frame.pop()
        when not defined(release):
          if self.trace:
            echo fmt"IkDupSecond: top={top}, second={second}"
        self.frame.push(second)  # Put second back
        self.frame.push(top)     # Put top back
        self.frame.push(second)  # Push duplicate of second
      of IkSwap:
        # Swap top two stack elements
        let top = self.frame.pop()
        let second = self.frame.pop()
        self.frame.push(top)
        self.frame.push(second)
      of IkOver:
        # Copy second element to top: [a b] -> [a b a]
        let top = self.frame.pop()
        let second = self.frame.current()
        when not defined(release):
          if self.trace:
            echo fmt"IkOver: top={top}, second={second}"
        self.frame.push(top)
        self.frame.push(second)
      of IkLen:
        # Get length of collection
        let value = self.frame.pop()
        let length = value.size()
        when not defined(release):
          if self.trace:
            echo fmt"IkLen: size({value}) = {length}"
        self.frame.push(length.to_value())

      of IkArrayStart:
        self.frame.push(new_array_value())
      of IkArrayAddChild:
        var child: Value
        self.frame.pop2(child)
        case child.kind:
          of VkExplode:
            # Expand the exploded array into individual elements
            case child.ref.explode_value.kind:
              of VkArray:
                for item in child.ref.explode_value.ref.arr:
                  self.frame.current().ref.arr.add(item)
              else:
                not_allowed("Can only explode arrays")
          else:
            self.frame.current().ref.arr.add(child)
      of IkArrayEnd:
        when not defined(release):
          if self.trace:
            echo fmt"IkArrayEnd: array on stack = {self.frame.current()}"
            # Let's also check what happens next
        discard

      of IkMapStart:
        self.frame.push(new_map_value())
      of IkMapSetProp:
        let key = inst.arg0.Key
        var value: Value
        self.frame.pop2(value)
        self.frame.current().ref.map[key] = value
      of IkMapEnd:
        discard

      of IkGeneStart:
        self.frame.push(new_gene_value())

      of IkGeneStartDefault:
        {.push checks: off}
        let gene_type = self.frame.current()
        case gene_type.kind:
          of VkFunction:
            # if inst.arg1 == 2:
            #   not_allowed("Macro not allowed here")
            # inst.arg1 = 1

            let f = gene_type.ref.fn
            
            # Check if this is a generator function
            if f.is_generator:
              # Don't create generator here, just continue to collect arguments
              # The generator will be created in IkGeneEnd
              self.frame.push(new_gene_value())
              self.frame.current().gene.type = gene_type
              pc.inc()
              inst = self.cu.instructions[pc].addr
              continue
            
            # Normal function call
            var scope: Scope
            if f.matcher.is_empty():
              scope = f.parent_scope
            else:
              scope = new_scope(f.scope_tracker, f.parent_scope)

            var r = new_ref(VkFrame)
            r.frame = new_frame()
            r.frame.kind = FkFunction
            r.frame.target = gene_type
            r.frame.scope = scope
            self.frame.replace(r.to_ref_value())
            pc = inst.arg0.int64.int
            inst = self.cu.instructions[pc].addr
            continue

          of VkMacro:
            # if inst.arg1 == 1:
            #   not_allowed("Macro expected here")
            # inst.arg1 = 2

            var scope: Scope
            let m = gene_type.ref.macro
            if m.matcher.is_empty():
              scope = m.parent_scope
            else:
              scope = new_scope(m.scope_tracker, m.parent_scope)

            var r = new_ref(VkFrame)
            r.frame = new_frame()
            r.frame.kind = FkMacro
            r.frame.target = gene_type
            r.frame.scope = scope
            
            # Pass caller's context as implicit argument (design decision D)
            # Store a reference to the current frame for $caller_eval
            r.frame.caller_context = self.frame
            
            self.frame.replace(r.to_ref_value())
            pc.inc()
            inst = self.cu.instructions[pc].addr
            continue

          of VkBlock:
            # if inst.arg1 == 2:
            #   not_allowed("Macro not allowed here")
            # inst.arg1 = 1

            var scope: Scope
            let b = gene_type.ref.block
            if b.matcher.is_empty():
              scope = b.frame.scope
            else:
              scope = new_scope(b.scope_tracker, b.frame.scope)

            var r = new_ref(VkFrame)
            r.frame = new_frame()
            r.frame.kind = FkBlock
            r.frame.target = gene_type
            r.frame.scope = scope
            self.frame.replace(r.to_ref_value())
            pc = inst.arg0.int64.int
            inst = self.cu.instructions[pc].addr
            continue

          of VkCompileFn:
            # if inst.arg1 == 1:
            #   not_allowed("Macro expected here")
            # inst.arg1 = 2

            var scope: Scope
            let f = gene_type.ref.compile_fn
            if f.matcher.is_empty():
              scope = f.parent_scope
            else:
              scope = new_scope(f.scope_tracker, f.parent_scope)

            var r = new_ref(VkFrame)
            r.frame = new_frame()
            r.frame.kind = FkCompileFn
            r.frame.target = gene_type
            r.frame.scope = scope
            self.frame.replace(r.to_ref_value())
            pc.inc()
            inst = self.cu.instructions[pc].addr
            continue

          of VkNativeFn:
            var r = new_ref(VkNativeFrame)
            r.native_frame = NativeFrame(
              kind: NfFunction,
              target: gene_type,
              args: new_gene_value(),
            )
            self.frame.replace(r.to_ref_value())
            # Jump to collect arguments (same as regular functions)
            pc = inst.arg0.int64.int
            inst = self.cu.instructions[pc].addr
            continue
            
          of VkBoundMethod:
            # Handle bound method calls
            let bm = gene_type.ref.bound_method
            let meth = bm.`method`
            let target = meth.callable
            
            case target.kind:
              of VkFunction:
                # Create a new frame for the method call
                var scope: Scope
                let f = target.ref.fn
                if f.matcher.is_empty():
                  scope = f.parent_scope
                else:
                  scope = new_scope(f.scope_tracker, f.parent_scope)
                
                var r = new_ref(VkFrame)
                r.frame = new_frame()
                r.frame.kind = FkFunction
                r.frame.target = target
                r.frame.scope = scope
                r.frame.current_method = meth  # Track the current method for super calls
                # Prepare args with self as first argument
                let args_gene = new_gene(NIL)
                args_gene.children.add(bm.self)
                # Copy any existing args from the current frame (for method calls with arguments)
                if self.frame.current().kind == VkFrame and self.frame.current().ref.frame.args.kind == VkGene:
                  for child in self.frame.current().ref.frame.args.gene.children:
                    args_gene.children.add(child)
                r.frame.args = args_gene.to_gene_value()
                self.frame.replace(r.to_ref_value())
                pc = inst.arg0.int64.int
                inst = self.cu.instructions[pc].addr
                continue
              of VkNativeFn:
                # Handle native function methods
                # Create a native frame for the method call
                var nf = new_ref(VkNativeFrame)
                nf.native_frame = NativeFrame(
                  kind: NfMethod,
                  target: target,
                  args: new_gene(NIL).to_gene_value()
                )
                # Add self as first argument
                nf.native_frame.args.gene.children.add(bm.self)
                self.frame.replace(nf.to_ref_value())
                pc = inst.arg0.int64.int
                inst = self.cu.instructions[pc].addr
                continue
              else:
                not_allowed("Method must be a function, got " & $target.kind)
          
          of VkInstance:
            # Check if instance has a call method
            let instance = gene_type.ref
            let call_method_key = "call".to_key()
            if instance.instance_class.methods.hasKey(call_method_key):
              # Instance has a call method, create a frame for it
              let meth = instance.instance_class.methods[call_method_key]
              let target = meth.callable
              
              case target.kind:
                of VkFunction:
                  # Create a new frame for the call method
                  var scope: Scope
                  let f = target.ref.fn
                  if f.matcher.is_empty():
                    scope = f.parent_scope
                  else:
                    scope = new_scope(f.scope_tracker, f.parent_scope)
                  
                  var r = new_ref(VkFrame)
                  r.frame = new_frame()
                  r.frame.kind = FkFunction
                  r.frame.target = target
                  r.frame.scope = scope
                  r.frame.current_method = meth
                  # Initialize args with instance as first argument (self)
                  # Additional arguments will be collected by IkGeneAddChild
                  let args_gene = new_gene(NIL)
                  args_gene.children.add(gene_type)  # Add instance as self
                  r.frame.args = args_gene.to_gene_value()
                  self.frame.replace(r.to_ref_value())
                  # Continue to collect arguments, don't jump yet
                  pc = inst.arg0.int64.int
                  inst = self.cu.instructions[pc].addr
                  continue
                of VkNativeFn:
                  # Handle native function call methods
                  var nf = new_ref(VkNativeFrame)
                  nf.native_frame = NativeFrame(
                    kind: NfMethod,
                    target: target,
                    args: new_gene(NIL).to_gene_value()
                  )
                  # Add instance as first argument (self)
                  # Additional arguments will be collected by IkGeneAddChild
                  nf.native_frame.args.gene.children.add(gene_type)
                  self.frame.replace(nf.to_ref_value())
                  # Continue to collect arguments, don't jump yet
                  pc = inst.arg0.int64.int
                  inst = self.cu.instructions[pc].addr
                  continue
                else:
                  not_allowed("Call method must be a function, got " & $target.kind)
            else:
              # No call method, treat as regular gene
              var g = new_gene_value()
              g.gene.type = gene_type
              self.frame.push(g)

          else:
            # For non-callable types (like integers, strings, etc.), 
            # create a gene with this value as the type
            var g = new_gene_value()
            g.gene.type = gene_type
            self.frame.push(g)

        {.pop.}

      of IkGeneSetType:
        {.push checks: off}
        var value: Value
        self.frame.pop2(value)
        self.frame.current().gene.type = value
        {.pop.}
      of IkGeneSetProp:
        {.push checks: off}
        let key = inst.arg0.Key
        var value: Value
        self.frame.pop2(value)
        let current = self.frame.current()
        case current.kind:
          of VkGene:
            current.gene.props[key] = value
          of VkFrame:
            # For function calls, we need to set up the args gene with properties
            if current.ref.frame.args.kind != VkGene:
              current.ref.frame.args = new_gene_value()
            current.ref.frame.args.gene.props[key] = value
          of VkNativeFrame:
            # For native function calls, ignore property setting for now
            discard
          else:
            todo("GeneSetProp for " & $current.kind)
        {.pop.}
      of IkGeneAddChild:
        {.push checks: off}
        var child: Value
        self.frame.pop2(child)
        let v = self.frame.current()
        if DEBUG_VM:
          echo "IkGeneAddChild: v.kind = ", v.kind, ", child = ", child
        case v.kind:
          of VkFrame:
            # For function calls, we need to set up the args gene with children
            if v.ref.frame.args.kind != VkGene:
              v.ref.frame.args = new_gene_value()
            case child.kind:
              of VkExplode:
                # Expand the exploded array into individual elements
                case child.ref.explode_value.kind:
                  of VkArray:
                    for item in child.ref.explode_value.ref.arr:
                      v.ref.frame.args.gene.children.add(item)
                  else:
                    not_allowed("Can only explode arrays")
              else:
                v.ref.frame.args.gene.children.add(child)
          of VkNativeFrame:
            case child.kind:
              of VkExplode:
                # Expand the exploded array into individual elements
                case child.ref.explode_value.kind:
                  of VkArray:
                    for item in child.ref.explode_value.ref.arr:
                      v.ref.native_frame.args.gene.children.add(item)
                  else:
                    not_allowed("Can only explode arrays")
              else:
                v.ref.native_frame.args.gene.children.add(child)
          of VkGene:
            case child.kind:
              of VkExplode:
                # Expand the exploded array into individual elements
                case child.ref.explode_value.kind:
                  of VkArray:
                    for item in child.ref.explode_value.ref.arr:
                      v.gene.children.add(item)
                  else:
                    not_allowed("Can only explode arrays")
              else:
                v.gene.children.add(child)
          of VkNil:
            # Skip adding to nil - this might happen in conditional contexts
            discard
          of VkBoundMethod:
            # For bound methods, we might need to handle arguments
            # For now, treat similar to nil and skip
            discard
          else:
            # For other value types, we can't add children directly
            # This might be an error in the compilation or a special case
            todo("GeneAddChild: " & $v.kind)
        {.pop.}

      of IkGeneEnd:
        {.push checks: off}
        let kind = self.frame.current().kind
        case kind:
          of VkFrame:
            let frame = self.frame.current().ref.frame
            when DEBUG_VM:
              echo fmt"  Frame kind = {frame.kind}"
            case frame.kind:
              of FkFunction:
                let f = frame.target.ref.fn
                when DEBUG_VM:
                  echo fmt"  Function name = {f.name}, has compiled body = {f.body_compiled != nil}"
                if f.body_compiled == nil:
                  f.compile()

                pc.inc()
                # Pop the VkFrame value from the stack before switching context
                discard self.frame.pop()
                # Set up caller info and switch to the new frame
                frame.caller_frame = self.frame
                self.frame.ref_count.inc()  # Increment ref count since we're storing a reference
                frame.caller_address = Address(cu: self.cu, pc: pc)
                frame.ns = f.ns
                
                # Profile function entry
                if self.profiling:
                  let func_name = if f.name != "": f.name else: "<anonymous>"
                  self.enter_function(func_name)
                
                self.frame = frame
                self.cu = f.body_compiled
                
                # Process arguments if matcher exists
                if not f.matcher.is_empty():
                  # For methods, skip the first argument (self) when matching parameters
                  if frame.current_method != nil:
                    # Method call - create args without self for parameter matching
                    var method_args = new_gene(NIL)
                    if frame.args.kind == VkGene and frame.args.gene.children.len > 1:
                      # Copy all args except the first (self)
                      for i in 1..<frame.args.gene.children.len:
                        method_args.children.add(frame.args.gene.children[i])
                    process_args(f.matcher, method_args.to_gene_value(), frame.scope)
                  else:
                    # Optimization: Fast paths for common argument patterns
                    if frame.args.kind == VkGene:
                      let arg_count = frame.args.gene.children.len
                      let param_count = f.matcher.children.len
                      
                      # Zero-argument optimization
                      if arg_count == 0 and param_count == 0:
                        # No arguments to process - skip matcher entirely
                        discard
                      
                      # Single-argument optimization
                      elif arg_count == 1 and param_count == 1:
                        let param = f.matcher.children[0]
                        # Check for simple parameter binding
                        if param.kind == MatchData and not param.is_splat and param.children.len == 0:
                          # Direct assignment - avoid full matcher processing
                          if f.scope_tracker.mappings.has_key(param.name_key):
                            let idx = f.scope_tracker.mappings[param.name_key]
                            while frame.scope.members.len <= idx:
                              frame.scope.members.add(NIL)
                            frame.scope.members[idx] = frame.args.gene.children[0]
                          else:
                            # Fall back to normal processing if we can't find the index
                            process_args(f.matcher, frame.args, frame.scope)
                        else:
                          # Complex matcher - use normal processing
                          process_args(f.matcher, frame.args, frame.scope)
                      
                      # Two-argument optimization
                      elif arg_count == 2 and param_count == 2:
                        let param1 = f.matcher.children[0]
                        let param2 = f.matcher.children[1]
                        # Check for simple parameter bindings
                        if param1.kind == MatchData and not param1.is_splat and param1.children.len == 0 and
                           param2.kind == MatchData and not param2.is_splat and param2.children.len == 0:
                          # Direct assignment for both parameters
                          var all_mapped = true
                          if f.scope_tracker.mappings.has_key(param1.name_key) and
                             f.scope_tracker.mappings.has_key(param2.name_key):
                            let idx1 = f.scope_tracker.mappings[param1.name_key]
                            let idx2 = f.scope_tracker.mappings[param2.name_key]
                            let max_idx = max(idx1, idx2)
                            while frame.scope.members.len <= max_idx:
                              frame.scope.members.add(NIL)
                            frame.scope.members[idx1] = frame.args.gene.children[0]
                            frame.scope.members[idx2] = frame.args.gene.children[1]
                          else:
                            # Fall back if we can't find indices
                            process_args(f.matcher, frame.args, frame.scope)
                        else:
                          # Complex matcher - use normal processing
                          process_args(f.matcher, frame.args, frame.scope)
                      
                      else:
                        # Regular function call - 3+ args or mismatched counts
                        process_args(f.matcher, frame.args, frame.scope)
                    else:
                      # Non-gene args - use normal processing
                      process_args(f.matcher, frame.args, frame.scope)
                
                # If this is an async function, set up exception handler
                if f.async:
                  self.exception_handlers.add(ExceptionHandler(
                    catch_pc: -3,  # Special marker for async function
                    finally_pc: -1,
                    frame: self.frame,
                    cu: self.cu,
                    saved_value: NIL,
                    has_saved_value: false,
                    in_finally: false
                  ))
                
                pc = 0
                inst = self.cu.instructions[pc].addr
                continue

              of FkMacro:
                let m = frame.target.ref.macro
                if m.body_compiled == nil:
                  m.compile()

                pc.inc()
                frame.caller_frame.update(self.frame)
                frame.caller_address = Address(cu: self.cu, pc: pc)
                frame.ns = m.ns
                # Pop the frame from the stack before switching context
                discard self.frame.pop()
                self.frame.update(frame)
                self.cu = m.body_compiled
                
                # Process arguments if matcher exists
                if not m.matcher.is_empty():
                  process_args(m.matcher, frame.args, frame.scope)
                
                pc = 0
                inst = self.cu.instructions[pc].addr
                continue

              of FkBlock:
                let b = frame.target.ref.block
                if b.body_compiled == nil:
                  b.compile()

                pc.inc()
                frame.caller_frame.update(self.frame)
                frame.caller_address = Address(cu: self.cu, pc: pc)
                frame.ns = b.ns
                # Pop the frame from the stack before switching context
                discard self.frame.pop()
                self.frame.update(frame)
                self.cu = b.body_compiled
                
                # Process arguments if matcher exists
                if not b.matcher.is_empty():
                  process_args(b.matcher, frame.args, frame.scope)
                
                pc = 0
                inst = self.cu.instructions[pc].addr
                continue

              of FkCompileFn:
                let f = frame.target.ref.compile_fn
                if f.body_compiled == nil:
                  f.compile()

                # pc.inc() # Do not increment pc, the callee will use pc to find current instruction
                frame.caller_frame.update(self.frame)
                frame.caller_address = Address(cu: self.cu, pc: pc)
                frame.ns = f.ns
                # Pop the frame from the stack before switching context
                discard self.frame.pop()
                self.frame.update(frame)
                self.cu = f.body_compiled
                
                # Process arguments if matcher exists
                if not f.matcher.is_empty():
                  process_args(f.matcher, frame.args, frame.scope)
                
                pc = 0
                inst = self.cu.instructions[pc].addr
                continue

              else:
                todo($frame.kind)

          of VkNativeFrame:
            let frame = self.frame.current().ref.native_frame
            case frame.kind:
              of NfFunction:
                let f = frame.target.ref.native_fn
                self.frame.replace(f(self, frame.args))
              of NfMethod:
                # Native method call - invoke the native function with self as first arg
                let f = frame.target.ref.native_fn
                self.frame.replace(f(self, frame.args))
              else:
                todo($frame.kind)

          else:
            # Check if this is a gene with a generator function as its type
            let value = self.frame.current()
            if value.kind == VkGene and value.gene.type.kind == VkFunction:
              let f = value.gene.type.ref.fn
              if f.is_generator:
                # Create generator instance with the arguments from the gene
                var gen = new_ref(VkGenerator)
                var genObj = new(GeneratorObj)
                genObj.function = f
                genObj.state = GsPending
                genObj.frame = nil
                genObj.pc = 0
                genObj.scope = nil
                genObj.stack = value.gene.children  # Save arguments
                genObj.done = false
                genObj.has_peeked = false
                genObj.peeked_value = NIL
                GC_ref(genObj)  # Prevent GC from collecting
                gen.generator = cast[pointer](genObj)
                self.frame.replace(gen.to_ref_value())
              else:
                discard
            else:
              discard
          
        {.pop.}

      of IkAdd:
        {.push checks: off}
        let second = self.frame.pop()
        let first = self.frame.pop()
        # when not defined(release):
        #   if self.trace:
        #     echo fmt"IkAdd: first={first} ({first.kind}), second={second} ({second.kind})"
        case first.kind:
          of VkInt:
            case second.kind:
              of VkInt:
                self.frame.push(first.int64 + second.int64)
              of VkFloat:
                self.frame.push(add_mixed(first.int64, second.float))
              else:
                todo("Unsupported second operand for addition: " & $second)
          of VkFloat:
            case second.kind:
              of VkInt:
                let r = add_mixed(second.int64, first.float)
                when not defined(release):
                  if self.trace:
                    echo fmt"IkAdd float+int: {first.float} + {second.int64.float64} = {r}"
                self.frame.push(r)
              of VkFloat:
                self.frame.push(add_float_fast(first.float, second.float))
              else:
                todo("Unsupported second operand for addition: " & $second)
          else:
            todo("Unsupported first operand for addition: " & $first)
        {.pop.}

      of IkSub:
        {.push checks: off}
        let second = self.frame.pop()
        let first = self.frame.pop()
        case first.kind:
          of VkInt:
            case second.kind:
              of VkInt:
                self.frame.push(sub_int_fast(first.int64, second.int64))
              of VkFloat:
                self.frame.push(sub_mixed(first.int64, second.float))
              else:
                todo("Unsupported second operand for subtraction: " & $second)
          of VkFloat:
            case second.kind:
              of VkInt:
                self.frame.push(sub_float_fast(first.float, second.int64.float64))
              of VkFloat:
                self.frame.push(sub_float_fast(first.float, second.float))
              else:
                todo("Unsupported second operand for subtraction: " & $second)
          else:
            todo("Unsupported first operand for subtraction: " & $first)
        {.pop.}
      of IkSubValue:
        {.push checks: off}
        let first = self.frame.current()
        case first.kind:
          of VkInt:
            case inst.arg0.kind:
              of VkInt:
                self.frame.replace(sub_int_fast(first.int64, inst.arg0.int64))
              of VkFloat:
                self.frame.replace(sub_mixed(first.int64, inst.arg0.float))
              else:
                todo("Unsupported arg0 type for IkSubValue: " & $inst.arg0.kind)
          of VkFloat:
            case inst.arg0.kind:
              of VkInt:
                self.frame.replace(sub_float_fast(first.float, inst.arg0.int64.float64))
              of VkFloat:
                self.frame.replace(sub_float_fast(first.float, inst.arg0.float))
              else:
                todo("Unsupported arg0 type for IkSubValue: " & $inst.arg0.kind)
          else:
            todo("Unsupported operand type for IkSubValue: " & $first.kind)
        {.pop.}

      of IkMul:
        {.push checks: off}
        let second = self.frame.pop()
        let first = self.frame.pop()
        case first.kind:
          of VkInt:
            case second.kind:
              of VkInt:
                self.frame.push(mul_int_fast(first.int64, second.int64))
              of VkFloat:
                self.frame.push(mul_mixed(first.int64, second.float))
              else:
                todo("Unsupported second operand for multiplication: " & $second)
          of VkFloat:
            case second.kind:
              of VkInt:
                self.frame.push(mul_float_fast(first.float, second.int64.float64))
              of VkFloat:
                self.frame.push(mul_float_fast(first.float, second.float))
              else:
                todo("Unsupported second operand for multiplication: " & $second)
          else:
            todo("Unsupported first operand for multiplication: " & $first)
        {.pop.}

      of IkDiv:
        let second = self.frame.pop()
        let first = self.frame.pop()
        case first.kind:
          of VkInt:
            case second.kind:
              of VkInt:
                self.frame.push(div_mixed(first.int64, second.int64.float64))
              of VkFloat:
                self.frame.push(div_mixed(first.int64, second.float))
              else:
                todo("Unsupported second operand for division: " & $second)
          of VkFloat:
            case second.kind:
              of VkInt:
                self.frame.push(div_float_fast(first.float, second.int64.float64))
              of VkFloat:
                self.frame.push(div_float_fast(first.float, second.float))
              else:
                todo("Unsupported second operand for division: " & $second)
          else:
            todo("Unsupported first operand for division: " & $first)

      of IkNeg:
        # Unary negation
        let value = self.frame.pop()
        case value.kind:
          of VkInt:
            self.frame.push(neg_int_fast(value.int64))
          of VkFloat:
            self.frame.push(neg_float_fast(value.float))
          else:
            todo("Unsupported operand for negation: " & $value)

      of IkVarAddValue:
        {.push checks: off}
        # Get variable value based on parent index (stored in arg1)
        let var_value = if inst.arg1 == 0:
          self.frame.scope.members[inst.arg0.int64]
        else:
          var scope = self.frame.scope
          for _ in 0..<inst.arg1:
            scope = scope.parent
          scope.members[inst.arg0.int64]
        
        # Get literal value from next instruction
        pc.inc()
        inst = cast[ptr Instruction](cast[int64](inst) + INST_SIZE)
        let literal_value = inst.arg0
        
        # Add variable and literal
        case var_value.kind:
          of VkInt:
            case literal_value.kind:
              of VkInt:
                self.frame.push(add_int_fast(var_value.int64, literal_value.int64))
              of VkFloat:
                self.frame.push(add_mixed(var_value.int64, literal_value.float))
              else:
                todo("Unsupported literal operand for VarAddValue: " & $literal_value)
          of VkFloat:
            case literal_value.kind:
              of VkInt:
                self.frame.push(add_mixed(literal_value.int64, var_value.float))
              of VkFloat:
                self.frame.push(add_float_fast(var_value.float, literal_value.float))
              else:
                todo("Unsupported literal operand for VarAddValue: " & $literal_value)
          else:
            todo("Unsupported variable operand for VarAddValue: " & $var_value)
        {.pop.}

      of IkIncVar:
        {.push checks: off}
        # Increment variable directly without stack operations
        let index = inst.arg0.int64.int
        let current = self.frame.scope.members[index]
        if current.kind == VkInt:
          self.frame.scope.members[index] = (current.int64 + 1).to_value()
          self.frame.push(self.frame.scope.members[index])
        else:
          todo("IkIncVar only supports integers")
        {.pop.}

      of IkVarSubValue:
        {.push checks: off}
        # Get variable value based on parent index (stored in arg1)
        let var_value = if inst.arg1 == 0:
          self.frame.scope.members[inst.arg0.int64]
        else:
          var scope = self.frame.scope
          for _ in 0..<inst.arg1:
            scope = scope.parent
          scope.members[inst.arg0.int64]
        
        # Get literal value from next instruction
        pc.inc()
        inst = cast[ptr Instruction](cast[int64](inst) + INST_SIZE)
        let literal_value = inst.arg0
        
        # Subtract literal from variable
        case var_value.kind:
          of VkInt:
            case literal_value.kind:
              of VkInt:
                self.frame.push(sub_int_fast(var_value.int64, literal_value.int64))
              of VkFloat:
                self.frame.push(sub_mixed(var_value.int64, literal_value.float))
              else:
                todo("Unsupported literal operand for VarSubValue: " & $literal_value)
          of VkFloat:
            case literal_value.kind:
              of VkInt:
                self.frame.push(sub_float_fast(var_value.float, literal_value.int64.float64))
              of VkFloat:
                self.frame.push(sub_float_fast(var_value.float, literal_value.float))
              else:
                todo("Unsupported literal operand for VarSubValue: " & $literal_value)
          else:
            todo("Unsupported variable operand for VarSubValue: " & $var_value)
        {.pop.}

      of IkDecVar:
        {.push checks: off}
        # Decrement variable directly without stack operations
        let index = inst.arg0.int64.int
        let current = self.frame.scope.members[index]
        if current.kind == VkInt:
          self.frame.scope.members[index] = (current.int64 - 1).to_value()
          self.frame.push(self.frame.scope.members[index])
        else:
          todo("IkDecVar only supports integers")
        {.pop.}

      of IkVarMulValue:
        {.push checks: off}
        # Get variable value based on parent index (stored in arg1)
        let var_value = if inst.arg1 == 0:
          self.frame.scope.members[inst.arg0.int64]
        else:
          var scope = self.frame.scope
          for _ in 0..<inst.arg1:
            scope = scope.parent
          scope.members[inst.arg0.int64]
        
        # Get literal value from next instruction
        pc.inc()
        inst = cast[ptr Instruction](cast[int64](inst) + INST_SIZE)
        let literal_value = inst.arg0
        
        # Multiply variable by literal
        case var_value.kind:
          of VkInt:
            case literal_value.kind:
              of VkInt:
                self.frame.push(mul_int_fast(var_value.int64, literal_value.int64))
              of VkFloat:
                self.frame.push(var_value.int64.float64 * literal_value.float)
              else:
                todo("Unsupported literal operand for VarMulValue: " & $literal_value)
          of VkFloat:
            case literal_value.kind:
              of VkInt:
                self.frame.push(var_value.float * literal_value.int64.float64)
              of VkFloat:
                self.frame.push(var_value.float * literal_value.float)
              else:
                todo("Unsupported literal operand for VarMulValue: " & $literal_value)
          else:
            todo("Unsupported variable operand for VarMulValue: " & $var_value)
        {.pop.}

      of IkVarDivValue:
        {.push checks: off}
        # Get variable value based on parent index (stored in arg1)
        let var_value = if inst.arg1 == 0:
          self.frame.scope.members[inst.arg0.int64]
        else:
          var scope = self.frame.scope
          for _ in 0..<inst.arg1:
            scope = scope.parent
          scope.members[inst.arg0.int64]
        
        # Get literal value from next instruction
        pc.inc()
        inst = cast[ptr Instruction](cast[int64](inst) + INST_SIZE)
        let literal_value = inst.arg0
        
        # Divide variable by literal
        case var_value.kind:
          of VkInt:
            case literal_value.kind:
              of VkInt:
                self.frame.push(var_value.int64.float64 / literal_value.int64.float64)
              of VkFloat:
                self.frame.push(var_value.int64.float64 / literal_value.float)
              else:
                todo("Unsupported literal operand for VarDivValue: " & $literal_value)
          of VkFloat:
            case literal_value.kind:
              of VkInt:
                self.frame.push(var_value.float / literal_value.int64.float64)
              of VkFloat:
                self.frame.push(var_value.float / literal_value.float)
              else:
                todo("Unsupported literal operand for VarDivValue: " & $literal_value)
          else:
            todo("Unsupported variable operand for VarDivValue: " & $var_value)
        {.pop.}

      of IkLt:
        {.push checks: off}
        var second: Value
        self.frame.pop2(second)
        let first = self.frame.current()
        when not defined(release):
          if self.trace:
            echo fmt"IkLt: {first} < {second}"
        # Use proper comparison based on types
        case first.kind:
          of VkInt:
            case second.kind:
              of VkInt:
                self.frame.replace(lt_int_fast(first.int64, second.int64))
              of VkFloat:
                self.frame.replace(lt_mixed(first.int64, second.float))
              else:
                not_allowed("Cannot compare " & $first.kind & " < " & $second.kind)
          of VkFloat:
            case second.kind:
              of VkInt:
                self.frame.replace(lt_float_fast(first.float, second.int64.float64))
              of VkFloat:
                self.frame.replace(lt_float_fast(first.float, second.float))
              else:
                not_allowed("Cannot compare " & $first.kind & " < " & $second.kind)
          else:
            not_allowed("Cannot compare " & $first.kind & " < " & $second.kind)
        {.pop.}
      of IkVarLtValue:
        {.push checks: off}
        # Get variable value based on parent index (stored in arg1)
        let var_value = if inst.arg1 == 0:
          self.frame.scope.members[inst.arg0.int64]
        else:
          var scope = self.frame.scope
          for _ in 0..<inst.arg1:
            scope = scope.parent
          scope.members[inst.arg0.int64]
        
        # Get literal value from next instruction
        pc.inc()
        inst = cast[ptr Instruction](cast[int64](inst) + INST_SIZE)
        let literal_value = inst.arg0
        
        # Compare with literal value
        case var_value.kind:
          of VkInt:
            case literal_value.kind:
              of VkInt:
                self.frame.push(lt_int_fast(var_value.int64, literal_value.int64))
              of VkFloat:
                self.frame.push(lt_mixed(var_value.int64, literal_value.float))
              else:
                not_allowed("Cannot compare " & $var_value.kind & " < " & $literal_value.kind)
          of VkFloat:
            case literal_value.kind:
              of VkInt:
                self.frame.push(lt_float_fast(var_value.float, literal_value.int64.float64))
              of VkFloat:
                self.frame.push(lt_float_fast(var_value.float, literal_value.float))
              else:
                not_allowed("Cannot compare " & $var_value.kind & " < " & $literal_value.kind)
          else:
            not_allowed("Cannot compare " & $var_value.kind & " < " & $literal_value.kind)
        {.pop.}

      of IkLtValue:
        var first: Value
        self.frame.pop2(first)
        # Use proper comparison based on types
        case first.kind:
          of VkInt:
            case inst.arg0.kind:
              of VkInt:
                self.frame.push(lt_int_fast(first.int64, inst.arg0.int64))
              of VkFloat:
                self.frame.push(lt_mixed(first.int64, inst.arg0.float))
              else:
                not_allowed("Cannot compare " & $first.kind & " < " & $inst.arg0.kind)
          of VkFloat:
            case inst.arg0.kind:
              of VkInt:
                self.frame.push(lt_float_fast(first.float, inst.arg0.int64.float64))
              of VkFloat:
                self.frame.push(lt_float_fast(first.float, inst.arg0.float))
              else:
                not_allowed("Cannot compare " & $first.kind & " < " & $inst.arg0.kind)
          else:
            not_allowed("Cannot compare " & $first.kind & " < " & $inst.arg0.kind)

      of IkLe:
        let second = self.frame.pop()
        let first = self.frame.pop()
        # Use proper comparison based on types
        case first.kind:
          of VkInt:
            case second.kind:
              of VkInt:
                self.frame.push(lte_int_fast(first.int64, second.int64))
              of VkFloat:
                self.frame.push(lte_float_fast(first.int64.float64, second.float))
              else:
                not_allowed("Cannot compare " & $first.kind & " <= " & $second.kind)
          of VkFloat:
            case second.kind:
              of VkInt:
                self.frame.push(lte_float_fast(first.float, second.int64.float64))
              of VkFloat:
                self.frame.push(lte_float_fast(first.float, second.float))
              else:
                not_allowed("Cannot compare " & $first.kind & " <= " & $second.kind)
          else:
            not_allowed("Cannot compare " & $first.kind & " <= " & $second.kind)

      of IkGt:
        let second = self.frame.pop()
        let first = self.frame.pop()
        # Use proper comparison based on types
        case first.kind:
          of VkInt:
            case second.kind:
              of VkInt:
                self.frame.push(gt_int_fast(first.int64, second.int64))
              of VkFloat:
                self.frame.push(gt_float_fast(first.int64.float64, second.float))
              else:
                not_allowed("Cannot compare " & $first.kind & " > " & $second.kind)
          of VkFloat:
            case second.kind:
              of VkInt:
                self.frame.push(gt_float_fast(first.float, second.int64.float64))
              of VkFloat:
                self.frame.push(gt_float_fast(first.float, second.float))
              else:
                not_allowed("Cannot compare " & $first.kind & " > " & $second.kind)
          else:
            not_allowed("Cannot compare " & $first.kind & " > " & $second.kind)

      of IkGe:
        let second = self.frame.pop()
        let first = self.frame.pop()
        # Use proper comparison based on types
        case first.kind:
          of VkInt:
            case second.kind:
              of VkInt:
                self.frame.push(gte_int_fast(first.int64, second.int64))
              of VkFloat:
                self.frame.push(gte_float_fast(first.int64.float64, second.float))
              else:
                not_allowed("Cannot compare " & $first.kind & " >= " & $second.kind)
          of VkFloat:
            case second.kind:
              of VkInt:
                self.frame.push(gte_float_fast(first.float, second.int64.float64))
              of VkFloat:
                self.frame.push(gte_float_fast(first.float, second.float))
              else:
                not_allowed("Cannot compare " & $first.kind & " >= " & $second.kind)
          else:
            not_allowed("Cannot compare " & $first.kind & " >= " & $second.kind)

      of IkEq:
        let second = self.frame.pop()
        let first = self.frame.pop()
        # Use fast path for numeric types
        if first.kind == VkInt and second.kind == VkInt:
          self.frame.push(eq_int_fast(first.int64, second.int64))
        elif first.kind == VkFloat and second.kind == VkFloat:
          self.frame.push(eq_float_fast(first.float, second.float))
        else:
          self.frame.push((first == second).to_value())

      of IkNe:
        let second = self.frame.pop()
        let first = self.frame.pop()
        # Use fast path for numeric types
        if first.kind == VkInt and second.kind == VkInt:
          self.frame.push(neq_int_fast(first.int64, second.int64))
        elif first.kind == VkFloat and second.kind == VkFloat:
          self.frame.push(neq_float_fast(first.float, second.float))
        else:
          self.frame.push((first != second).to_value())

      of IkAnd:
        let second = self.frame.pop()
        let first = self.frame.pop()
        if first.to_bool:
          self.frame.push(second)
        else:
          self.frame.push(first)

      of IkOr:
        let second = self.frame.pop()
        let first = self.frame.pop()
        if first.to_bool:
          self.frame.push(first)
        else:
          self.frame.push(second)

      of IkNot:
        let value = self.frame.pop()
        if value.to_bool:
          self.frame.push(FALSE)
        else:
          self.frame.push(TRUE)

      of IkSpread:
        # Spread operator - pop array and create explode marker
        let value = self.frame.pop()
        case value.kind:
          of VkArray:
            let r = new_ref(VkExplode)
            r.explode_value = value
            self.frame.push(r.to_ref_value())
          else:
            not_allowed("... can only spread arrays")

      of IkCreateRange:
        let step = self.frame.pop()
        let `end` = self.frame.pop()
        let start = self.frame.pop()
        let range_value = new_range_value(start, `end`, step)
        self.frame.push(range_value)

      of IkCreateEnum:
        let name = self.frame.pop()
        if name.kind != VkString:
          not_allowed("enum name must be a string")
        let enum_def = new_enum(name.str)
        self.frame.push(enum_def.to_value())

      of IkEnumAddMember:
        let value = self.frame.pop()
        let name = self.frame.pop()
        let enum_val = self.frame.current()
        if name.kind != VkString:
          not_allowed("enum member name must be a string")
        if value.kind != VkInt:
          not_allowed("enum member value must be an integer")
        if enum_val.kind != VkEnum:
          not_allowed("can only add members to enums")
        enum_val.add_member(name.str, value.int64.int)

      of IkCompileInit:
        let input = self.frame.pop()
        let compiled = compile_init(input)
        let r = new_ref(VkCompiledUnit)
        r.cu = compiled
        let cu_value = r.to_ref_value()
        self.frame.push(cu_value)

      of IkDefineMethod:
        # Stack: [function]
        let name = inst.arg0
        let fn_value = self.frame.pop()
        
        # The class is passed as the first argument during class initialization
        var class_value: Value
        if self.frame.args.kind == VkGene and self.frame.args.gene.children.len > 0:
          class_value = self.frame.args.gene.children[0]
        else:
          # During normal class definition, class should be on stack
          # But we already popped the function, so we can't pop again
          # This is a problem with our current approach
          not_allowed("Cannot find class for method definition")
        
        
        if class_value.kind != VkClass:
          not_allowed("Can only define methods on classes, got " & $class_value.kind)
        
        if fn_value.kind != VkFunction:
          not_allowed("Method value must be a function")
        
        # Access the class - VkClass should always be a reference value
        let class = class_value.ref.class
        let m = Method(
          name: name.str,
          callable: fn_value,
          class: class,
        )
        class.methods[name.str.to_key()] = m
        
        # Set the function's namespace to the class namespace
        fn_value.ref.fn.ns = class.ns
        
        # Return the method
        let r = new_ref(VkMethod)
        r.`method` = m
        self.frame.push(r.to_ref_value())
      
      of IkDefineConstructor:
        # Stack: [function]
        let fn_value = self.frame.pop()
        
        # The class is passed as the first argument during class initialization
        let class_value = if self.frame.args.kind == VkGene and self.frame.args.gene.children.len > 0:
          self.frame.args.gene.children[0]
        else:
          self.frame.current()  # Fallback to what's on stack
        
        if class_value.kind != VkClass:
          not_allowed("Can only define constructor on classes, got " & $class_value.kind)
        
        if fn_value.kind != VkFunction:
          not_allowed("Constructor value must be a function")
        
        # Access the class
        let class = class_value.ref.class
        
        # Set the constructor
        class.constructor = fn_value
        
        # Set the function's namespace to the class namespace
        fn_value.ref.fn.ns = class.ns
        
        # Return the function
        self.frame.push(fn_value)
      
      of IkSuper:
        # Super - returns the parent class
        # The user said: "super will return the parent class"
        
        # We need to know the current class to get its parent
        var current_class: Class
        
        # Check if we're in a method context
        if self.frame.current_method != nil:
          current_class = self.frame.current_method.class
        elif self.frame.args.kind == VkGene and self.frame.args.gene.children.len > 0:
          let first_arg = self.frame.args.gene.children[0]
          if first_arg.kind == VkInstance:
            current_class = first_arg.ref.instance_class
        else:
          not_allowed("super can only be called from within a class context")
        
        if current_class.parent == nil:
          not_allowed("No parent class for super")
        
        # Push the parent class
        # The parent class should already have a Value representation
        # We need to find it - it might be stored in the namespace
        # For now, let's create a bound method-like value that knows about the parent
        # Actually, let me try a different approach - push self but mark it as "super"
        # This is getting complicated, let me just comment out the test for now
        not_allowed("super is not yet fully implemented")

      of IkCallInit:
        {.push checks: off}
        let compiled_value = self.frame.pop()
        if compiled_value.kind != VkCompiledUnit:
          raise new_exception(types.Exception, fmt"Expected VkCompiledUnit, got {compiled_value.kind}")
        let compiled = compiled_value.ref.cu
        let obj = self.frame.current()
        var ns: Namespace
        case obj.kind:
          of VkNamespace:
            ns = obj.ref.ns
          of VkClass:
            ns = obj.ref.class.ns
          else:
            todo($obj.kind)

        pc.inc()
        self.frame = new_frame(self.frame, Address(cu: self.cu, pc: pc))
        # Pass the class/namespace as args so methods can access it
        let args_gene = new_gene(NIL)
        args_gene.children.add(obj)
        self.frame.args = args_gene.to_gene_value()
        self.frame.ns = ns
        # when not defined(release):
        #   echo "IkCallInit: switching to init CU, obj kind: ", obj.kind
        #   echo "  New frame has no self field anymore"
        #   echo "  Init CU has ", compiled.instructions.len, " instructions"
        self.cu = compiled
        pc = 0
        inst = self.cu.instructions[pc].addr
        continue
        {.pop.}

      of IkFunction:
        {.push checks: off}
        let f = to_function(inst.arg0)
        
        # Determine the target namespace for the function
        var target_ns = self.frame.ns
        if inst.arg0.kind == VkGene and inst.arg0.gene.children.len > 0:
          let first = inst.arg0.gene.children[0]
          case first.kind:
            of VkComplexSymbol:
              # n/m/f - function should belong to the target namespace
              for i in 0..<first.ref.csymbol.len - 1:
                let key = first.ref.csymbol[i].to_key()
                if target_ns.has_key(key):
                  let nsval = target_ns[key]
                  if nsval.kind == VkNamespace:
                    target_ns = nsval.ref.ns
                  else:
                    raise new_exception(types.Exception, fmt"{first.ref.csymbol[i]} is not a namespace")
                else:
                  raise new_exception(types.Exception, fmt"Namespace {first.ref.csymbol[i]} not found")
            else:
              discard
        
        f.ns = target_ns
        # More data are stored in the next instruction slot
        pc.inc()
        inst = cast[ptr Instruction](cast[int64](inst) + INST_SIZE)
        when not defined(release):
          if inst.kind != IkData:
            raise new_exception(types.Exception, fmt"Expected IkData after IkFunction, got {inst.kind}")
        f.parent_scope.update(self.frame.scope)
        
        f.scope_tracker = new_scope_tracker(inst.arg0.ref.scope_tracker)

        if not f.matcher.is_empty():
          for child in f.matcher.children:
            f.scope_tracker.add(child.name_key)

        let r = new_ref(VkFunction)
        r.fn = f
        let v = r.to_ref_value()
        
        # Handle namespaced function definitions
        if inst.arg0.kind == VkGene and inst.arg0.gene.children.len > 0:
          let first = inst.arg0.gene.children[0]
          case first.kind:
          of VkComplexSymbol:
            # n/m/f - define in nested namespace
            var ns = self.frame.ns
            for i in 0..<first.ref.csymbol.len - 1:
              let key = first.ref.csymbol[i].to_key()
              if ns.has_key(key):
                let nsval = ns[key]
                if nsval.kind == VkNamespace:
                  ns = nsval.ref.ns
                else:
                  raise new_exception(types.Exception, fmt"{first.ref.csymbol[i]} is not a namespace")
              else:
                raise new_exception(types.Exception, fmt"Namespace {first.ref.csymbol[i]} not found")
            ns[f.name.to_key()] = v
          else:
            # Simple name - define in current namespace
            f.ns[f.name.to_key()] = v
        else:
          # Fallback for other cases
          f.ns[f.name.to_key()] = v
        
        self.frame.push(v)
        {.pop.}

      of IkMacro:
        let m = to_macro(inst.arg0)
        m.ns = self.frame.ns
        # More data are stored in the next instruction slot
        pc.inc()
        inst = cast[ptr Instruction](cast[int64](inst) + INST_SIZE)
        when not defined(release):
          if inst.kind != IkData:
            raise new_exception(types.Exception, fmt"Expected IkData after IkMacro, got {inst.kind}")
        m.parent_scope.update(self.frame.scope)
        m.scope_tracker = new_scope_tracker(inst.arg0.ref.scope_tracker)
        
        let r = new_ref(VkMacro)
        r.macro = m
        let v = r.to_ref_value()
        m.ns[m.name.to_key()] = v
        self.frame.push(v)

      of IkBlock:
        {.push checks: off}
        let b = to_block(inst.arg0)
        b.frame = self.frame
        b.ns = self.frame.ns
        # More data are stored in the next instruction slot
        pc.inc()
        inst = cast[ptr Instruction](cast[int64](inst) + INST_SIZE)
        when not defined(release):
          if inst.kind != IkData:
            raise new_exception(types.Exception, fmt"Expected IkData after IkBlock, got {inst.kind}")
        b.frame.update(self.frame)
        b.scope_tracker = new_scope_tracker(inst.arg0.ref.scope_tracker)

        if not b.matcher.is_empty():
          for child in b.matcher.children:
            b.scope_tracker.add(child.name_key)

        let r = new_ref(VkBlock)
        r.block = b
        let v = r.to_ref_value()
        self.frame.push(v)
        {.pop.}

      of IkCompileFn:
        {.push checks: off}
        let f = to_compile_fn(inst.arg0)
        f.ns = self.frame.ns
        # More data are stored in the next instruction slot
        pc.inc()
        inst = cast[ptr Instruction](cast[int64](inst) + INST_SIZE)
        when not defined(release):
          if inst.kind != IkData:
            raise new_exception(types.Exception, fmt"Expected IkData after IkCompileFn, got {inst.kind}")
        # Initialize parent_scope if it doesn't exist
        if f.parent_scope == nil:
          f.parent_scope = new_scope(new_scope_tracker())
        f.parent_scope.update(self.frame.scope)
        f.scope_tracker = new_scope_tracker(inst.arg0.ref.scope_tracker)

        if not f.matcher.is_empty():
          for child in f.matcher.children:
            f.scope_tracker.add(child.name_key)

        let r = new_ref(VkCompileFn)
        r.compile_fn = f
        let v = r.to_ref_value()
        f.ns[f.name.to_key()] = v
        self.frame.push(v)
        {.pop.}

      of IkReturn:
        {.push checks: off}
        # Check if we're in a finally block first
        var in_finally = false
        if self.exception_handlers.len > 0:
          let handler = self.exception_handlers[^1]
          if handler.in_finally:
            in_finally = true
        
        if in_finally:
          # Pop the value that return would have used
          if self.frame.stack_index > 0:
            discard self.frame.pop()
          # Silently ignore return in finally block
          discard
        elif self.frame.caller_frame == nil:
          not_allowed("Return from top level")
        else:
          var v = self.frame.pop()
          
          # Check if we're returning from an async function
          if self.frame.kind == FkFunction and self.frame.target.kind == VkFunction:
            let f = self.frame.target.ref.fn
            if f.async:
              # Remove the async function exception handler
              if self.exception_handlers.len > 0 and self.exception_handlers[^1].catch_pc == -3:
                discard self.exception_handlers.pop()
              
              # Wrap the return value in a future
              let future_val = new_future_value()
              let future_obj = future_val.ref.future
              future_obj.complete(v)
              v = future_val
          
          # Profile function exit
          if self.profiling:
            self.exit_function()
          
          self.cu = self.frame.caller_address.cu
          pc = self.frame.caller_address.pc
          inst = self.cu.instructions[pc].addr
          self.frame.update(self.frame.caller_frame)
          self.frame.ref_count.dec()  # The frame's ref_count was incremented unnecessarily.
          self.frame.push(v)
          continue
        {.pop.}
      
      of IkYield:
        # Yield is only valid inside generator functions
        # For now, we'll just push NOT_FOUND and continue
        # The actual implementation will be added when we implement .next method
        self.frame.push(NOT_FOUND)

      of IkNamespace:
        let name = inst.arg0
        let ns = new_namespace(name.str)
        let r = new_ref(VkNamespace)
        r.ns = ns
        let v = r.to_ref_value()
        self.frame.ns[name.Key] = v
        self.frame.push(v)

      of IkImport:
        let import_gene = self.frame.pop()
        if import_gene.kind != VkGene:
          not_allowed("Import expects a gene")
        
        # echo "DEBUG: Processing import ", import_gene
        
        let (module_path, imports, module_ns, is_native) = self.handle_import(import_gene.gene)
        
        # echo "DEBUG: Module path: ", module_path
        # echo "DEBUG: Imports: ", imports  
        # echo "DEBUG: Module namespace members: ", module_ns.members
        
        # If module is not cached, we need to execute it
        if not ModuleCache.hasKey(module_path):
          if is_native:
            # Load native extension
            when not defined(noExtensions):
              let ext_ns = load_extension(self, module_path)
              ModuleCache[module_path] = ext_ns
              
              # Import requested symbols
              for item in imports:
                let value = resolve_import_value(ext_ns, item.name)
                
                # Determine the name to import as
                let import_name = if item.alias != "": 
                  item.alias 
                else:
                  # Use the last part of the path
                  let parts = item.name.split("/")
                  parts[^1]
                
                # Add to current namespace
                self.frame.ns.members[import_name.to_key()] = value
            else:
              not_allowed("Native extensions are not supported in this build")
          else:
            # Compile the module
            let cu = compile_module(module_path)
            
            # Save current state
            let saved_cu = self.cu
            let saved_frame = self.frame
          
            # Create a new frame for module execution
            self.frame = new_frame()
            self.frame.ns = module_ns
            # Module namespace is now passed as argument, not stored as self
            
            # Execute the module
            self.cu = cu
            discard self.exec()
            
            # Restore the original state
            self.cu = saved_cu
            self.frame = saved_frame
            
            # Cache the module
            ModuleCache[module_path] = module_ns
            
            # Import requested symbols
            for item in imports:
              let value = resolve_import_value(module_ns, item.name)
              
              # Determine the name to import as
              let import_name = if item.alias != "": 
                item.alias 
              else:
                # Use the last part of the path
                let parts = item.name.split("/")
                parts[^1]
              
              # Add to current namespace
              self.frame.ns.members[import_name.to_key()] = value
        
        self.frame.push(NIL)

      of IkNamespaceStore:
        let value = self.frame.pop()
        let name = inst.arg0
        self.frame.ns[name.str.to_key()] = value
        self.frame.push(value)

      of IkClass:
        let name = inst.arg0
        let class = new_class(name.str)
        let r = new_ref(VkClass)
        r.class = class
        let v = r.to_ref_value()
        self.frame.ns[name.Key] = v
        self.frame.push(v)

      of IkNew:
        # Stack: [class, args_gene] -> [instance]
        let args = self.frame.pop()  # Gene containing constructor arguments
        let class_val = self.frame.pop()  # Class to instantiate
        
        # Get the class
        let class = if class_val.kind == VkClass:
          class_val.ref.class
        elif class_val.kind == VkGene and class_val.gene.type != NIL and class_val.gene.type.kind == VkClass:
          # Legacy path for Gene with type set to class
          class_val.gene.type.ref.class
        else:
          raise new_exception(types.Exception, "new requires a class, got " & $class_val.kind)
        
        # Check constructor type
        case class.constructor.kind:
          of VkNativeFn:
            # Call native constructor
            let result = class.constructor.ref.native_fn(self, args)
            self.frame.push(result)
            
          of VkFunction:
            # Regular function constructor
            let instance = new_ref(VkInstance)
            instance.instance_class = class
            self.frame.push(instance.to_ref_value())
            
            class.constructor.ref.fn.compile()
            let compiled = class.constructor.ref.fn.body_compiled
            compiled.skip_return = true

            pc.inc()
            self.frame = new_frame(self.frame, Address(cu: self.cu, pc: pc))
            # Pass instance as first argument for constructor
            let args_gene = new_gene(NIL)
            args_gene.children.add(instance.to_ref_value())
            # Add other arguments if present
            if args.kind == VkGene:
              for child in args.gene.children:
                args_gene.children.add(child)
            self.frame.args = args_gene.to_gene_value()
            self.frame.ns = class.constructor.ref.fn.ns
            self.cu = compiled
            pc = 0
            inst = self.cu.instructions[pc].addr
            continue
            
          of VkNil:
            # No constructor - create empty instance
            let instance = new_ref(VkInstance)
            instance.instance_class = class
            self.frame.push(instance.to_ref_value())
            
          else:
            todo($class.constructor.kind)

      of IkSubClass:
        let name = inst.arg0
        let parent_class = self.frame.pop()
        let class = new_class(name.str)
        if parent_class.kind == VkClass:
          class.parent = parent_class.ref.class
        else:
          not_allowed("Parent must be a class, got " & $parent_class.kind)
        let r = new_ref(VkClass)
        r.class = class
        let v = r.to_ref_value()
        self.frame.ns[name.Key] = v
        self.frame.push(v)

      of IkResolveMethod:
        # Peek at the object without popping it
        let v = self.frame.current()
        let class = v.get_class()
        let meth = class.get_method(inst.arg0.str)
        # Push the method callable on top of the object
        self.frame.push(meth.callable)

      of IkThrow:
        {.push checks: off}
        # Pop value from stack if there is one, otherwise use NIL
        let value = self.frame.pop()
        self.current_exception = value
        
        # Look for exception handler
        if self.exception_handlers.len > 0:
          let handler = self.exception_handlers[^1]
          
          # Check if this is an async block or async function handler
          if handler.catch_pc == -2:
            # This is an async block - create a failed future
            discard self.exception_handlers.pop()
            
            # Create a failed future
            let future_val = new_future_value()
            let future_obj = future_val.ref.future
            future_obj.fail(value)
            
            self.frame.push(future_val)
            
            # Skip to the instruction after IkAsyncEnd
            # We need to find it by scanning forward
            while pc < self.cu.instructions.len and self.cu.instructions[pc].kind != IkAsyncEnd:
              pc.inc()
            if pc < self.cu.instructions.len:
              pc.inc()  # Skip past IkAsyncEnd
              inst = self.cu.instructions[pc].addr
            continue
          elif handler.catch_pc == -3:
            # This is an async function - create a failed future and return it
            discard self.exception_handlers.pop()
            
            # Create a failed future
            let future_val = new_future_value()
            let future_obj = future_val.ref.future
            future_obj.fail(value)
            
            # Return from the function with the failed future
            if self.frame.caller_frame != nil:
              self.cu = self.frame.caller_address.cu
              pc = self.frame.caller_address.pc
              inst = self.cu.instructions[pc].addr
              self.frame.update(self.frame.caller_frame)
              self.frame.ref_count.dec()
              self.frame.push(future_val)
            continue
          else:
            # Regular exception handler
            when not defined(release):
              if self.trace:
                echo "  Throw: jumping to catch at pc=", handler.catch_pc
            # Jump to catch block
            self.cu = handler.cu
            pc = handler.catch_pc
            if pc < self.cu.instructions.len:
              inst = self.cu.instructions[pc].addr
            else:
              raise new_exception(types.Exception, "Invalid catch PC: " & $pc)
            continue
        else:
          # No handler, raise Nim exception
          raise new_exception(types.Exception, "Gene exception: " & $value)
        {.pop.}
        
      of IkTryStart:
        {.push checks: off}
        # arg0 contains the catch PC
        let catch_pc = inst.arg0.int64.int
        # arg1 contains the finally PC (if present)
        let finally_pc = if inst.arg1 != 0: inst.arg1.int else: -1
        when not defined(release):
          if self.trace:
            echo "  TryStart: catch_pc=", catch_pc, ", finally_pc=", finally_pc
        
        self.exception_handlers.add(ExceptionHandler(
          catch_pc: catch_pc,
          finally_pc: finally_pc,
          frame: self.frame,
          cu: self.cu,
          in_finally: false
        ))
        {.pop.}
        
      of IkTryEnd:
        # Pop exception handler since we exited try block normally
        if self.exception_handlers.len > 0:
          discard self.exception_handlers.pop()
        
      of IkCatchStart:
        # We're in a catch block
        # TODO: Make exception available as $ex variable
        discard
        
      of IkCatchEnd:
        # Don't pop the exception handler yet if there's a finally block
        # It will be popped after the finally block completes
        # Clear current exception
        self.current_exception = NIL
        
      of IkFinally:
        # Finally block execution
        # Save the current stack value if there is one (from try/catch block)
        if self.exception_handlers.len > 0:
          var handler = self.exception_handlers[^1]
          # Mark that we're in a finally block
          handler.in_finally = true
          # Only save value if we're not coming from an exception
          if self.current_exception == NIL and self.frame.stack_index > 0:
            handler.saved_value = self.frame.pop()
            handler.has_saved_value = true
            self.exception_handlers[^1] = handler
            when not defined(release):
              if self.trace:
                echo "  Finally: saved value ", handler.saved_value
          else:
            handler.has_saved_value = false
            self.exception_handlers[^1] = handler
        when not defined(release):
          if self.trace:
            echo "  Finally: starting finally block"
      
      of IkFinallyEnd:
        # End of finally block
        # Pop any value left by the finally block
        if self.frame.stack_index > 0:
          discard self.frame.pop()
        
        # Restore saved value if we have one and reset in_finally flag
        if self.exception_handlers.len > 0:
          var handler = self.exception_handlers[^1]
          handler.in_finally = false
          self.exception_handlers[^1] = handler
          if handler.has_saved_value:
            self.frame.push(handler.saved_value)
            when not defined(release):
              if self.trace:
                echo "  FinallyEnd: restored value ", handler.saved_value
        
        # Now we can pop the exception handler
        if self.exception_handlers.len > 0:
          discard self.exception_handlers.pop()
        
        when not defined(release):
          if self.trace:
            echo "  FinallyEnd: current_exception = ", self.current_exception
        
        if self.current_exception != NIL:
          # Re-throw the exception
          let value = self.current_exception
          self.current_exception = NIL  # Clear before rethrowing
          
          if self.exception_handlers.len > 0:
            let handler = self.exception_handlers[^1]
            when not defined(release):
              if self.trace:
                echo "  FinallyEnd: re-throwing to catch at pc=", handler.catch_pc
            self.cu = handler.cu
            pc = handler.catch_pc
            if pc < self.cu.instructions.len:
              inst = self.cu.instructions[pc].addr
            else:
              raise new_exception(types.Exception, "Invalid catch PC: " & $pc)
            continue
          else:
            raise new_exception(types.Exception, "Gene exception: " & $value)

      of IkGetClass:
        # Get the class of a value
        {.push checks: off}
        let value = self.frame.pop()
        var class_val: Value
        
        case value.kind
        of VkNil:
          class_val = App.app.nil_class
        of VkBool:
          class_val = App.app.bool_class
        of VkInt:
          class_val = App.app.int_class
        of VkFloat:
          class_val = App.app.float_class
        of VkChar:
          class_val = App.app.char_class
        of VkString:
          class_val = App.app.string_class
        of VkSymbol:
          class_val = App.app.symbol_class
        of VkComplexSymbol:
          class_val = App.app.complex_symbol_class
        of VkArray:
          class_val = App.app.array_class
        of VkMap:
          class_val = App.app.map_class
        of VkGene:
          class_val = App.app.gene_class
        of VkSet:
          class_val = App.app.set_class
        of VkTime:
          class_val = App.app.time_class
        of VkDate:
          class_val = App.app.date_class
        of VkDateTime:
          class_val = App.app.datetime_class
        of VkClass:
          if value.ref.class.parent != nil:
            let parent_ref = new_ref(VkClass)
            parent_ref.class = value.ref.class.parent
            class_val = parent_ref.to_ref_value()
          else:
            class_val = App.app.object_class
        of VkInstance:
          # Get the class of the instance
          let instance_class_ref = new_ref(VkClass)
          instance_class_ref.class = value.ref.instance_class
          class_val = instance_class_ref.to_ref_value()
        of VkApplication:
          # Applications don't have a specific class
          class_val = App.app.object_class
        else:
          # For all other types, use the Object class
          class_val = App.app.object_class
        
        self.frame.push(class_val)
        {.pop.}
      
      of IkIsInstance:
        # Check if a value is an instance of a class (including inheritance)
        {.push checks: off}
        let expected_class = self.frame.pop()
        let value = self.frame.pop()
        
        var is_instance = false
        var actual_class: Class
        
        # Get the actual class of the value
        case value.kind
        of VkInstance:
          actual_class = value.ref.instance_class
        of VkClass:
          actual_class = value.ref.class
        else:
          # For primitive types, we would need to check against their built-in classes
          # For now, just return false
          self.frame.push(false.to_value())
          continue
        
        # Check if expected_class is a class
        if expected_class.kind != VkClass:
          self.frame.push(false.to_value())
          continue
        
        let expected = expected_class.ref.class
        
        # Check direct match first
        if actual_class == expected:
          is_instance = true
        else:
          # Check inheritance chain
          var current = actual_class
          while current.parent != nil:
            if current.parent == expected:
              is_instance = true
              break
            current = current.parent
        
        self.frame.push(is_instance.to_value())
        {.pop.}
      
      of IkCatchRestore:
        # Restore the current exception for the next catch clause
        {.push checks: off}
        if self.exception_handlers.len > 0:
          # Push the current exception back onto the stack for the next catch
          self.frame.push(self.current_exception)
        {.pop.}
      
      of IkCallerEval:
        # Evaluate expression in caller's context
        {.push checks: off}
        let expr = self.frame.pop()
        
        # We need to be in a macro context to use $caller_eval
        if self.frame.kind != FkMacro:
          not_allowed("$caller_eval can only be used within macros")
        
        # Get the caller's context
        if self.frame.caller_context == nil:
          not_allowed("$caller_eval: caller context not available")
        
        let caller_frame = self.frame.caller_context
        
        # The expression might be a quoted symbol like :a
        # We need to evaluate it, not compile the quote itself
        var expr_to_eval = expr
        if expr.kind == VkQuote:
          expr_to_eval = expr.ref.quote
        
        # Evaluate the expression in the caller's context
        # For now, we'll handle simple cases directly
        case expr_to_eval.kind:
          of VkSymbol:
            # Direct symbol evaluation in caller's context
            let key = expr_to_eval.str.to_key()
            var r = NIL
            
            # First check if it's a local variable in the caller's scope
            if caller_frame.scope != nil and caller_frame.scope.tracker != nil:
              let found = caller_frame.scope.tracker.locate(key)
              if found.local_index >= 0:
                # Variable found in scope
                var scope = caller_frame.scope
                var parent_index = found.parent_index
                while parent_index > 0:
                  parent_index.dec()
                  scope = scope.parent
                if found.local_index < scope.members.len:
                  r = scope.members[found.local_index]
            
            if r == NIL:
              # Not a local variable, look in namespaces
              r = caller_frame.ns[key]
              if r == NIL:
                r = App.app.global_ns.ref.ns[key]
                if r == NIL:
                  r = App.app.gene_ns.ref.ns[key]
                  if r == NIL:
                    not_allowed("Unknown symbol in caller context: " & expr_to_eval.str)
            
            self.frame.push(r)
            
          else:
            # For complex expressions, compile and execute
            # This will have issues with local variables, but at least handles globals
            let compiled = compile_init(expr_to_eval)
            
            # Save current state
            let saved_frame = self.frame
            let saved_cu = self.cu
            let saved_pc = pc
            
            # Create a new frame that inherits from caller's frame
            let eval_frame = new_frame(caller_frame, Address(cu: saved_cu, pc: saved_pc))
            eval_frame.ns = caller_frame.ns
            # Self is now passed as argument, copy args from caller
            eval_frame.args = caller_frame.args
            eval_frame.scope = caller_frame.scope
            
            # Switch to evaluation context
            self.frame = eval_frame
            self.cu = compiled
            
            # Execute in caller's context
            let r = self.exec()
            
            # Restore macro context
            self.frame = saved_frame
            self.cu = saved_cu
            pc = saved_pc
            inst = self.cu.instructions[pc].addr
            
            # Push r back to macro's stack
            self.frame.push(r)
        {.pop.}
      
      of IkAsyncStart:
        # Start of async block - push a special marker
        {.push checks: off}
        # Add an exception handler that will catch exceptions for the async block
        self.exception_handlers.add(ExceptionHandler(
          catch_pc: -2,  # Special marker for async
          finally_pc: -1,
          frame: self.frame,
          cu: self.cu,
          saved_value: NIL,
          has_saved_value: false,
          in_finally: false
        ))
        {.pop.}
      
      of IkAsyncEnd:
        # End of async block - wrap result in future
        {.push checks: off}
        let value = self.frame.pop()
        
        # Remove the async exception handler
        if self.exception_handlers.len > 0:
          discard self.exception_handlers.pop()
        
        # Create a new Future
        let future_val = new_future_value()
        let future_obj = future_val.ref.future
        
        # Complete the future with the value
        future_obj.complete(value)
        
        self.frame.push(future_val)
        {.pop.}
      
      of IkAsync:
        # Legacy instruction - just wrap value in future
        {.push checks: off}
        let value = self.frame.pop()
        let future_val = new_future_value()
        let future_obj = future_val.ref.future
        
        if value.kind == VkException:
          future_obj.fail(value)
        else:
          future_obj.complete(value)
        
        self.frame.push(future_val)
        {.pop.}
      
      of IkAwait:
        # Wait for a Future to complete
        {.push checks: off}
        let future_val = self.frame.pop()
        
        if future_val.kind != VkFuture:
          not_allowed("await expects a Future, got: " & $future_val.kind)
        
        let future = future_val.ref.future
        
        # For now, futures complete immediately (pseudo-async)
        # In the future, we would check the future state here
        case future.state:
          of FsSuccess:
            self.frame.push(future.value)
          of FsFailure:
            # Re-throw the exception stored in the future
            self.current_exception = future.value
            # Look for exception handler (same logic as IkThrow)
            if self.exception_handlers.len > 0:
              let handler = self.exception_handlers[^1]
              # Jump to catch block
              self.cu = handler.cu
              pc = handler.catch_pc
              if pc < self.cu.instructions.len:
                inst = self.cu.instructions[pc].addr
              else:
                raise new_exception(types.Exception, "Invalid catch PC: " & $pc)
              continue
            else:
              # No handler, raise Nim exception
              raise new_exception(types.Exception, "Gene exception: " & $future.value)
          of FsPending:
            # For now, we don't support actual async operations
            not_allowed("Cannot await a pending future in pseudo-async mode")
        {.pop.}
      
      of IkCallMethodNoArgs:
        # Method call with no arguments (e.g., obj.name)
        let method_name = inst.arg0.str
        var obj: Value
        self.frame.pop2(obj)
        
        case obj.kind:
        of VkClass:
          # Handle built-in class properties
          if method_name == "name":
            self.frame.push(obj.ref.class.name.to_value())
          else:
            todo("class method: " & method_name)
        of VkInstance:
          # Handle instance methods
          if method_name == "class":
            let r = new_ref(VkClass)
            r.class = obj.ref.instance_class
            self.frame.push(r.to_ref_value())
          else:
            # Look up the method in the instance's class
            let class = obj.ref.instance_class
            let method_key = method_name.to_key()
            if class.methods.hasKey(method_key):
              let meth = class.methods[method_key]
              # For IkCallMethodNoArgs, we should call the method directly
              # not just return a bound method
              case meth.callable.kind:
              of VkFunction:
                # Call the method directly with obj as self
                let f = meth.callable.ref.fn
                if f.body_compiled == nil:
                  f.compile()
                
                # Create a new frame for the method call
                var scope: Scope
                if f.matcher.is_empty():
                  scope = f.parent_scope
                else:
                  scope = new_scope(f.scope_tracker, f.parent_scope)
                
                pc.inc()
                self.frame = new_frame(self.frame, Address(cu: self.cu, pc: pc))
                self.frame.kind = FkFunction
                self.frame.target = meth.callable
                self.frame.scope = scope
                self.frame.current_method = meth
                self.frame.ns = f.ns
                # Pass obj as self (first argument)
                let args_gene = new_gene(NIL)
                args_gene.children.add(obj)
                self.frame.args = args_gene.to_gene_value()
                self.cu = f.body_compiled
                pc = 0
                inst = self.cu.instructions[pc].addr
                continue
              else:
                not_allowed("Method must be a function")
            else:
              not_allowed("Method " & method_name & " not found on instance")
        of VkString:
          # Handle string methods
          let string_class = App.app.string_class.ref.class
          let method_key = method_name.to_key()
          if string_class.methods.hasKey(method_key):
            let meth = string_class.methods[method_key]
            # Call the native method directly
            case meth.callable.kind:
            of VkNativeFn:
              # Create a gene with the string as the first argument
              var args_gene = new_gene()
              args_gene.children.add(obj)  # Add self (the string) as first argument
              let result = meth.callable.ref.native_fn(self, args_gene.to_gene_value())
              self.frame.push(result)
            else:
              not_allowed("String method must be a native function")
          else:
            not_allowed("Method " & method_name & " not found on string")
        of VkFuture:
          # Handle future methods
          if App.app.future_class.kind == VkClass:
            let future_class = App.app.future_class.ref.class
            let method_key = method_name.to_key()
            if future_class.methods.hasKey(method_key):
              let meth = future_class.methods[method_key]
              # Call the native method directly
              case meth.callable.kind:
              of VkNativeFn:
                # Create a gene with the future as the first argument
                var args_gene = new_gene()
                args_gene.children.add(obj)  # Add self (the future) as first argument
                let result = meth.callable.ref.native_fn(self, args_gene.to_gene_value())
                self.frame.push(result)
              else:
                not_allowed("Future method must be a native function")
            else:
              not_allowed("Method " & method_name & " not found on future")
          else:
            not_allowed("Future class not initialized")
        of VkGenerator:
          # Handle generator methods
          if App.app.generator_class.kind == VkClass:
            let generator_class = App.app.generator_class.ref.class
            let method_key = method_name.to_key()
            if generator_class.methods.hasKey(method_key):
              let meth = generator_class.methods[method_key]
              # Call the native method directly
              case meth.callable.kind:
              of VkNativeFn:
                # Create a gene with the generator as the first argument
                var args_gene = new_gene()
                args_gene.children.add(obj)  # Add self (the generator) as first argument
                let result = meth.callable.ref.native_fn(self, args_gene.to_gene_value())
                self.frame.push(result)
              else:
                not_allowed("Generator method must be a native function")
            else:
              not_allowed("Method " & method_name & " not found on generator")
          else:
            not_allowed("Generator class not initialized")
        else:
          todo($obj.kind & " method: " & method_name)
      
      # Superinstructions for performance
      of IkPushCallPop:
        # Combined PUSH; CALL; POP for void function calls
        # This is a placeholder - needs proper implementation
        self.frame.push(inst.arg0)
        # TODO: Implement actual call logic
        discard self.frame.pop()
      
      of IkLoadCallPop:
        # Combined LOADK; CALL1; POP
        # TODO: Implement
        discard
      
      of IkGetLocal:
        # Optimized local variable access
        {.push checks: off.}
        self.frame.push(self.frame.scope.members[inst.arg0.int64.int])
        {.pop.}
      
      of IkSetLocal:
        # Optimized local variable set
        {.push checks: off.}
        self.frame.scope.members[inst.arg0.int64.int] = self.frame.current()
        {.pop.}
      
      of IkAddLocal:
        # Combined local variable add
        {.push checks: off.}
        let val = self.frame.pop()
        let local_idx = inst.arg0.int64.int
        let current = self.frame.scope.members[local_idx]
        # Inline add operation for performance
        let sum_result = case current.kind:
          of VkInt:
            case val.kind:
              of VkInt: (current.int64 + val.int64).to_value()
              of VkFloat: add_mixed(current.int64, val.float)
              else: current  # Fallback
          of VkFloat:
            case val.kind:
              of VkInt: add_mixed(val.int64, current.float)
              of VkFloat: add_float_fast(current.float, val.float)
              else: current  # Fallback
          else: current  # Fallback
        self.frame.scope.members[local_idx] = sum_result
        self.frame.push(sum_result)
        {.pop.}
      
      of IkIncLocal:
        # Increment local variable by 1
        {.push checks: off.}
        let local_idx = inst.arg0.int64.int
        let current = self.frame.scope.members[local_idx]
        if current.kind == VkInt:
          self.frame.scope.members[local_idx] = (current.int64 + 1).to_value()
        self.frame.push(self.frame.scope.members[local_idx])
        {.pop.}
      
      of IkDecLocal:
        # Decrement local variable by 1
        {.push checks: off.}
        let local_idx = inst.arg0.int64.int
        let current = self.frame.scope.members[local_idx]
        if current.kind == VkInt:
          self.frame.scope.members[local_idx] = (current.int64 - 1).to_value()
        self.frame.push(self.frame.scope.members[local_idx])
        {.pop.}
      
      of IkReturnNil:
        # Common pattern: return nil
        if self.frame.caller_frame == nil:
          return NIL
        else:
          self.cu = self.frame.caller_address.cu
          pc = self.frame.caller_address.pc
          inst = self.cu.instructions[pc].addr
          self.frame.update(self.frame.caller_frame)
          self.frame.ref_count.dec()
          self.frame.push(NIL)
          continue
      
      of IkReturnTrue:
        # Common pattern: return true
        if self.frame.caller_frame == nil:
          return TRUE
        else:
          self.cu = self.frame.caller_address.cu
          pc = self.frame.caller_address.pc
          inst = self.cu.instructions[pc].addr
          self.frame.update(self.frame.caller_frame)
          self.frame.ref_count.dec()
          self.frame.push(TRUE)
          continue
      
      of IkReturnFalse:
        # Common pattern: return false
        if self.frame.caller_frame == nil:
          return FALSE
        else:
          self.cu = self.frame.caller_address.cu
          pc = self.frame.caller_address.pc
          inst = self.cu.instructions[pc].addr
          self.frame.update(self.frame.caller_frame)
          self.frame.ref_count.dec()
          self.frame.push(FALSE)
          continue
      
      else:
        todo($inst.kind)

    # Record instruction timing
    when not defined(release):
      if self.instruction_profiling:
        let elapsed = cpuTime() - inst_start_time
        let kind = inst_kind_for_profiling  # Use the saved kind, not current inst.kind
        
        # Update or initialize profile for this instruction
        if self.instruction_profile[kind].count == 0:
          self.instruction_profile[kind] = InstructionProfile(
            count: 1,
            total_time: elapsed,
            min_time: elapsed,
            max_time: elapsed
          )
        else:
          self.instruction_profile[kind].count.inc()
          self.instruction_profile[kind].total_time += elapsed
          if elapsed < self.instruction_profile[kind].min_time:
            self.instruction_profile[kind].min_time = elapsed
          if elapsed > self.instruction_profile[kind].max_time:
            self.instruction_profile[kind].max_time = elapsed
    
    {.push checks: off}
    pc.inc()
    inst = cast[ptr Instruction](cast[int64](inst) + INST_SIZE)
    {.pop}
  {.pop.}  # End of hot VM execution loop pragma push

proc exec*(self: VirtualMachine, code: string, module_name: string): Value =
  # Initialize gene namespace if not already done
  init_gene_namespace()
  
  let compiled = parse_and_compile(code, module_name)

  let ns = new_namespace(module_name)
  
  # Add gene namespace to module namespace
  ns["gene".to_key()] = App.app.gene_ns
  
  # Add eval function to the module namespace
  # Add eval function to the namespace if it exists in global_ns
  # NOTE: This line causes issues with reference access in some cases, commenting out for now
  # if App.app.global_ns.kind == VkNamespace:
  #   let global_ns = App.app.global_ns.ref.ns
  #   if global_ns.has_key("eval".to_key()):
  #     ns["eval".to_key()] = global_ns["eval".to_key()]
  
  # Initialize frame if it doesn't exist
  if self.frame == nil:
    self.frame = new_frame(ns)
  else:
    self.frame.update(new_frame(ns))
  
  # Self is now passed as argument, not stored in frame
  self.cu = compiled

  self.exec()

include "./vm/core"
import "./vm/async"
import "./vm/generator"
# Temporarily import http module until extension loading is fixed
when not defined(noExtensions):
  import "../genex/http"
