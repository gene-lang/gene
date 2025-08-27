import base64

# Show the code
# JIT the code (create a temporary block, reuse the frame)
# Execute the code
# Show the result
proc debug(self: VirtualMachine, args: Value): Value =
  todo()

proc println(self: VirtualMachine, args: Value): Value =
  var s = ""
  for i, k in args.gene.children:
    s &= k.str_no_quotes()
    if i < args.gene.children.len - 1:
      s &= " "
  echo s

proc print(self: VirtualMachine, args: Value): Value =
  var s = ""
  for i, k in args.gene.children:
    s &= k.str_no_quotes()
    if i < args.gene.children.len - 1:
      s &= " "
  stdout.write(s)

proc gene_assert(self: VirtualMachine, args: Value): Value =
  if args.gene.children.len > 0:
    let condition = args.gene.children[0]
    if not condition.to_bool():
      var msg = "Assertion failed"
      if args.gene.children.len > 1:
        msg = args.gene.children[1].str
      raise new_exception(types.Exception, msg)

proc base64_encode(self: VirtualMachine, args: Value): Value =
  if args.kind != VkGene or args.gene.children.len < 1:
    raise new_exception(types.Exception, "base64_encode requires a string argument")
  
  let input = args.gene.children[0]
  if input.kind != VkString:
    raise new_exception(types.Exception, "base64_encode requires a string argument")
  
  let encoded = base64.encode(input.str)
  return encoded.to_value()

proc base64_decode(self: VirtualMachine, args: Value): Value =
  if args.kind != VkGene or args.gene.children.len < 1:
    raise new_exception(types.Exception, "base64_decode requires a string argument")
  
  let input = args.gene.children[0]
  if input.kind != VkString:
    raise new_exception(types.Exception, "base64_decode requires a string argument")
  
  try:
    let decoded = base64.decode(input.str)
    return decoded.to_value()
  except ValueError as e:
    raise new_exception(types.Exception, "Invalid base64 string: " & e.msg)

proc trace_start(self: VirtualMachine, args: Value): Value =
  self.trace = true
  self.frame.push(NIL)

proc trace_end(self: VirtualMachine, args: Value): Value =
  self.trace = false
  self.frame.push(NIL)

proc print_stack(self: VirtualMachine, args: Value): Value =
  var s = "Stack: "
  for i, reg in self.frame.stack:
    if i > 0:
      s &= ", "
    if i == self.frame.stack_index.int:
      s &= "=> "
    s &= $self.frame.stack[i]
  echo s
  self.frame.push(NIL)

proc print_instructions(self: VirtualMachine, args: Value): Value =
  echo self.cu
  self.frame.push(NIL)

proc to_ctor(node: Value): Function =
  let name = "ctor"

  let matcher = new_arg_matcher()
  matcher.parse(node.gene.children[0])
  matcher.check_hint()

  var body: seq[Value] = @[]
  for i in 1..<node.gene.children.len:
    body.add node.gene.children[i]

  # body = wrap_with_try(body)
  result = new_fn(name, matcher, body)

proc class_ctor(self: VirtualMachine, args: Value): Value =
  let fn = to_ctor(args)
  fn.ns = self.frame.ns
  let r = new_ref(VkFunction)
  r.fn = fn
  # Get class from first argument (bound method self)
  let x = args.gene.type.ref.bound_method.self
  if x.kind == VkClass:
    x.ref.class.constructor = r.to_ref_value()
  else:
    not_allowed("Constructor can only be defined on classes")

proc class_fn(self: VirtualMachine, args: Value): Value =
  let x = args.gene.type.ref.bound_method.self
  # define a fn like method on a class
  let fn = to_function(args)

  let r = new_ref(VkFunction)
  r.fn = fn
  let m = Method(
     name: fn.name,
    callable: r.to_ref_value(),
  )
  case x.kind:
  of VkClass:
    let class = x.ref.class
    m.class = class
    fn.ns = class.ns
    class.methods[m.name.to_key()] = m
  # of VkMixin:
  #   fn.ns = x.mixin.ns
  #   x.mixin.methods[m.name] = m
  else:
    not_allowed()

