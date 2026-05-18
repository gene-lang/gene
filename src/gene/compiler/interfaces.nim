## Interface and Adapter compilation:
## compile_interface, compile_implement.
## Included from compiler.nim — shares its scope.

proc interface_prop_name(input: Value): string =
  if input.kind notin {VkSymbol, VkString}:
    not_allowed("property name must be a symbol or string")
  result = input.str
  if result.ends_with(":"):
    result = result[0..^2]

proc interface_type_id_array(items: seq[CallableParamDesc]): Value =
  var values: seq[Value] = @[]
  for item in items:
    var param_values: seq[Value] = @[]
    param_values.add(ord(item.kind).to_value())
    param_values.add(item.keyword_name.to_value())
    param_values.add(item.type_id.int.to_value())
    values.add(new_array_value(param_values))
  new_array_value(values)

proc interface_method_metadata(name: Value, params: seq[CallableParamDesc],
                               return_type_id: TypeId): Value =
  result = new_gene_value()
  result.gene.type = "interface_method".to_symbol_value()
  result.gene.children.add(name)
  result.gene.children.add(interface_type_id_array(params))
  result.gene.children.add(return_type_id.int.to_value())

proc interface_prop_metadata(name: string, type_id: TypeId): Value =
  result = new_gene_value()
  result.gene.type = "interface_prop".to_symbol_value()
  result.gene.children.add(name.to_value())
  result.gene.children.add(type_id.int.to_value())

proc interface_header_metadata(name: Value, parents: seq[Value], overrides: seq[Value]): Value =
  if parents.len == 0 and overrides.len == 0:
    return name
  result = new_gene_value()
  result.gene.type = "interface".to_symbol_value()
  result.gene.children.add(name)
  result.gene.children.add(new_array_value(parents))
  result.gene.children.add(new_array_value(overrides))

proc callable_args_with_self(args: Value, context: string): Value =
  if args.kind != VkArray:
    not_allowed(context & " requires an array argument list; use [] for no arguments")
  var method_args = new_array_value()
  let src = array_data(args)
  if src.len == 0:
    array_data(method_args).add("self".to_symbol_value())
  elif src[0].kind == VkSymbol and src[0].str == "self":
    for arg in src:
      array_data(method_args).add(arg)
  else:
    array_data(method_args).add("self".to_symbol_value())
    for arg in src:
      array_data(method_args).add(arg)
  method_args

proc interface_param_descs(self: Compiler, args: Value): seq[CallableParamDesc] =
  if args.kind != VkArray:
    return
  var type_desc_index = initTable[string, TypeId]()
  ensure_type_desc_index(self.output.type_descriptors, type_desc_index)
  let items = array_data(args)
  var i = 0
  while i < items.len:
    let item = items[i]
    if item.kind == VkSymbol and item.str == "=":
      i += 2
      continue
    if item.kind == VkSymbol:
      if item.str == "...":
        not_allowed("Positional rest must follow a named parameter")
      var raw = item.str
      var keyword_name = ""
      var kind = CpkPositional
      var has_type = false
      if raw.endsWith(":"):
        has_type = true
        raw = raw[0..^2]
      if raw.endsWith("..."):
        kind = CpkPositionalRest
        raw = raw[0..^4]
      if i + 1 < items.len and items[i + 1].kind == VkSymbol and items[i + 1].str == "...":
        if kind == CpkPositionalRest:
          not_allowed("Duplicate rest marker for parameter " & raw)
        kind = CpkPositionalRest
        i += 1
      if raw.startsWith("^"):
        if raw.len >= 2 and (raw[1] == '^' or raw[1] == '!'):
          keyword_name = raw[2..^1]
        else:
          keyword_name = raw[1..^1]
        kind = if kind == CpkPositionalRest: CpkKeywordRest else: CpkKeyword
      var type_id = BUILTIN_TYPE_ANY_ID
      if has_type:
        if i + 1 >= items.len:
          not_allowed("Missing type for parameter " & raw)
        type_id = resolve_type_value_to_id_with_index(
          items[i + 1],
          self.output.type_descriptors,
          type_desc_index,
          self.output.type_aliases,
          initTable[string, TypeId](),
          self.output.module_path)
        i += 1
      result.add(CallableParamDesc(kind: kind, keyword_name: keyword_name, type_id: type_id))
      i += 1
    elif item.kind == VkArray:
      result.add(CallableParamDesc(kind: CpkPositional, keyword_name: "", type_id: BUILTIN_TYPE_ANY_ID))
      i += 1
    else:
      i += 1

