## Interface and Adapter VM operations
##
## This module handles the runtime execution of interface definitions,
## implementations, and adapter creation/access.

import tables
import ../types
from ../types/runtime_types import types_equivalent

type
  InterfaceMethodMetadata = object
    name: string
    param_descs: seq[CallableParamDesc]
    return_type_id: TypeId
    effects: seq[string]

  InterfacePropMetadata = object
    name: string
    type_id: TypeId

  InterfaceHeaderMetadata = object
    name: string
    parents: seq[string]
    overrides: seq[string]

proc new_adapter_value(adapter: Adapter): Value =
  let r = new_ref(VkAdapter)
  r.adapter = adapter
  r.to_ref_value()

proc adapter_key_name(key: Key): string =
  get_symbol(symbol_index(key))

proc adapter_member_name(value: Value, context: string): string =
  if value.kind notin {VkSymbol, VkString}:
    raise new_exception(types.Exception, context & " must be a symbol or string")
  value.str

proc adapter_metadata_int(value: Value, context: string): int64 =
  if value.kind != VkInt:
    raise new_exception(types.Exception, context & " must be an integer")
  value.int64

proc parse_interface_param_descs(value: Value): seq[CallableParamDesc] =
  if value == NIL:
    return @[]
  if value.kind != VkArray:
    raise new_exception(types.Exception, "interface method parameter metadata must be an array")
  for item in array_data(value):
    if item.kind != VkArray:
      raise new_exception(types.Exception, "interface method parameter entry must be an array")
    let parts = array_data(item)
    if parts.len < 3:
      raise new_exception(types.Exception, "interface method parameter entry is incomplete")
    let kind_id = adapter_metadata_int(parts[0], "interface method parameter kind").int
    if kind_id < ord(low(CallableParamKind)) or kind_id > ord(high(CallableParamKind)):
      raise new_exception(types.Exception, "interface method parameter kind is invalid")
    let keyword_name =
      if parts[1].kind in {VkString, VkSymbol}:
        parts[1].str
      else:
        raise new_exception(types.Exception, "interface method keyword parameter name must be a string")
    let type_id = adapter_metadata_int(parts[2], "interface method parameter type").TypeId
    result.add(CallableParamDesc(
      kind: CallableParamKind(kind_id),
      keyword_name: keyword_name,
      type_id: type_id
    ))

proc parse_interface_effects(value: Value): seq[string] =
  if value == NIL:
    return @[]
  if value.kind != VkArray:
    raise new_exception(types.Exception, "interface method effects metadata must be an array")
  for item in array_data(value):
    if item.kind notin {VkSymbol, VkString}:
      raise new_exception(types.Exception, "interface method effects must be symbols or strings")
    if item.str.len > 0:
      result.add(item.str)

proc parse_interface_method_metadata(metadata: Value): InterfaceMethodMetadata =
  result.return_type_id = NO_TYPE_ID
  if metadata.kind == VkGene:
    if metadata.gene.children.len == 0:
      raise new_exception(types.Exception, "interface method metadata is missing a name")
    result.name = adapter_member_name(metadata.gene.children[0], "interface method name")
    if metadata.gene.children.len > 1:
      result.param_descs = parse_interface_param_descs(metadata.gene.children[1])
    if metadata.gene.children.len > 2:
      result.return_type_id = adapter_metadata_int(metadata.gene.children[2], "interface method return type").TypeId
    if metadata.gene.children.len > 3:
      result.effects = parse_interface_effects(metadata.gene.children[3])
  else:
    result.name = adapter_member_name(metadata, "interface method name")

proc parse_interface_prop_metadata(metadata: Value): InterfacePropMetadata =
  result.type_id = NO_TYPE_ID
  if metadata.kind == VkGene:
    if metadata.gene.children.len == 0:
      raise new_exception(types.Exception, "interface field metadata is missing a name")
    result.name = adapter_member_name(metadata.gene.children[0], "interface field name")
    if metadata.gene.children.len > 1:
      result.type_id = adapter_metadata_int(metadata.gene.children[1], "interface field type").TypeId
  else:
    result.name = adapter_member_name(metadata, "interface field name")

proc parse_interface_header_metadata(metadata: Value): InterfaceHeaderMetadata =
  if metadata.kind == VkGene:
    if metadata.gene.children.len == 0:
      raise new_exception(types.Exception, "interface metadata is missing a name")
    result.name = adapter_member_name(metadata.gene.children[0], "interface name")
    if metadata.gene.children.len > 1:
      let parents = metadata.gene.children[1]
      if parents.kind != VkArray:
        raise new_exception(types.Exception, "interface parent metadata must be an array")
      for parent in array_data(parents):
        result.parents.add(adapter_member_name(parent, "interface parent name"))
    if metadata.gene.children.len > 2:
      let overrides = metadata.gene.children[2]
      if overrides.kind != VkArray:
        raise new_exception(types.Exception, "interface override metadata must be an array")
      for override_name in array_data(overrides):
        result.overrides.add(adapter_member_name(override_name, "interface override name"))
  else:
    result.name = adapter_member_name(metadata, "interface name")

proc interface_header_overrides(header: InterfaceHeaderMetadata, name: string): bool =
  for override_name in header.overrides:
    if override_name == name:
      return true
  false