proc vm_compile(self: VirtualMachine, args: Value): Value {.gcsafe.} =
  {.cast(gcsafe).}:
    let compiler = Compiler(output: new_compilation_unit())
    let scope_tracker = self.frame.caller_frame.scope.tracker
    # compiler.output.scope_tracker = scope_tracker
    compiler.scope_trackers.add(scope_tracker)
    compiler.compile(args.gene.children[0])
    let instrs = new_ref(VkArray)
    for instr in compiler.output.instructions:
      instrs.arr.add instr.to_value()
    result = instrs.to_ref_value()

proc vm_push(self: VirtualMachine, args: Value): Value =
  new_instr(IkPushValue, args.gene.children[0])

proc vm_add(self: VirtualMachine, args: Value): Value =
  new_instr(IkAdd)

proc current_ns(self: VirtualMachine, args: Value): Value =
  # Return the current namespace
  let r = new_ref(VkNamespace)
  r.ns = self.frame.ns
  result = r.to_ref_value()

# vm_not function removed - now handled by IkNot instruction at compile time

# vm_spread function removed - ... is now handled as compile-time keyword

proc vm_parse(self: VirtualMachine, args: Value): Value =
  # Parse Gene code from string
  if args.gene.children.len != 1:
    not_allowed("$parse expects exactly 1 argument")
  let arg = args.gene.children[0]
  case arg.kind:
    of VkString:
      let code = arg.str
      # Use the actual Gene parser to parse the code
      try:
        let parsed = read_all(code)
        if parsed.len > 0:
          return parsed[0]
        else:
          return NIL
      except:
        # Fallback to simple parsing for basic literals
        case code:
          of "true": 
            return TRUE
          of "false": 
            return FALSE
          of "nil": 
            return NIL
          else:
            # Try to parse as number
            try:
              let int_val = parseInt(code)
              return int_val.to_value()
            except ValueError:
              try:
                let float_val = parseFloat(code)
                return float_val.to_value()
              except ValueError:
                # Return as symbol for now
                return code.to_symbol_value()
    else:
      not_allowed("$parse expects a string argument")

proc vm_with(self: VirtualMachine, args: Value): Value =
  # $with sets self to the first argument and executes the body, returns the original value
  if args.gene.children.len < 2:
    not_allowed("$with expects at least 2 arguments")
  
  let original_value = args.gene.children[0]
  # Self is now managed through arguments, not frame field
  # The compiler should handle passing the value as the first argument
  
  # Execute the body (all arguments after the first)
  for i in 1..<args.gene.children.len:
    discard # Body execution would happen during compilation/evaluation
  
  return original_value

proc vm_tap(self: VirtualMachine, args: Value): Value =
  # $tap executes the body with self set to the first argument, returns the original value
  if args.gene.children.len < 2:
    not_allowed("$tap expects at least 2 arguments")
  
  let original_value = args.gene.children[0]
  
  # If second argument is a symbol, bind it to the value
  var binding_name: string = ""
  var body_start_index = 1
  if args.gene.children.len > 2 and args.gene.children[1].kind == VkSymbol:
    binding_name = args.gene.children[1].str
    body_start_index = 2
  
  # Self is now managed through arguments
  # The compiler should handle passing the value as the first argument
  
  # Execute the body
  for i in body_start_index..<args.gene.children.len:
    discard # Body execution would happen during compilation/evaluation
  
  return original_value

# String interpolation handler
proc vm_str_interpolation(self: VirtualMachine, args: Value): Value =
  # #Str concatenates all arguments as strings
  if args.kind != VkGene:
    return "".to_value()
  
  var result = ""
  for child in args.gene.children:
    case child.kind:
    of VkString:
      result.add(child.str)
    of VkInt:
      result.add($child.int64)
    of VkBool:
      result.add(if child.bool: "true" else: "false")
    of VkNil:
      result.add("nil")
    of VkChar:
      result.add($child.char)
    of VkFloat:
      result.add($child.float)
    else:
      # For other types, use $ operator
      result.add($child)
  
  return result.to_value()

