## Interface and Adapter VM operations
##
## This module handles the runtime execution of interface definitions,
## implementations, and adapter creation/access.

import tables
import ../types

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
  let interface_name = name.str
  let gene_interface = new_interface(interface_name, vm.cu.module_path)

  let r = new_ref(VkInterface)
  r.gene_interface = gene_interface
  let v = r.to_ref_value()

  vm.frame.ns[interface_name.to_key()] = v
  vm.frame.push(v)

proc exec_interface_method(vm: ptr VirtualMachine, name: Value) =
  let interface_val = vm.frame.current()
  if interface_val.kind != VkInterface:
    raise new_exception(types.Exception, "interface method definition requires an interface context")
  interface_val.ref.gene_interface.add_method(name.str)

proc exec_interface_prop(vm: ptr VirtualMachine, name: Value, readonly: bool) =
  let interface_val = vm.frame.current()
  if interface_val.kind != VkInterface:
    raise new_exception(types.Exception, "interface prop definition requires an interface context")
  interface_val.ref.gene_interface.add_prop(name.str, readonly = readonly)

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
    vm.frame.push(impl_target)
    return

  let adapter = new_adapter(gene_interface, inner, impl)
  let adapter_val = new_adapter_value(adapter)
  vm.frame.push(adapter_val)

  if impl.ctor != NIL:
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

  if key == "_genevalue".to_key():
    raise new_exception(types.Exception, "Adapter pseudo-member _genevalue is retired; use _wrapped inside adapter implementation bodies")

  if key == "_geneinternal".to_key():
    raise new_exception(types.Exception, "Adapter pseudo-member _geneinternal is retired; declare adapter-owned fields instead")

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
  if key == "_genevalue".to_key():
    raise new_exception(types.Exception, "Adapter pseudo-member _genevalue is retired; use _wrapped inside adapter implementation bodies")
  if key == "_geneinternal".to_key():
    raise new_exception(types.Exception, "Adapter pseudo-member _geneinternal is retired; declare adapter-owned fields instead")

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