proc resolve_interface_in_namespace(vm: ptr VirtualMachine, name: string): GeneInterface =
  let interface_key = name.to_key()
  var interface_val = vm.frame.ns.members.get_or_default(interface_key, NIL)
  if interface_val.is_nil or interface_val.kind != VkInterface:
    var ns = vm.frame.ns.parent
    while not ns.is_nil:
      interface_val = ns.members.get_or_default(interface_key, NIL)
      if not interface_val.is_nil and interface_val.kind == VkInterface:
        break
      ns = ns.parent
  if interface_val.is_nil or interface_val.kind != VkInterface:
    raise new_exception(types.Exception, "Interface not found: " & name)
  interface_val.ref.gene_interface

proc interface_type_id_equivalent(left_id: TypeId, left_descs: seq[TypeDesc],
                                  right_id: TypeId, right_descs: seq[TypeDesc]): bool =
  if left_id == right_id:
    return true
  if left_id == NO_TYPE_ID and right_id == BUILTIN_TYPE_ANY_ID:
    return true
  if left_id == BUILTIN_TYPE_ANY_ID and right_id == NO_TYPE_ID:
    return true
  if left_id >= 0 and right_id >= 0:
    return types_equivalent(left_id, left_descs, right_id, right_descs)
  false

proc interface_effects_same(left, right: seq[string]): bool =
  if left.len != right.len:
    return false
  for effect in left:
    var found = false
    for other in right:
      if effect == other:
        found = true
        break
    if not found:
      return false
  true

proc interface_effects_compatible(expected, actual: seq[string]): bool =
  if expected.len == 0:
    return actual.len == 0
  if actual.len == 0:
    return true
  for effect in actual:
    var found = false
    for allowed in expected:
      if allowed == effect:
        found = true
        break
    if not found:
      return false
  true

proc adapter_type_name(type_id: TypeId, type_descs: seq[TypeDesc]): string =
  type_desc_to_string(type_id, type_descs)

proc adapter_param_signature(param: CallableParamDesc, type_descs: seq[TypeDesc]): string =
  let typ = adapter_type_name(param.type_id, type_descs)
  case param.kind
  of CpkPositional:
    typ
  of CpkPositionalRest:
    typ & " ..."
  of CpkKeyword:
    "^" & param.keyword_name & " " & typ
  of CpkKeywordRest:
    "^... " & typ

proc adapter_effect_suffix(effects: seq[string]): string =
  if effects.len == 0:
    return ""
  " ! [" & effects.join(" ") & "]"

proc adapter_method_signature(method_name: string, param_descs: seq[CallableParamDesc],
                              return_type_id: TypeId, type_descs: seq[TypeDesc],
                              effects: seq[string]): string =
  var params: seq[string] = @[]
  for param in param_descs:
    params.add(adapter_param_signature(param, type_descs))
  method_name & " [" & params.join(" ") & "] -> " &
    adapter_type_name(return_type_id, type_descs) & adapter_effect_suffix(effects)

proc adapter_method_signature(method_info: InterfaceMethod): string =
  adapter_method_signature(method_info.name, method_info.param_descs, method_info.type_id,
    method_info.type_descs, method_info.effects)

proc adapter_prop_signature(prop: InterfaceProp): string =
  prop.name & " " & adapter_type_name(prop.type_id, prop.type_descs) &
    (if prop.readonly: " readonly" else: "")

proc interface_methods_compatible(left, right: InterfaceMethod,
                                  allow_effect_refinement = false): bool =
  if left.param_descs.len != right.param_descs.len:
    return false
  for i, left_param in left.param_descs:
    let right_param = right.param_descs[i]
    if left_param.kind != right_param.kind:
      return false
    if left_param.keyword_name != right_param.keyword_name:
      return false
    if not interface_type_id_equivalent(left_param.type_id, left.type_descs,
                                        right_param.type_id, right.type_descs):
      return false
  if not interface_type_id_equivalent(left.type_id, left.type_descs, right.type_id, right.type_descs):
    return false
  if allow_effect_refinement:
    interface_effects_compatible(left.effects, right.effects)
  else:
    interface_effects_same(left.effects, right.effects)

proc interface_props_compatible(left, right: InterfaceProp): bool =
  left.readonly == right.readonly and
    interface_type_id_equivalent(left.type_id, left.type_descs, right.type_id, right.type_descs)

proc inherit_interface_member(target: GeneInterface, key: Key, iface_method: InterfaceMethod,
                              allow_duplicate_default = false) =
  if not target.methods.has_key(key):
    target.methods[key] = iface_method
    return
  let existing = target.methods[key]
  if not interface_methods_compatible(existing, iface_method):
    raise new_exception(types.Exception,
      "Interface " & target.name & " inherits incompatible method " & iface_method.name &
      " (existing " & adapter_method_signature(existing) &
      ", inherited " & adapter_method_signature(iface_method) & ")")
  if existing.callable != NIL and iface_method.callable != NIL and not allow_duplicate_default:
    raise new_exception(types.Exception,
      "Interface " & target.name & " inherits duplicate default method " & iface_method.name)
  if existing.callable == NIL and iface_method.callable != NIL:
    target.methods[key] = iface_method