proc compile_interface_method_decl(self: Compiler, gene: ptr Gene) =
  if gene.children.len < 2:
    not_allowed("interface method requires a name and argument list")

  let name = gene.children[0]
  if name.kind notin {VkSymbol, VkString}:
    not_allowed("interface method name must be a symbol or string")

  if gene.children[1].kind != VkArray:
    not_allowed("interface method requires an array argument list; use [] for no arguments")

  var body_start = 2
  if body_start < gene.children.len and gene.children[body_start].kind == VkSymbol and gene.children[body_start].str == "->":
    if body_start + 1 >= gene.children.len:
      not_allowed("Missing return type after ->")
    body_start += 2
  if body_start < gene.children.len and gene.children[body_start].kind == VkSymbol and gene.children[body_start].str == "!":
    if body_start + 1 >= gene.children.len:
      not_allowed("Missing effects list after !")
    body_start += 2

  var return_type_id = NO_TYPE_ID
  var scan = 2
  if scan < gene.children.len and gene.children[scan].kind == VkSymbol and gene.children[scan].str == "->":
    return_type_id = resolve_type_value_to_id(
      gene.children[scan + 1],
      self.output.type_descriptors,
      self.output.type_aliases,
      self.output.module_path)
  let params = self.interface_param_descs(gene.children[1])

  let has_default = body_start < gene.children.len
  if has_default:
    var fn_value = new_gene_value()
    fn_value.gene.type = "fn".to_symbol_value()
    for k, v in gene.props:
      fn_value.gene.props[k] = v
    fn_value.gene.children.add(name)
    fn_value.gene.children.add(callable_args_with_self(gene.children[1], "interface method"))
    for i in 2..<body_start:
      fn_value.gene.children.add(gene.children[i])
    for i in body_start..<gene.children.len:
      fn_value.gene.children.add(gene.children[i])
    self.compile_fn(fn_value, define_binding = false)

  self.emit(Instruction(
    kind: IkInterfaceMethod,
    arg0: interface_method_metadata(name, params, return_type_id),
    arg1: (if has_default: 1 else: 0).int32,
  ))

proc compile_interface_prop_decl(self: Compiler, gene: ptr Gene) =
  if gene.children.len == 0:
    not_allowed("interface prop requires a name")

  let prop_name = interface_prop_name(gene.children[0])
  let readonly =
    gene.props.has_key("readonly".to_key()) and
    gene.props["readonly".to_key()] notin [FALSE, NIL]

  var type_id = NO_TYPE_ID
  if gene.children.len > 1:
    type_id = resolve_type_value_to_id(
      gene.children[1],
      self.output.type_descriptors,
      self.output.type_aliases,
      self.output.module_path)

  self.emit(
    Instruction(
      kind: IkInterfaceProp,
      arg0: interface_prop_metadata(prop_name, type_id),
      arg1: (if readonly: 1 else: 0).int32,
    )
  )

proc compile_interface_field_decl(self: Compiler, gene: ptr Gene) =
  if gene.children.len == 0:
    not_allowed("field requires a name")
  let field_name = interface_prop_name(gene.children[0])
  let readonly =
    gene.props.has_key("readonly".to_key()) and
    gene.props["readonly".to_key()] notin [FALSE, NIL]
  var type_id = NO_TYPE_ID
  if gene.children.len > 1:
    type_id = resolve_type_value_to_id(
      gene.children[1],
      self.output.type_descriptors,
      self.output.type_aliases,
      self.output.module_path)
  self.emit(Instruction(kind: IkInterfaceProp, arg0: interface_prop_metadata(field_name, type_id), arg1: (if readonly: 1 else: 0).int32))

proc external_implement_args_with_self(args: Value): Value =
  callable_args_with_self(args, "external implement methods and ctors")

proc compile_external_implement_method(self: Compiler, gene: ptr Gene) =
  if gene.children.len < 2:
    not_allowed("method requires a name and argument list")

  let name = gene.children[0]
  if name.kind != VkSymbol:
    not_allowed("method name must be a symbol")

  let parsed_name = split_generic_definition_name(name.str)
  let method_name = parsed_name.base_name.to_symbol_value()

  var fn_value = new_gene_value()
  fn_value.gene.type = "fn".to_symbol_value()
  for k, v in gene.props:
    fn_value.gene.props[k] = v

  # Preserve the original method name on the lowered function so generic method
  # parameters continue to be visible to to_function(), but register the stripped
  # base name on the implementation mapping.
  fn_value.gene.children.add(name)
  fn_value.gene.children.add(external_implement_args_with_self(gene.children[1]))

  if gene.children.len == 2:
    fn_value.gene.children.add(NIL)
  else:
    for i in 2..<gene.children.len:
      fn_value.gene.children.add(gene.children[i])

  self.compile_fn(fn_value, define_binding = false)
  self.emit(Instruction(kind: IkImplementMethod, arg0: method_name))