proc vm_eval(self: VirtualMachine, args: Value): Value {.gcsafe.} =
  {.cast(gcsafe).}:
    # This function is not used - eval is handled by IkEval instruction
    # The compiler generates IkEval instructions for each argument
    not_allowed("vm_eval should not be called directly")

# TODO: Implement while loop properly - needs compiler-level support like loop/if


# Sleep functions
proc gene_sleep(self: VirtualMachine, args: Value): Value =
  if args.kind != VkGene or args.gene.children.len < 1:
    raise new_exception(types.Exception, "sleep requires 1 argument")

  let duration_arg = args.gene.children[0]
  var duration_ms: int

  case duration_arg.kind:
    of VkInt:
      duration_ms = duration_arg.int64.int
    of VkFloat:
      duration_ms = (duration_arg.float64 * 1000).int
    else:
      raise new_exception(types.Exception, "sleep requires a number (milliseconds)")

  # Use Nim's sleep function (takes milliseconds)
  sleep(duration_ms)
  return NIL

proc gene_sleep_async(self: VirtualMachine, args: Value): Value =
  if args.kind != VkGene or args.gene.children.len < 1:
    raise new_exception(types.Exception, "sleep_async requires 1 argument")

  let duration_arg = args.gene.children[0]
  var duration_ms: int

  case duration_arg.kind:
    of VkInt:
      duration_ms = duration_arg.int64.int
    of VkFloat:
      duration_ms = (duration_arg.float64 * 1000).int
    else:
      raise new_exception(types.Exception, "sleep_async requires a number (milliseconds)")

  # Create a Gene Future
  let gene_future_val = new_future_value()
  let gene_future = gene_future_val.ref.future

  # For now, perform synchronous sleep and complete immediately
  # In a real implementation, this would use async timers
  sleep(duration_ms)
  gene_future.complete(NIL)

  return gene_future_val

# I/O functions
proc file_read(self: VirtualMachine, args: Value): Value =
  if args.kind != VkGene or args.gene.children.len < 1:
    raise new_exception(types.Exception, "File/read requires 1 argument")

  let path_arg = args.gene.children[0]
  if path_arg.kind != VkString:
    raise new_exception(types.Exception, "File/read requires a string path")

  let path = path_arg.str
  try:
    let content = readFile(path)
    return content.to_value()
  except IOError as e:
    raise new_exception(types.Exception, "Failed to read file '" & path & "': " & e.msg)

proc file_write(self: VirtualMachine, args: Value): Value =
  if args.kind != VkGene or args.gene.children.len < 2:
    raise new_exception(types.Exception, "File/write requires 2 arguments")

  let path_arg = args.gene.children[0]
  let content_arg = args.gene.children[1]

  if path_arg.kind != VkString:
    raise new_exception(types.Exception, "File/write requires a string path")
  if content_arg.kind != VkString:
    raise new_exception(types.Exception, "File/write requires string content")

  let path = path_arg.str
  let content = content_arg.str

  try:
    writeFile(path, content)
    return NIL
  except IOError as e:
    raise new_exception(types.Exception, "Failed to write file '" & path & "': " & e.msg)

proc file_read_async(self: VirtualMachine, args: Value): Value =
  if args.kind != VkGene or args.gene.children.len < 1:
    raise new_exception(types.Exception, "File/read_async requires 1 argument")

  let path_arg = args.gene.children[0]
  if path_arg.kind != VkString:
    raise new_exception(types.Exception, "File/read_async requires a string path")

  let path = path_arg.str

  # Create a Gene Future
  let gene_future_val = new_future_value()
  let gene_future = gene_future_val.ref.future

  # For now, perform synchronous read and complete immediately
  try:
    let content = readFile(path)
    gene_future.complete(content.to_value())
  except IOError as e:
    let error_msg = "Failed to read file '" & path & "': " & e.msg
    gene_future.fail(error_msg.to_value())

  return gene_future_val

