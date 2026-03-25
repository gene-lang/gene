## Interface and Adapter compilation:
## compile_interface, compile_implement, compile_adapter_call.
## Included from compiler.nim — shares its scope.

proc compile_interface*(self: Compiler, gene: ptr Gene) =
  ## Compile an interface definition
  ## Syntax: (interface Name)
  ## For now, just creates an empty interface. Methods/props are defined in implement blocks.
  
  if gene.children.len == 0:
    not_allowed("interface requires a name")
  
  let name = gene.children[0]
  if name.kind != VkSymbol:
    not_allowed("interface name must be a symbol")
  
  # Emit the interface instruction
  # This will create the interface at runtime
  self.emit(Instruction(kind: IkInterface, arg0: name))

proc compile_implement*(self: Compiler, gene: ptr Gene) =
  ## Compile an implement block
  ## Two forms:
  ## 1. Inline (inside class): (implement InterfaceName body...)
  ## 2. External: (implement InterfaceName for ClassName body...)
  
  if gene.children.len == 0:
    not_allowed("implement requires at least an interface name")
  
  let interface_name = gene.children[0]
  if interface_name.kind != VkSymbol:
    not_allowed("interface name must be a symbol")
  
  var target_class: Value = NIL
  var body_start = 1
  var is_external = false
  
  # Check for "for" keyword: (implement Interface for Class body...)
  if gene.children.len >= 3 and gene.children[1].kind == VkSymbol and gene.children[1].str == "for":
    target_class = gene.children[2]
    body_start = 3
    is_external = true
  
  # Emit the implement instruction
  # arg0 = interface name
  # arg1 = flags (0 = inline, 1 = external)
  # If external, target_class is compiled before the instruction
  if is_external:
    self.compile(target_class)
    self.emit(Instruction(kind: IkImplement, arg0: interface_name, arg1: 1))
  else:
    self.emit(Instruction(kind: IkImplement, arg0: interface_name, arg1: 0))
  
  # If there's a body, compile it
  if gene.children.len > body_start:
    let body = new_stream_value(gene.children[body_start..^1])
    let compiled = compile_init(body,
      local_defs = true,
      module_path = self.output.module_path,
      inherited_type_descriptors = self.output.type_descriptors,
      inherited_type_aliases = self.output.type_aliases)
    let r = new_ref(VkCompiledUnit)
    r.cu = compiled
    self.emit(Instruction(kind: IkPushValue, arg0: r.to_ref_value()))
    self.emit(Instruction(kind: IkCallInit))
  else:
    self.emit(Instruction(kind: IkPushNil))

proc compile_adapter_call*(self: Compiler, gene: ptr Gene) =
  ## Compile an interface call that creates an adapter
  ## Syntax: (InterfaceName obj)
  ## 
  ## This is called when InterfaceName is used as a function call
  ## on an object that doesn't have an inline implementation.
  
  # The type (interface) is already compiled and on the stack
  # Compile the argument (the object to wrap)
  if gene.children.len == 0:
    not_allowed("adapter call requires an object to wrap")
  
  self.compile(gene.children[0])
  
  # Emit adapter instruction
  self.emit(Instruction(kind: IkAdapter))