proc compile_external_implement_ctor(self: Compiler, gene: ptr Gene) =
  if gene.children.len == 0:
    not_allowed("ctor requires an argument list")

  var fn_value = new_gene_value()
  fn_value.gene.type = "fn".to_symbol_value()
  for k, v in gene.props:
    fn_value.gene.props[k] = v

  fn_value.gene.children.add("__adapter_ctor__".to_symbol_value())
  fn_value.gene.children.add(external_implement_args_with_self(gene.children[0]))

  if gene.children.len == 1:
    fn_value.gene.children.add(NIL)
  else:
    for i in 1..<gene.children.len:
      fn_value.gene.children.add(gene.children[i])

  self.compile_fn(fn_value, define_binding = false)
  self.emit(Instruction(kind: IkImplementCtor))

proc adapter_field_metadata(field_name: string, extra: Value = NIL): Value =
  result = new_gene_value()
  result.gene.type = "adapter_field".to_symbol_value()
  result.gene.children.add(field_name.to_symbol_value())
  if extra != NIL:
    result.gene.children.add(extra)

proc adapter_accessor_args(accessor: ptr Gene, field_name, accessor_name: string, expected_len: int): Value =
  if accessor.children.len == 0 or accessor.children[0].kind != VkArray:
    not_allowed("adapter field " & field_name & " " & accessor_name & " accessor requires an array argument list")
  result = accessor.children[0]
  let args = array_data(result)
  if args.len != expected_len:
    not_allowed("adapter field " & field_name & " " & accessor_name & " accessor has invalid arity")
  for arg in args:
    if arg.kind != VkSymbol:
      not_allowed("adapter field " & field_name & " " & accessor_name & " accessor arguments must be symbols")

proc compile_external_implement_field_accessor(self: Compiler, field_name: string, accessor: ptr Gene, accessor_name: string) =
  let args = adapter_accessor_args(accessor, field_name, accessor_name, if accessor_name == "get": 0 else: 1)

  var fn_value = new_gene_value()
  fn_value.gene.type = "fn".to_symbol_value()
  fn_value.gene.children.add(("__adapter_" & accessor_name & "_" & field_name).to_symbol_value())
  fn_value.gene.children.add(external_implement_args_with_self(args))

  if accessor.children.len == 1:
    fn_value.gene.children.add(NIL)
  else:
    for i in 1..<accessor.children.len:
      fn_value.gene.children.add(accessor.children[i])

  self.compile_fn(fn_value, define_binding = false)

proc compile_external_implement_field(self: Compiler, gene: ptr Gene) =
  if gene.children.len == 0:
    not_allowed("adapter field mapping requires a name")

  let field_name = interface_prop_name(gene.children[0])
  let from_key = "from".to_key()
  let has_from = gene.props.has_key(from_key)

  if has_from:
    if gene.children.len != 1:
      not_allowed("adapter field " & field_name & " cannot mix ^from with accessor or owned-field forms")
    let from_value = gene.props[from_key]
    if from_value.kind notin {VkSymbol, VkString}:
      not_allowed("adapter field " & field_name & " ^from target must be a member name")
    self.emit(Instruction(
      kind: IkImplementField,
      arg0: adapter_field_metadata(field_name, from_value.str.to_symbol_value()),
      arg1: ord(AfiDirect).int32,
    ))
    return

  if gene.children.len == 2 and gene.children[1].kind != VkGene:
    self.emit(Instruction(
      kind: IkImplementField,
      arg0: adapter_field_metadata(field_name, gene.children[1]),
      arg1: ord(AfiOwned).int32,
    ))
    return

  var getter: ptr Gene = nil
  var setter: ptr Gene = nil
  if gene.children.len < 2:
    not_allowed("adapter field " & field_name & " requires ^from, accessor blocks, or an owned field type")

  for i in 1..<gene.children.len:
    let child = gene.children[i]
    if child.kind != VkGene or child.gene == nil or child.gene.type.kind != VkSymbol:
      not_allowed("adapter field " & field_name & " has an invalid accessor form")
    case child.gene.type.str
    of "get":
      if getter != nil:
        not_allowed("adapter field " & field_name & " declares duplicate get accessors")
      getter = child.gene
    of "set":
      if setter != nil:
        not_allowed("adapter field " & field_name & " declares duplicate set accessors")
      setter = child.gene
    else:
      not_allowed("adapter field " & field_name & " has unknown accessor form: " & child.gene.type.str)

  if getter == nil:
    not_allowed("adapter field " & field_name & " accessor mapping requires a get accessor")

  self.compile_external_implement_field_accessor(field_name, getter, "get")
  var flags = ord(AfiAccessor).int32
  if setter != nil:
    self.compile_external_implement_field_accessor(field_name, setter, "set")
    flags = flags or 4'i32

  self.emit(Instruction(
    kind: IkImplementField,
    arg0: adapter_field_metadata(field_name),
    arg1: flags,
  ))

