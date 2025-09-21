import tables, strutils

import ./types
import ./parser

type
  Serialization* = ref object
    references*: Table[string, Value]
    data*: Value

proc serialize*(self: Serialization, value: Value): Value {.gcsafe.}
proc to_path*(self: Value): string {.gcsafe.}
proc to_path*(self: Class): string {.gcsafe.}

proc new_gene_ref(path: string): Value =
  # Create (gene/ref "path")
  let gene = new_gene("gene/ref".to_symbol_value())
  gene.children.add(path.to_value())
  gene.to_gene_value()

# Serialize a value into a form that can be stored and later deserialized
proc serialize*(value: Value): Serialization =
  result = Serialization(
    references: initTable[string, Value](),
  )
  result.data = result.serialize(value)

proc serialize*(self: Serialization, value: Value): Value =
  case value.kind:
  of VkNil, VkBool, VkInt, VkFloat, VkChar:
    return value
  of VkString, VkSymbol:
    return value
  of VkArray:
    let arr = new_ref(VkArray)
    for item in value.ref.arr:
      arr.arr.add(self.serialize(item))
    return arr.to_ref_value()
  of VkMap:
    let map = new_ref(VkMap)
    map.map = initTable[Key, Value]()
    for k, v in value.ref.map:
      map.map[k] = self.serialize(v)
    return map.to_ref_value()
  of VkGene:
    let gene = new_gene(self.serialize(value.gene.type))
    for k, v in value.gene.props:
      gene.props[k] = self.serialize(v)
    for child in value.gene.children:
      gene.children.add(self.serialize(child))
    return gene.to_gene_value()
  of VkClass:
    return new_gene_ref(value.to_path())
  of VkFunction:
    return new_gene_ref(value.to_path())
  of VkInstance:
    # Create (gene/instance <class-ref> {props})
    let gene = new_gene("gene/instance".to_symbol_value())
    gene.children.add(new_gene_ref(value.ref.instance_class.to_path()))
    
    let props = new_ref(VkMap)
    props.map = initTable[Key, Value]()
    for k, v in value.ref.instance_props:
      props.map[k] = self.serialize(v)
    gene.children.add(props.to_ref_value())
    
    return gene.to_gene_value()
  else:
    todo("serialize " & $value.kind)

proc to_path*(self: Class): string =
  # For now, just return the class name
  # In the future, we can build a full path
  return self.name

# A path looks like
# Class C => "pkgP:modM:nsN/C" or just "nsN/C" or "C"
proc to_path*(self: Value): string =
  case self.kind:
  of VkClass:
    return self.ref.class.to_path()
  of VkFunction:
    # For now, just return the function name
    # TODO: Handle namespaced functions properly
    return self.ref.fn.name
  else:
    not_allowed("to_path " & $self.kind)

proc path_to_value*(path: string): Value =
  # Check if it's a namespaced path (e.g., "n/f")
  if "/" in path:
    let parts = path.split("/")
    if parts.len >= 2:
      # Handle nested namespace paths
      var current_ns: Namespace = nil
      var search_namespaces: seq[Namespace] = @[]
      
      # Add namespaces to search
      if App.app.global_ns.kind == VkNamespace:
        search_namespaces.add(App.app.global_ns.ref.ns)
      if VM != nil and VM.frame != nil and VM.frame.ns != nil:
        search_namespaces.add(VM.frame.ns)
      
      # Find the first namespace in the path
      let first_key = parts[0].to_key()
      for ns in search_namespaces:
        if ns.members.has_key(first_key):
          let ns_val = ns.members[first_key]
          if ns_val.kind == VkNamespace:
            current_ns = ns_val.ref.ns
            break
      
      if current_ns != nil:
        # Navigate through nested namespaces
        for i in 1..<parts.len-1:
          let key = parts[i].to_key()
          if current_ns.members.has_key(key):
            let val = current_ns.members[key]
            if val.kind == VkNamespace:
              current_ns = val.ref.ns
            else:
              # Not a namespace, can't continue
              break
          else:
            # Key not found
            current_ns = nil
            break
        
        # Look for the final item
        if current_ns != nil:
          let final_key = parts[^1].to_key()
          if current_ns.members.has_key(final_key):
            return current_ns.members[final_key]
  
  # Look in global namespace first
  let key = path.to_key()
  if App.app.global_ns.kind == VkNamespace and App.app.global_ns.ref.ns.members.has_key(key):
    return App.app.global_ns.ref.ns.members[key]
  
  # Also check if VM is running and has a current frame
  if VM != nil and VM.frame != nil and VM.frame.ns != nil:
    if VM.frame.ns.members.has_key(key):
      return VM.frame.ns.members[key]
  
  not_allowed("path_to_value: not found: " & path)

proc value_to_gene_str(self: Value): string

proc to_s*(self: Serialization): string =
  result = "(gene/serialization "
  result &= value_to_gene_str(self.data)
  result &= ")"