proc inherit_interface_member(target: GeneInterface, key: Key, prop: InterfaceProp) =
  if not target.props.has_key(key):
    target.props[key] = prop
    return
  if not interface_props_compatible(target.props[key], prop):
    raise new_exception(types.Exception,
      "Interface " & target.name & " inherits incompatible field " & prop.name &
      " (existing " & adapter_prop_signature(target.props[key]) &
      ", inherited " & adapter_prop_signature(prop) & ")")

proc adapter_private_access_allowed(vm: ptr VirtualMachine, adapter_val: Value): bool =
  if vm == nil or vm.frame == nil:
    return false
  if vm.frame.args.kind == VkGene and vm.frame.args.gene.children.len > 0:
    return same_value_identity(vm.frame.args.gene.children[0], adapter_val)
  false

proc bind_adapter_callable(self_value: Value, method_name: string, callable: Value): Value =
  let r = new_ref(VkBoundMethod)
  r.bound_method = BoundMethod(
    self: self_value,
    `method`: Method(
      class: nil,
      name: method_name,
      callable: callable,
      is_macro: callable.kind == VkFunction and callable.ref.fn.is_macro_like,
      native_signature_known: false,
      native_param_types: @[],
      native_return_type: NIL,
    )
  )
  r.to_ref_value()

proc adapter_target_class(value: Value): Class =
  case value.kind
  of VkAdapter:
    adapter_target_class(value.ref.adapter.inner)
  of VkClass:
    value.ref.class
  else:
    get_value_class(value)

proc adapter_try_read_inner_property(vm: ptr VirtualMachine, value: Value, key: Key): tuple[found: bool, member: Value] =
  case value.kind
  of VkAdapter:
    adapter_try_read_inner_property(vm, value.ref.adapter.inner, key)
  of VkAdapterInternal:
    (true, adapter_internal_get_member(value, key))
  of VkInstance:
    if key in instance_props(value):
      (true, instance_props(value)[key])
    else:
      (false, NIL)
  of VkMap:
    if map_data(value).has_key(key):
      (true, map_data(value)[key])
    else:
      (false, NIL)
  of VkNamespace:
    if value.ref.ns.members.has_key(key):
      (true, value.ref.ns.members[key])
    else:
      (false, NIL)
  of VkClass:
    let member = value.ref.class.get_member(key)
    if member != NIL:
      (true, member)
    elif value.ref.class.ns.members.has_key(key):
      (true, value.ref.class.ns.members[key])
    else:
      (false, NIL)
  else:
    (false, NIL)

proc adapter_write_inner_property(value: Value, mapped_key: Key, member_value: Value): bool =
  case value.kind
  of VkAdapter:
    adapter_write_inner_property(value.ref.adapter.inner, mapped_key, member_value)
  of VkAdapterInternal:
    adapter_internal_set_member(value, mapped_key, member_value)
    true
  of VkInstance:
    instance_props(value)[mapped_key] = member_value
    true
  of VkMap:
    map_data(value)[mapped_key] = member_value
    true
  else:
    false

proc adapter_bind_inner_method(value: Value, key: Key): Value =
  case value.kind
  of VkAdapter:
    adapter_bind_inner_method(value.ref.adapter.inner, key)
  else:
    let inner_class = adapter_target_class(value)
    if inner_class == nil:
      return NIL
    let meth = inner_class.get_method(key)
    if meth.is_nil:
      return NIL
    let r = new_ref(VkBoundMethod)
    r.bound_method = BoundMethod(self: value, `method`: meth)
    r.to_ref_value()

proc adapter_bind_runtime_method(value: Value, key: Key): Value =
  let value_class = get_value_class(value)
  if value_class == nil:
    return NIL
  let meth = value_class.get_method(key)
  if meth.is_nil:
    return NIL
  let r = new_ref(VkBoundMethod)
  r.bound_method = BoundMethod(self: value, `method`: meth)
  r.to_ref_value()

proc exec_interface(vm: ptr VirtualMachine, name: Value) =
  ## Execute IkInterface instruction - create an interface
  let header = parse_interface_header_metadata(name)
  let interface_name = header.name
  let gene_interface = new_interface(interface_name, vm.cu.module_path)
  for parent_name in header.parents:
    if parent_name == interface_name:
      raise new_exception(types.Exception, "Interface " & interface_name & " cannot extend itself")
    let parent = resolve_interface_in_namespace(vm, parent_name)
    gene_interface.parents.add(parent)
    for key, parent_method in parent.methods:
      gene_interface.inherit_interface_member(
        key,
        parent_method,
        allow_duplicate_default = interface_header_overrides(header, parent_method.name)
      )
    for key, prop in parent.props:
      gene_interface.inherit_interface_member(key, prop)

  let r = new_ref(VkInterface)
  r.gene_interface = gene_interface
  let v = r.to_ref_value()

  vm.frame.ns[interface_name.to_key()] = v
  vm.frame.push(v)