proc compile_interface*(self: Compiler, gene: ptr Gene) =
  ## Compile an interface definition
  ## Syntax: (interface Name body...)
  
  if gene.children.len == 0:
    not_allowed("interface requires a name")
  
  let name = gene.children[0]
  if name.kind != VkSymbol:
    not_allowed("interface name must be a symbol")

  var parent_interfaces: seq[Value] = @[]
  var body_start = 1
  if gene.children.len >= 3 and gene.children[1].kind == VkSymbol and gene.children[1].str == "extends":
    case gene.children[2].kind
    of VkSymbol:
      parent_interfaces.add(gene.children[2])
    of VkArray:
      for item in array_data(gene.children[2]):
        if item.kind != VkSymbol:
          not_allowed("interface extends expects interface symbols")
        parent_interfaces.add(item)
    else:
      not_allowed("interface extends expects an interface symbol or array of interface symbols")
    body_start = 3

  var method_overrides: seq[Value] = @[]
  for i in body_start..<gene.children.len:
    let child = gene.children[i]
    if child.kind == VkGene and child.gene != nil and child.gene.type.kind == VkSymbol and
       child.gene.type.str == "method" and child.gene.children.len > 0 and
       child.gene.children[0].kind == VkSymbol:
      let parsed = split_generic_definition_name(child.gene.children[0].str)
      method_overrides.add(parsed.base_name.to_symbol_value())

  # Emit the interface instruction
  self.emit(Instruction(kind: IkInterface, arg0: interface_header_metadata(name, parent_interfaces, method_overrides)))

  for i in body_start..<gene.children.len:
    let child = gene.children[i]
    if child.kind != VkGene or child.gene == nil or child.gene.type.kind != VkSymbol:
      not_allowed("interface body only supports method and field declarations")
    case child.gene.type.str
    of "method":
      self.compile_interface_method_decl(child.gene)
    of "field":
      self.compile_interface_field_decl(child.gene)
    of "prop":
      self.compile_interface_prop_decl(child.gene)
    else:
      not_allowed("unsupported interface member: " & child.gene.type.str)

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
  let has_body = gene.children.len > body_start
  
  # Emit the implement instruction
  # arg0 = interface name
  # arg1 bit 0 = external, bit 1 = has body
  # If external, target_class is compiled before the instruction
  let flags = ((if is_external: 1 else: 0) or (if has_body: 2 else: 0)).int32
  if is_external:
    self.compile(target_class)
    self.emit(Instruction(kind: IkImplement, arg0: interface_name, arg1: flags))
  else:
    self.emit(Instruction(kind: IkImplement, arg0: interface_name, arg1: flags))
  
  # If there's a body, compile it
  if has_body:
    if is_external:
      for i in body_start..<gene.children.len:
        let child = gene.children[i]
        if child.kind != VkGene or child.gene == nil or child.gene.type.kind != VkSymbol:
          not_allowed("external implement body only supports method and ctor declarations")
        case child.gene.type.str
        of "method":
          self.compile_external_implement_method(child.gene)
        of "ctor":
          self.compile_external_implement_ctor(child.gene)
        of "field":
          self.compile_external_implement_field(child.gene)
        else:
          not_allowed("unsupported external implement member: " & child.gene.type.str)
      self.emit(Instruction(kind: IkImplementCheck))
      self.emit(Instruction(kind: IkPop))
      self.emit(Instruction(kind: IkPushNil))
    else:
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