proc value_to_gene_str(self: Value): string =
  case self.kind:
  of VkNil:
    result = "nil"
  of VkBool:
    result = if self == TRUE: "true" else: "false"
  of VkInt:
    result = $self.to_int()
  of VkFloat:
    result = $self.to_float()
  of VkChar:
    result = "'" & $self.char & "'"
  of VkString:
    result = "\"" & self.str & "\""
  of VkSymbol:
    result = self.str
  of VkArray:
    result = "["
    for i, v in self.ref.arr:
      if i > 0:
        result &= " "
      result &= value_to_gene_str(v)
    result &= "]"
  of VkMap:
    result = "{"
    var first = true
    for k, v in self.ref.map:
      if not first:
        result &= " "
      # k is a Key (distinct int64), which is a packed symbol value
      # Extract the symbol index from the packed value
      let symbol_value = cast[Value](k)
      let symbol_index = cast[uint64](symbol_value) and PAYLOAD_MASK
      let key_str = get_symbol(symbol_index.int)
      result &= "^" & key_str
      result &= " "
      result &= value_to_gene_str(v)
      first = false
    result &= "}"
  of VkGene:
    result = "("
    result &= value_to_gene_str(self.gene.type)
    # Add properties
    for k, v in self.gene.props:
      let symbol_value = cast[Value](k)
      let symbol_index = cast[uint64](symbol_value) and PAYLOAD_MASK
      result &= " ^" & get_symbol(symbol_index.int) & " " & value_to_gene_str(v)
    # Add children
    for child in self.gene.children:
      result &= " " & value_to_gene_str(child)
    result &= ")"
  else:
    result = $self  # Fallback to default string representation

#################### Deserialization #############

proc deserialize*(self: Serialization, value: Value): Value {.gcsafe.}

proc deref*(self: Serialization, s: string): Value =
  path_to_value(s)

proc deserialize*(s: string): Value =
  var ser = Serialization(
    references: initTable[string, Value](),
  )
  ser.deserialize(read_all(s)[0])

proc deserialize*(self: Serialization, value: Value): Value =
  case value.kind:
  of VkGene:
    # Check if it's a special gene type
    var type_str: string
    if value.gene.type.kind == VkSymbol:
      type_str = value.gene.type.str
    elif value.gene.type.kind == VkComplexSymbol:
      type_str = value.gene.type.ref.csymbol.join("/")
    else:
      # Regular gene - deserialize recursively
      let gene = new_gene(self.deserialize(value.gene.type))
      for k, v in value.gene.props:
        gene.props[k] = self.deserialize(v)
      for child in value.gene.children:
        gene.children.add(self.deserialize(child))
      return gene.to_gene_value()
    
    # Handle special gene types
    case type_str:
    of "gene/serialization":
      if value.gene.children.len > 0:
        return self.deserialize(value.gene.children[0])
      else:
        return NIL
    of "gene/ref":
      if value.gene.children.len > 0:
        return self.deref(value.gene.children[0].str)
      else:
        return NIL
    of "gene/instance":
        if value.gene.children.len >= 2:
          var class_ref = self.deserialize(value.gene.children[0])
          if class_ref.kind != VkClass:
            not_allowed("gene/instance expects class reference")
          
          let instance = new_ref(VkInstance)
          instance.instance_class = class_ref.ref.class
          instance.instance_props = initTable[Key, Value]()
          
          # Deserialize properties
          let props = value.gene.children[1]
          if props.kind == VkMap:
            for k, v in props.ref.map:
              instance.instance_props[k] = self.deserialize(v)
          
          return instance.to_ref_value()
        else:
          return NIL
    else:
      # Regular gene - deserialize recursively
      let gene = new_gene(self.deserialize(value.gene.type))
      for k, v in value.gene.props:
        gene.props[k] = self.deserialize(v)
      for child in value.gene.children:
        gene.children.add(self.deserialize(child))
      return gene.to_gene_value()
  else:
    # Simple values serialize to themselves
    return value

# VM integration functions
proc vm_serialize(vm: VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value {.gcsafe.} =
  {.cast(gcsafe).}:
    if arg_count != 1:
      not_allowed("serialize expects 1 argument")

    let value = get_positional_arg(args, 0, has_keyword_args)
    let ser = serialize(value)
    return ser.to_s().to_value()

proc vm_deserialize(vm: VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value {.gcsafe.} =
  {.cast(gcsafe).}:
    if arg_count != 1:
      not_allowed("deserialize expects 1 argument")

    let s = get_positional_arg(args, 0, has_keyword_args).str
    return deserialize(s)

# Initialize the serdes namespace
proc init_serdes*() =
  let serdes_ns = new_namespace("serdes")
  serdes_ns["serialize".to_key()] = NativeFn(vm_serialize).to_value()
  serdes_ns["deserialize".to_key()] = NativeFn(vm_deserialize).to_value()
  App.app.gene_ns.ref.ns["serdes".to_key()] = serdes_ns.to_value()