proc file_write_async(self: VirtualMachine, args: Value): Value =
  if args.kind != VkGene or args.gene.children.len < 2:
    raise new_exception(types.Exception, "File/write_async requires 2 arguments")

  let path_arg = args.gene.children[0]
  let content_arg = args.gene.children[1]

  if path_arg.kind != VkString:
    raise new_exception(types.Exception, "File/write_async requires a string path")
  if content_arg.kind != VkString:
    raise new_exception(types.Exception, "File/write_async requires string content")

  let path = path_arg.str
  let content = content_arg.str

  # Create a Gene Future
  let gene_future_val = new_future_value()
  let gene_future = gene_future_val.ref.future

  # For now, perform synchronous write and complete immediately
  try:
    writeFile(path, content)
    gene_future.complete(NIL)
  except IOError as e:
    let error_msg = "Failed to write file '" & path & "': " & e.msg
    gene_future.fail(error_msg.to_value())

  return gene_future_val

proc register_io_functions*() =
  # Get the io namespace that was created in init_app_and_vm
  let io_key = "io".to_key()
  if not App.app.gene_ns.ns.has_key(io_key):
    return  # io namespace doesn't exist
  
  let io_val = App.app.gene_ns.ns[io_key]
  if io_val.kind != VkNamespace:
    return  # io is not a namespace
  
  let io_ns = io_val.ns
  
  # Add synchronous functions
  var read_ref = new_ref(VkNativeFn)
  read_ref.native_fn = file_read
  io_ns["read".to_key()] = read_ref.to_ref_value()

  var write_ref = new_ref(VkNativeFn)
  write_ref.native_fn = file_write
  io_ns["write".to_key()] = write_ref.to_ref_value()

  # Add asynchronous functions
  var read_async_ref = new_ref(VkNativeFn)
  read_async_ref.native_fn = file_read_async
  io_ns["read_async".to_key()] = read_async_ref.to_ref_value()

  var write_async_ref = new_ref(VkNativeFn)
  write_async_ref.native_fn = file_write_async
  io_ns["write_async".to_key()] = write_async_ref.to_ref_value()