proc exec_interface_method(vm: ptr VirtualMachine, name: Value, flags: int32) =
  let has_default = (flags and 1'i32) != 0
  let default_callable = if has_default: vm.frame.pop() else: NIL
  let interface_val = vm.frame.current()
  if interface_val.kind != VkInterface:
    raise new_exception(types.Exception, "interface method definition requires an interface context")
  let metadata = parse_interface_method_metadata(name)
  let type_descs = if vm.cu != nil: vm.cu.type_descriptors else: @[]
  let existing = interface_val.ref.gene_interface.get_method(metadata.name.to_key())
  if existing != nil:
    let candidate = InterfaceMethod(
      name: metadata.name,
      callable: default_callable,
      type_id: metadata.return_type_id,
      param_descs: metadata.param_descs,
      effects: metadata.effects,
      type_descs: type_descs
    )
    if not interface_methods_compatible(existing, candidate, allow_effect_refinement = true):
      raise new_exception(types.Exception,
        "Interface " & interface_val.ref.gene_interface.name & " overrides method " &
        metadata.name & " with an incompatible signature (inherited " &
        adapter_method_signature(existing) & ", override " &
        adapter_method_signature(metadata.name, metadata.param_descs, metadata.return_type_id,
          type_descs, metadata.effects) & ")")
  interface_val.ref.gene_interface.add_method(
    metadata.name,
    callable = default_callable,
    type_id = metadata.return_type_id,
    param_descs = metadata.param_descs,
    effects = metadata.effects,
    type_descs = type_descs
  )

proc exec_interface_prop(vm: ptr VirtualMachine, name: Value, readonly: bool) =
  let interface_val = vm.frame.current()
  if interface_val.kind != VkInterface:
    raise new_exception(types.Exception, "interface prop definition requires an interface context")
  let metadata = parse_interface_prop_metadata(name)
  let type_descs = if vm.cu != nil: vm.cu.type_descriptors else: @[]
  let existing = interface_val.ref.gene_interface.get_prop(metadata.name.to_key())
  if existing != nil:
    let candidate = InterfaceProp(
      name: metadata.name,
      type_id: metadata.type_id,
      type_descs: type_descs,
      readonly: readonly
    )
    if not interface_props_compatible(existing, candidate):
      raise new_exception(types.Exception,
        "Interface " & interface_val.ref.gene_interface.name & " overrides field " &
        metadata.name & " with an incompatible signature")
  interface_val.ref.gene_interface.add_prop(metadata.name, metadata.type_id, readonly, type_descs)

proc class_prop_type(cls: Class, key: Key): tuple[found: bool, type_id: TypeId, type_descs: seq[TypeDesc]] =
  var current = cls
  while current != nil:
    if current.prop_types.has_key(key):
      return (true, current.prop_types[key], current.prop_type_descs)
    current = current.parent
  (false, NO_TYPE_ID, @[])

proc adapter_type_id_compatible(interface_id: TypeId, interface_descs: seq[TypeDesc],
                                impl_id: TypeId, impl_descs: seq[TypeDesc]): bool =
  if interface_id in [NO_TYPE_ID, BUILTIN_TYPE_ANY_ID]:
    return true
  if impl_id in [NO_TYPE_ID, BUILTIN_TYPE_ANY_ID]:
    return true
  if interface_id >= 0 and impl_id >= 0:
    return types_equivalent(interface_id, interface_descs, impl_id, impl_descs)
  interface_id == impl_id

proc callable_signature_compatible(callable: Value, iface_method: InterfaceMethod,
                                   has_self: bool): bool =
  if callable.kind != VkFunction:
    return true
  let fn = callable.ref.fn
  if fn == nil or fn.matcher == nil:
    return iface_method.param_descs.len == 0

  let start = if has_self and fn.matcher.children.len > 0: 1 else: 0
  if fn.matcher.children.len - start != iface_method.param_descs.len:
    return false

  for i, iface_param in iface_method.param_descs:
    let matcher = fn.matcher.children[start + i]
    if not adapter_type_id_compatible(iface_param.type_id, iface_method.type_descs,
                                      matcher.type_id, fn.matcher.type_descriptors):
      return false

  adapter_type_id_compatible(iface_method.type_id, iface_method.type_descs,
                             fn.matcher.return_type_id, fn.matcher.type_descriptors) and
    interface_effects_compatible(iface_method.effects, fn.matcher.effects)

proc method_signature_compatible(meth: Method, iface_method: InterfaceMethod): bool =
  if meth.is_nil:
    return false
  if meth.native_signature_known:
    let sig = meth.native_signature
    if sig == nil or sig.params.len != iface_method.param_descs.len:
      return false
    for i, iface_param in iface_method.param_descs:
      let native_param = sig.params[i]
      if native_param.kind != iface_param.kind:
        return false
      if not adapter_type_id_compatible(iface_param.type_id, iface_method.type_descs,
                                        native_param.type_id, sig.type_descriptors):
        return false
    if not adapter_type_id_compatible(iface_method.type_id, iface_method.type_descs,
                                      sig.return_type_id, sig.type_descriptors):
      return false
    return true
  callable_signature_compatible(meth.callable, iface_method, has_self = true)

proc inline_requires_adapter(target_class: Class, gene_interface: GeneInterface): bool =
  for key, iface_method in gene_interface.methods:
    if iface_method.callable != NIL and target_class.get_method(key).is_nil:
      return true
  false

proc validate_implementation_complete(gene_interface: GeneInterface, target_class: Class,
                                      impl: Implementation) =
  if gene_interface.is_nil or target_class.is_nil or impl.is_nil:
    raise new_exception(types.Exception, "invalid implementation validation context")

  for key, iface_method in gene_interface.methods:
    let mapping = impl.method_mappings.get_or_default(key, nil)
    if not mapping.is_nil:
      case mapping.kind
      of AmkComputed:
        if not callable_signature_compatible(mapping.compute_fn, iface_method, has_self = true):
          raise new_exception(types.Exception,
            "Implementation of interface " & gene_interface.name & " for " & target_class.name &
            " has incompatible method signature for " & iface_method.name &
            " (expected " & adapter_method_signature(iface_method) & ")")
        continue
      of AmkRename:
        let mapped_method = target_class.get_method(mapping.inner_name)
        if not mapped_method.is_nil and method_signature_compatible(mapped_method, iface_method):
          continue
        raise new_exception(types.Exception,
          "Implementation of interface " & gene_interface.name & " for " & target_class.name &
          " maps method " & iface_method.name & " to an incompatible or missing method" &
          " (expected " & adapter_method_signature(iface_method) & ")")
      of AmkAccessor, AmkHidden:
        discard

    let same_name_method = target_class.get_method(key)
    if not same_name_method.is_nil and method_signature_compatible(same_name_method, iface_method):
      continue
    if impl.is_inline and iface_method.callable != NIL:
      for existing_interface, existing_impl in target_class.implementations:
        if existing_impl == impl:
          continue
        let existing_method = existing_interface.get_method(key)
        if existing_method != nil and existing_method.callable != NIL:
          raise new_exception(types.Exception,
            "Implementation of interface " & gene_interface.name & " for " & target_class.name &
            " has duplicate default method " & iface_method.name)
    if iface_method.callable != NIL:
      continue
    raise new_exception(types.Exception,
      "Implementation of interface " & gene_interface.name & " for " & target_class.name &
      " is missing method " & adapter_method_signature(iface_method))

  for key, iface_prop in gene_interface.props:
    if impl.prop_mappings.has_key(key):
      continue
    let class_prop = class_prop_type(target_class, key)
    if class_prop.found and adapter_type_id_compatible(iface_prop.type_id, iface_prop.type_descs,
                                                       class_prop.type_id, class_prop.type_descs):
      continue
    if class_prop.found:
      raise new_exception(types.Exception,
        "Implementation of interface " & gene_interface.name & " for " & target_class.name &
        " has incompatible field signature for " & iface_prop.name &
        " (expected " & adapter_prop_signature(iface_prop) & ")")
    raise new_exception(types.Exception,
      "Implementation of interface " & gene_interface.name & " for " & target_class.name &
      " is missing field " & adapter_prop_signature(iface_prop))

proc exec_implement_check(vm: ptr VirtualMachine) =
  let context = vm.frame.current()
  if context.kind != VkGene or context.gene.children.len < 2:
    raise new_exception(types.Exception, "external implement check requires an implementation context")

  let class_val = context.gene.children[0]
  let interface_val = context.gene.children[1]
  if class_val.kind != VkClass or interface_val.kind != VkInterface:
    raise new_exception(types.Exception, "invalid implementation context")

  let impl = class_val.ref.class.find_implementation(interface_val.ref.gene_interface)
  if impl.is_nil:
    raise new_exception(types.Exception, "implementation not found for external implement check")
  validate_implementation_complete(interface_val.ref.gene_interface, class_val.ref.class, impl)

proc exec_implement(vm: ptr VirtualMachine, interface_name: Value, is_external: bool, has_body: bool) =
  ## Execute IkImplement instruction - register an implementation
  var target_class: Class

  if is_external:
    let target_class_val = vm.frame.pop()
    if target_class_val.kind == VkClass:
      target_class = target_class_val.ref.class
    else:
      raise new_exception(types.Exception, "implement requires a class, got " & $target_class_val.kind)
  else:
    if vm.frame.args.kind == VkGene and vm.frame.args.gene.children.len > 0:
      let class_value = vm.frame.args.gene.children[0]
      if class_value.kind == VkClass:
        target_class = class_value.ref.class
      else:
        raise new_exception(types.Exception, "inline implement can only be used inside a class")
    else:
      raise new_exception(types.Exception, "inline implement can only be used inside a class")

  let interface_key = interface_name.str.to_key()
  var interface_val = vm.frame.ns.members.get_or_default(interface_key, NIL)
  if interface_val.is_nil or interface_val.kind != VkInterface:
    var ns = vm.frame.ns.parent
    while not ns.is_nil:
      interface_val = ns.members.get_or_default(interface_key, NIL)
      if not interface_val.is_nil and interface_val.kind == VkInterface:
        break
      ns = ns.parent

  if interface_val.is_nil or interface_val.kind != VkInterface:
    raise new_exception(types.Exception, "Interface not found: " & interface_name.str)

  let gene_interface = interface_val.ref.gene_interface
  let impl = new_implementation(gene_interface, target_class, ItkClass, is_inline = not is_external)
  target_class.register_implementation(gene_interface, impl)

  if has_body:
    if is_external:
      let context = new_gene_value()
      let class_ref = new_ref(VkClass)
      class_ref.class = target_class
      context.gene.children.add(class_ref.to_ref_value())
      context.gene.children.add(interface_val)
      vm.frame.push(context)
    else:
      let class_ref = new_ref(VkClass)
      class_ref.class = target_class
      vm.frame.push(class_ref.to_ref_value())
  else:
    validate_implementation_complete(gene_interface, target_class, impl)
    vm.frame.push(NIL)

proc exec_implement_method(vm: ptr VirtualMachine, method_name: Value) =
  let fn_value = vm.frame.pop()
  let context = vm.frame.current()

  if context.kind != VkGene or context.gene.children.len < 2:
    raise new_exception(types.Exception, "external implement method requires an implementation context")

  let class_val = context.gene.children[0]
  let interface_val = context.gene.children[1]
  if class_val.kind != VkClass or interface_val.kind != VkInterface:
    raise new_exception(types.Exception, "invalid implementation context")

  let impl = class_val.ref.class.find_implementation(interface_val.ref.gene_interface)
  if impl.is_nil:
    raise new_exception(types.Exception, "implementation not found for external method: " & method_name.str)

  if not interface_val.ref.gene_interface.has_method(method_name.str.to_key()):
    raise new_exception(types.Exception,
      "Method " & method_name.str & " is not declared on interface " & interface_val.ref.gene_interface.name)
  impl.map_method_computed(method_name.str, fn_value)

proc exec_implement_ctor(vm: ptr VirtualMachine) =
  let fn_value = vm.frame.pop()
  let context = vm.frame.current()

  if context.kind != VkGene or context.gene.children.len < 2:
    raise new_exception(types.Exception, "external implement ctor requires an implementation context")

  let class_val = context.gene.children[0]
  let interface_val = context.gene.children[1]
  if class_val.kind != VkClass or interface_val.kind != VkInterface:
    raise new_exception(types.Exception, "invalid implementation context")

  let impl = class_val.ref.class.find_implementation(interface_val.ref.gene_interface)
  if impl.is_nil:
    raise new_exception(types.Exception, "implementation not found for external ctor")
  impl.ctor = fn_value

proc exec_implement_field(vm: ptr VirtualMachine, metadata: Value, flags: int32) =
  if metadata.kind != VkGene or metadata.gene.children.len == 0:
    raise new_exception(types.Exception, "external implement field has invalid metadata")

  let mode = AdapterFieldInstructionMode(flags and 3'i32)
  let has_setter = (flags and 4'i32) != 0
  var get_fn = NIL
  var set_fn = NIL
  if mode == AfiAccessor:
    if has_setter:
      set_fn = vm.frame.pop()
    get_fn = vm.frame.pop()

  let context = vm.frame.current()
  if context.kind != VkGene or context.gene.children.len < 2:
    raise new_exception(types.Exception, "external implement field requires an implementation context")

  let class_val = context.gene.children[0]
  let interface_val = context.gene.children[1]
  if class_val.kind != VkClass or interface_val.kind != VkInterface:
    raise new_exception(types.Exception, "invalid implementation context")

  let gene_interface = interface_val.ref.gene_interface
  let impl = class_val.ref.class.find_implementation(gene_interface)
  if impl.is_nil:
    raise new_exception(types.Exception, "implementation not found for external field")

  let field_name = adapter_member_name(metadata.gene.children[0], "adapter field name")
  let field_key = field_name.to_key()

  case mode
  of AfiOwned:
    if gene_interface.has_prop(field_key):
      raise new_exception(types.Exception,
        "Adapter-owned field " & field_name & " conflicts with interface field " & field_name)
    if impl.owned_fields.has_key(field_key):
      raise new_exception(types.Exception, "Duplicate adapter-owned field: " & field_name)
    let type_expr = if metadata.gene.children.len > 1: metadata.gene.children[1] else: NIL
    impl.add_owned_field(field_name, type_expr)
  of AfiDirect, AfiAccessor:
    if not gene_interface.has_prop(field_key):
      raise new_exception(types.Exception,
        "Adapter field mapping " & field_name & " is not declared on interface " & gene_interface.name)
    if impl.prop_mappings.has_key(field_key):
      raise new_exception(types.Exception, "Duplicate adapter field mapping: " & field_name)
    let prop = gene_interface.props[field_key]
    if mode == AfiAccessor and has_setter and prop.readonly:
      raise new_exception(types.Exception,
        "Readonly interface field " & field_name & " cannot declare an adapter set accessor")

    case mode
    of AfiDirect:
      if metadata.gene.children.len < 2:
        raise new_exception(types.Exception, "Direct adapter field mapping " & field_name & " requires a ^from target")
      let inner_name = adapter_member_name(metadata.gene.children[1], "adapter field ^from target")
      impl.map_prop_rename(field_name, inner_name)
    of AfiAccessor:
      impl.map_prop_accessor(field_name, get_fn, set_fn)
    else:
      discard

proc exec_adapter(vm: ptr VirtualMachine, ctor_args: seq[Value] = @[], kw_pairs: seq[(Key, Value)] = @[]) =
  ## Execute IkAdapter instruction - create an adapter wrapper
  let inner = vm.frame.pop()
  let interface_val = vm.frame.pop()

  if interface_val.kind != VkInterface:
    raise new_exception(types.Exception, "adapter requires an interface, got " & $interface_val.kind)

  let gene_interface = interface_val.ref.gene_interface
  let impl_target = unwrap_adapter(inner)
  let target_class = adapter_target_class(impl_target)
  let impl = if target_class != nil: target_class.find_implementation(gene_interface) else: nil

  if impl.is_nil:
    raise new_exception(types.Exception,
      "No implementation found for interface " & gene_interface.name &
      " on type " & (if target_class != nil: target_class.name else: $impl_target.kind))

  if impl.is_inline:
    if ctor_args.len > 0 or kw_pairs.len > 0:
      raise new_exception(types.Exception,
        "Inline interface implementation " & gene_interface.name & " does not accept adapter constructor arguments")
    if not inline_requires_adapter(target_class, gene_interface):
      vm.frame.push(impl_target)
      return

  let adapter = new_adapter(gene_interface, inner, impl)
  let adapter_val = new_adapter_value(adapter)
  vm.frame.push(adapter_val)

  if impl.is_inline:
    return
  elif impl.ctor != NIL:
    discard vm.call_bound_method(bind_adapter_callable(adapter_val, "ctor", impl.ctor), ctor_args, kw_pairs)
  elif ctor_args.len > 0 or kw_pairs.len > 0:
    discard vm.frame.pop()
    raise new_exception(types.Exception,
      "Adapter " & gene_interface.name & " does not define a constructor")

proc adapter_get_member(vm: ptr VirtualMachine, adapter_val: Value, key: Key): Value =
  ## Get a member from an adapter
  if adapter_val.kind != VkAdapter:
    raise new_exception(types.Exception, "Expected VkAdapter")

  let adapter = adapter_val.ref.adapter
  let gene_interface = adapter.gene_interface
  let impl = adapter.implementation
  let private_access = adapter_private_access_allowed(vm, adapter_val)

  if key == "_wrapped".to_key():
    if not private_access:
      raise new_exception(types.Exception, "Adapter pseudo-member _wrapped is only available inside adapter implementation bodies")
    return adapter.inner

  if private_access and impl.owned_fields.has_key(key):
    return adapter.own_data.get_or_default(key, NIL)

  if gene_interface.props.has_key(key):
    let mapping = impl.prop_mappings.get_or_default(key, nil)
    if not mapping.is_nil and mapping.kind == AmkHidden:
      raise new_exception(types.Exception, "Property " & $key & " is not accessible")
    if mapping.is_nil:
      let found = adapter_try_read_inner_property(vm, adapter.inner, key)
      if found.found:
        return found.member
      raise new_exception(types.Exception,
        "Adapter field " & adapter_key_name(key) & " has no explicit mapping and wrapped value has no same-name member")

    case mapping.kind
    of AmkRename:
      let found = adapter_try_read_inner_property(vm, adapter.inner, mapping.inner_name)
      if found.found:
        return found.member
      raise new_exception(types.Exception,
        "Adapter field " & adapter_key_name(key) & " maps to missing wrapped member " & adapter_key_name(mapping.inner_name))
    of AmkComputed:
      return vm.call_bound_method(bind_adapter_callable(adapter_val, adapter_key_name(key), mapping.compute_fn), @[])
    of AmkAccessor:
      return vm.call_bound_method(bind_adapter_callable(adapter_val, adapter_key_name(key), mapping.get_fn), @[])
    of AmkHidden:
      discard

  if gene_interface.methods.has_key(key):
    let mapping = impl.method_mappings.get_or_default(key, nil)
    if mapping.is_nil:
      let member = adapter_bind_inner_method(adapter.inner, key)
      if member != NIL:
        return member
      let iface_method = gene_interface.methods[key]
      if iface_method.callable != NIL:
        return bind_adapter_callable(adapter_val, adapter_key_name(key), iface_method.callable)
      raise new_exception(types.Exception, "Method " & $key & " not found on inner object")

    case mapping.kind
    of AmkRename:
      let member = adapter_bind_inner_method(adapter.inner, mapping.inner_name)
      if member != NIL:
        return member
      raise new_exception(types.Exception, "Method " & $mapping.inner_name & " not found on inner object")
    of AmkComputed:
      return bind_adapter_callable(adapter_val, adapter_key_name(key), mapping.compute_fn)
    of AmkAccessor:
      raise new_exception(types.Exception, "Method " & $key & " cannot use field accessors")
    of AmkHidden:
      raise new_exception(types.Exception, "Method " & $key & " is not accessible")

  let runtime_method = adapter_bind_runtime_method(adapter_val, key)
  if runtime_method != NIL:
    return runtime_method

  raise new_exception(types.Exception,
    "Member " & adapter_key_name(key) & " is not declared on interface " & gene_interface.name)

proc adapter_set_member(vm: ptr VirtualMachine, adapter_val: Value, key: Key, value: Value) =
  ## Set a member on an adapter
  if adapter_val.kind != VkAdapter:
    raise new_exception(types.Exception, "Expected VkAdapter")

  let adapter = adapter_val.ref.adapter
  let gene_interface = adapter.gene_interface
  let impl = adapter.implementation
  let private_access = adapter_private_access_allowed(vm, adapter_val)

  if key == "_wrapped".to_key():
    raise new_exception(types.Exception, "Adapter pseudo-member _wrapped is readonly")

  if private_access and impl.owned_fields.has_key(key):
    adapter.own_data[key] = value
    return

  if gene_interface.props.has_key(key):
    let prop = gene_interface.props[key]
    if prop.readonly:
      raise new_exception(types.Exception, "Property " & $key & " is readonly")
    let mapping = impl.prop_mappings.get_or_default(key, nil)
    if not mapping.is_nil and mapping.kind == AmkHidden:
      raise new_exception(types.Exception, "Property " & $key & " is not accessible")
    if mapping.is_nil:
      if adapter_write_inner_property(adapter.inner, key, value):
        return
      raise new_exception(types.Exception,
        "Adapter field " & adapter_key_name(key) & " has no explicit mapping and wrapped value cannot assign same-name member")

    case mapping.kind
    of AmkRename:
      if adapter_write_inner_property(adapter.inner, mapping.inner_name, value):
        return
      raise new_exception(types.Exception,
        "Adapter field " & adapter_key_name(key) & " maps to unwritable wrapped member " & adapter_key_name(mapping.inner_name))
    of AmkComputed:
      raise new_exception(types.Exception, "Computed property " & $key & " cannot be set")
    of AmkAccessor:
      if mapping.set_fn == NIL:
        raise new_exception(types.Exception, "Adapter field " & adapter_key_name(key) & " does not declare a set accessor")
      discard vm.call_bound_method(bind_adapter_callable(adapter_val, adapter_key_name(key), mapping.set_fn), @[value])
      return
    of AmkHidden:
      raise new_exception(types.Exception, "Property " & $key & " is not accessible")

  if private_access:
    raise new_exception(types.Exception,
      "Adapter-owned field " & adapter_key_name(key) & " is not declared")

  raise new_exception(types.Exception,
    "Property " & $key & " is not declared on interface " & gene_interface.name)

proc adapter_member_key(prop: Value): Key =
  case prop.kind
  of VkString, VkSymbol:
    prop.str.to_key()
  of VkInt:
    ($prop.int64).to_key()
  else:
    raise new_exception(types.Exception, "Invalid adapter property type: " & $prop.kind)

proc adapter_member_or_nil(vm: ptr VirtualMachine, adapter_val: Value, prop: Value): Value =
  let key = adapter_member_key(prop)
  adapter_get_member(vm, adapter_val, key)

proc is_adapter_value*(value: Value): bool {.inline.} =
  value.kind == VkAdapter

proc adapter_get_inner*(value: Value): Value {.inline.} =
  if value.kind == VkAdapter:
    return value.ref.adapter.inner
  return value

proc adapter_get_interface*(value: Value): GeneInterface {.inline.} =
  if value.kind == VkAdapter:
    return value.ref.adapter.gene_interface
  return nil

proc dispatch_adapter_method(vm: ptr VirtualMachine, obj: Value, method_name: string, args: seq[Value]): Value =
  let member = adapter_get_member(vm, obj, method_name.to_key())
  if member == NIL or member == VOID:
    not_allowed("Method " & method_name & " not found on Adapter")
  case member.kind
  of VkFunction:
    vm.exec_method_impl(member, obj, args, vm.frame)
  of VkBoundMethod:
    let bm = member.ref.bound_method
    if bm.`method`.callable.kind == VkFunction:
      vm.exec_method_impl(bm.`method`.callable, bm.self, args, vm.frame)
    else:
      vm.exec_callable(member, args)
  else:
    vm.exec_callable_with_self(member, obj, args)

proc dispatch_adapter_method_kw(vm: ptr VirtualMachine, obj: Value, method_name: string,
                                args: seq[Value], kw_pairs: seq[(Key, Value)]): Value =
  let member = adapter_get_member(vm, obj, method_name.to_key())
  if member == NIL or member == VOID:
    not_allowed("Method " & method_name & " not found on Adapter")
  case member.kind
  of VkFunction:
    vm.exec_method_kw_impl(member, obj, args, kw_pairs, vm.frame)
  of VkBoundMethod:
    let bm = member.ref.bound_method
    if bm.`method`.callable.kind == VkFunction:
      vm.exec_method_kw_impl(bm.`method`.callable, bm.self, args, kw_pairs, vm.frame)
    else:
      if kw_pairs.len > 0:
        not_allowed("Keyword arguments are not supported for adapter bound method kind: " & $bm.`method`.callable.kind)
      vm.exec_callable(member, args)
  else:
    if kw_pairs.len > 0:
      not_allowed("Keyword arguments are not supported for adapter method kind: " & $member.kind)
    vm.exec_callable_with_self(member, obj, args)

proc adapter_internal_get_member*(adapter_internal_val: Value, key: Key): Value =
  raise new_exception(types.Exception, "Adapter internal pseudo-member _geneinternal is retired; declare adapter-owned fields instead")

proc adapter_internal_set_member*(adapter_internal_val: Value, key: Key, value: Value) =
  raise new_exception(types.Exception, "Adapter internal pseudo-member _geneinternal is retired; declare adapter-owned fields instead")

proc adapter_internal_member_or_nil*(adapter_internal_val: Value, prop: Value): Value =
  let key = adapter_member_key(prop)
  adapter_internal_get_member(adapter_internal_val, key)