proc init_gene_namespace*() =
  if types.gene_namespace_initialized:
    return
  types.gene_namespace_initialized = true
  # Initialize basic classes needed by get_class
  var r: ptr Reference
  
  # nil_class
  let nil_class = new_class("Nil")
  r = new_ref(VkClass)
  r.class = nil_class
  App.app.nil_class = r.to_ref_value()
  
  # bool_class
  let bool_class = new_class("Bool")
  r = new_ref(VkClass)
  r.class = bool_class
  App.app.bool_class = r.to_ref_value()
  
  # int_class
  let int_class = new_class("Int")
  r = new_ref(VkClass)
  r.class = int_class
  App.app.int_class = r.to_ref_value()
  
  # float_class
  let float_class = new_class("Float")
  r = new_ref(VkClass)
  r.class = float_class
  App.app.float_class = r.to_ref_value()
  
  # string_class
  let string_class = new_class("String")
  
  # Add String methods
  # append method
  proc string_append(self: VirtualMachine, args: Value): Value =
    if args.kind != VkGene or args.gene.children.len < 2:
      raise new_exception(types.Exception, "String.append requires 2 arguments (self and string to append)")
    
    let self_arg = args.gene.children[0]
    let append_arg = args.gene.children[1]
    
    if self_arg.kind != VkString:
      raise new_exception(types.Exception, "append can only be called on a string")
    if append_arg.kind != VkString:
      raise new_exception(types.Exception, "append requires a string argument")
    
    let result = self_arg.str & append_arg.str
    return result.to_value()
  
  var append_fn = new_ref(VkNativeFn)
  append_fn.native_fn = string_append
  string_class.def_native_method("append", append_fn.native_fn)
  
  # length method
  proc string_length(self: VirtualMachine, args: Value): Value =
    if args.kind != VkGene or args.gene.children.len < 1:
      raise new_exception(types.Exception, "String.length requires self argument")
    
    let self_arg = args.gene.children[0]
    if self_arg.kind != VkString:
      raise new_exception(types.Exception, "length can only be called on a string")
    
    return self_arg.str.len.int64.to_value()
  
  var length_fn = new_ref(VkNativeFn)
  length_fn.native_fn = string_length
  string_class.def_native_method("length", length_fn.native_fn)
  
  # to_upper method
  proc string_to_upper(self: VirtualMachine, args: Value): Value =
    if args.kind != VkGene or args.gene.children.len < 1:
      raise new_exception(types.Exception, "String.to_upper requires self argument")
    
    let self_arg = args.gene.children[0]
    if self_arg.kind != VkString:
      raise new_exception(types.Exception, "to_upper can only be called on a string")
    
    return self_arg.str.toUpperAscii().to_value()
  
  var to_upper_fn = new_ref(VkNativeFn)
  to_upper_fn.native_fn = string_to_upper
  string_class.def_native_method("to_upper", to_upper_fn.native_fn)
  
  # to_lower method
  proc string_to_lower(self: VirtualMachine, args: Value): Value =
    if args.kind != VkGene or args.gene.children.len < 1:
      raise new_exception(types.Exception, "String.to_lower requires self argument")
    
    let self_arg = args.gene.children[0]
    if self_arg.kind != VkString:
      raise new_exception(types.Exception, "to_lower can only be called on a string")
    
    return self_arg.str.toLowerAscii().to_value()
  
  var to_lower_fn = new_ref(VkNativeFn)
  to_lower_fn.native_fn = string_to_lower
  string_class.def_native_method("to_lower", to_lower_fn.native_fn)
  
  r = new_ref(VkClass)
  r.class = string_class
  App.app.string_class = r.to_ref_value()
  
  # symbol_class
  let symbol_class = new_class("Symbol")
  r = new_ref(VkClass)
  r.class = symbol_class
  App.app.symbol_class = r.to_ref_value()
  
  # complex_symbol_class
  let complex_symbol_class = new_class("ComplexSymbol")
  r = new_ref(VkClass)
  r.class = complex_symbol_class
  App.app.complex_symbol_class = r.to_ref_value()
  
  # array_class
  let array_class = new_class("Array")
  r = new_ref(VkClass)
  r.class = array_class
  App.app.array_class = r.to_ref_value()
  
  # Add array methods
  proc vm_array_add(self: VirtualMachine, args: Value): Value =
    # First argument is the array (self), second is the value to add
    let arr = args.gene.children[0]
    let value = if args.gene.children.len > 1: args.gene.children[1] else: NIL
    if arr.kind == VkArray:
      arr.ref.arr.add(value)
    return arr
  
  array_class.def_native_method("add", vm_array_add)
  
  proc vm_array_size(self: VirtualMachine, args: Value): Value =
    # First argument is the array (self)
    let arr = args.gene.children[0]
    if arr.kind == VkArray:
      return arr.ref.arr.len.to_value()
    return 0.to_value()
  
  array_class.def_native_method("size", vm_array_size)
  
  proc vm_array_get(self: VirtualMachine, args: Value): Value =
    # First argument is the array (self), second is the index
    let arr = args.gene.children[0]
    let index = if args.gene.children.len > 1: args.gene.children[1] else: 0.to_value()
    if arr.kind == VkArray and index.kind == VkInt:
      let idx = index.int64.int
      if idx >= 0 and idx < arr.ref.arr.len:
        return arr.ref.arr[idx]
    return NIL
  
  array_class.def_native_method("get", vm_array_get)
  
  # map_class
  let map_class = new_class("Map")
  r = new_ref(VkClass)
  r.class = map_class
  App.app.map_class = r.to_ref_value()
  
  # Add map methods
  proc vm_map_contains(self: VirtualMachine, args: Value): Value =
    # First argument is the map (self), second is the key
    let map = args.gene.children[0]
    let key = if args.gene.children.len > 1: args.gene.children[1] else: NIL
    if map.kind == VkMap and key.kind == VkString:
      return map.ref.map.hasKey(key.str.to_key()).to_value()
    return false.to_value()
  
  map_class.def_native_method("contains", vm_map_contains)
  
  # set_class
  let set_class = new_class("Set")
  r = new_ref(VkClass)
  r.class = set_class
  App.app.set_class = r.to_ref_value()
  
  # gene_class
  let gene_class = new_class("Gene")
  r = new_ref(VkClass)
  r.class = gene_class
  App.app.gene_class = r.to_ref_value()
  
  # function_class
  let function_class = new_class("Function")
  r = new_ref(VkClass)
  r.class = function_class
  App.app.function_class = r.to_ref_value()
  
  # char_class
  let char_class = new_class("Char")
  r = new_ref(VkClass)
  r.class = char_class
  App.app.char_class = r.to_ref_value()
  
  # application_class
  let application_class = new_class("Application")
  r = new_ref(VkClass)
  r.class = application_class
  App.app.application_class = r.to_ref_value()
  
  # package_class
  let package_class = new_class("Package")
  r = new_ref(VkClass)
  r.class = package_class
  App.app.package_class = r.to_ref_value()
  
  # namespace_class
  let namespace_class = new_class("Namespace")
  r = new_ref(VkClass)
  r.class = namespace_class
  App.app.namespace_class = r.to_ref_value()

  App.app.gene_ns.ns["debug".to_key()] = debug
  App.app.gene_ns.ns["println".to_key()] = println
  App.app.gene_ns.ns["print".to_key()] = print
  App.app.gene_ns.ns["assert".to_key()] = gene_assert
  App.app.gene_ns.ns["base64_encode".to_key()] = base64_encode
  App.app.gene_ns.ns["base64_decode".to_key()] = base64_decode
  App.app.gene_ns.ns["trace_start".to_key()] = trace_start
  App.app.gene_ns.ns["trace_end".to_key()] = trace_end
  App.app.gene_ns.ns["print_stack".to_key()] = print_stack
  App.app.gene_ns.ns["print_instructions".to_key()] = print_instructions
  App.app.gene_ns.ns["ns".to_key()] = current_ns
  # not and ... are now handled by compile-time instructions, no need to register
  App.app.gene_ns.ns["parse".to_key()] = vm_parse  # $parse translates to gene/parse
  App.app.gene_ns.ns["with".to_key()] = vm_with    # $with translates to gene/with
  App.app.gene_ns.ns["tap".to_key()] = vm_tap      # $tap translates to gene/tap
  App.app.gene_ns.ns["eval".to_key()] = vm_eval    # eval function


  # Add sleep functions directly to gene namespace
  var sleep_ref = new_ref(VkNativeFn)
  sleep_ref.native_fn = gene_sleep
  App.app.gene_ns.ns["sleep".to_key()] = sleep_ref.to_ref_value()

  var sleep_async_ref = new_ref(VkNativeFn)
  sleep_async_ref.native_fn = gene_sleep_async
  App.app.gene_ns.ns["sleep_async".to_key()] = sleep_async_ref.to_ref_value()
  
  # Also add to global namespace
  App.app.global_ns.ns["parse".to_key()] = vm_parse
  App.app.global_ns.ns["with".to_key()] = vm_with
  App.app.global_ns.ns["tap".to_key()] = vm_tap
  App.app.global_ns.ns["eval".to_key()] = vm_eval
  App.app.global_ns.ns["#Str".to_key()] = vm_str_interpolation
  App.app.global_ns.ns["not_found".to_key()] = NOT_FOUND
  
  

  let class = new_class("Class")
  class.def_native_macro_method "ctor", class_ctor
  class.def_native_macro_method "fn", class_fn
  
  
  r = new_ref(VkClass)
  r.class = class
  App.app.class_class = r.to_ref_value()

  let vm_ns = new_namespace("vm")
  App.app.gene_ns.ns["vm".to_key()] = vm_ns.to_value()
  vm_ns["compile".to_key()] = NativeFn(vm_compile)
  vm_ns["PUSH".to_key()] = vm_push
  vm_ns["ADD" .to_key()] = vm_add
