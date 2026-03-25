## Interface and Adapter VM operations
##
## This module handles the runtime execution of interface definitions,
## implementations, and adapter creation/access.

import tables
import ../types
import ../logging_core

const AdapterLogger = "gene/vm/adapter"

proc get_or_create_interface_class(vm: ptr VirtualMachine): Class =
  ## Get or create the Interface class
  if not App.is_nil and App.kind == VkApplication and App.app.interface_class.kind == VkClass:
    return App.app.interface_class.ref.class
  
  # Create the Interface class if it doesn't exist
  let object_class = App.app.object_class.ref.class
  result = new_class("Interface", object_class)
  
  # Store it in the app
  let r = new_ref(VkClass)
  r.class = result
  App.app.interface_class = r.to_ref_value()

proc get_or_create_adapter_class(vm: ptr VirtualMachine): Class =
  ## Get or create the Adapter class
  if not App.is_nil and App.kind == VkApplication and App.app.adapter_class.kind == VkClass:
    return App.app.adapter_class.ref.class
  
  # Create the Adapter class if it doesn't exist
  let object_class = App.app.object_class.ref.class
  result = new_class("Adapter", object_class)
  
  # Store it in the app
  let r = new_ref(VkClass)
  r.class = result
  App.app.adapter_class = r.to_ref_value()

proc exec_interface(vm: ptr VirtualMachine, name: Value) =
  ## Execute IkInterface instruction - create an interface
  let interface_name = name.str
  let interface = new_interface(interface_name, vm.cu.module_path)
  
  # Create the interface value
  let r = new_ref(VkInterface)
  r.interface = interface
  let v = r.to_ref_value()
  
  # Store in current namespace
  vm.frame.ns[interface_name.to_key()] = v
  vm.frame.push(v)

proc exec_implement(vm: ptr VirtualMachine, interface_name: Value, is_external: bool) =
  ## Execute IkImplement instruction - register an implementation
  ## 
  ## For inline: current class is on the frame
  ## For external: target class is on the stack
  
  var target_class_val: Value
  var target_class: Class
  
  if is_external:
    target_class_val = vm.frame.pop()
    if target_class_val.kind == VkClass:
      target_class = target_class_val.ref.class
    else:
      raise new_exception(types.Exception, "implement requires a class, got " & $target_class_val.kind)
  else:
    # Inline implementation - get current class from frame
    if vm.frame.target.kind == VkClass:
      target_class = vm.frame.target.ref.class
    else:
      raise new_exception(types.Exception, "inline implement can only be used inside a class")
  
  # Look up the interface
  let interface_key = interface_name.str.to_key()
  var interface_val = vm.frame.ns.get_value(interface_key)
  if interface_val.is_nil or interface_val.kind != VkInterface:
    # Try parent namespaces
    var ns = vm.frame.ns.parent
    while not ns.is_nil:
      interface_val = ns.members.get_or_default(interface_key, NIL)
      if not interface_val.is_nil and interface_val.kind == VkInterface:
        break
      ns = ns.parent
  
  if interface_val.is_nil or interface_val.kind != VkInterface:
    raise new_exception(types.Exception, "Interface not found: " & interface_name.str)
  
  let interface = interface_val.ref.interface
  
  # Create implementation
  let impl = new_implementation(interface, target_class, ItkClass)
  
  # Register as inline implementation (no adapter wrapper needed)
  register_inline_implementation(target_class.name, interface.name)
  
  # Store implementation on the class
  # For now, we store it in the class's members for later lookup
  let impl_key = ("_impl_" & interface.name).to_key()
  let impl_r = new_ref(VkCustom)
  impl_r.custom_data = impl
  target_class.members[impl_key] = impl_r.to_ref_value()
  
  vm.frame.push(NIL)

proc exec_adapter(vm: ptr VirtualMachine) =
  ## Execute IkAdapter instruction - create an adapter wrapper
  ## Stack: [interface, inner_value]
  
  let inner = vm.frame.pop()
  let interface_val = vm.frame.pop()
  
  if interface_val.kind != VkInterface:
    raise new_exception(types.Exception, "adapter requires an interface, got " & $interface_val.kind)
  
  let interface = interface_val.ref.interface
  
  # Check if inner value has an inline implementation
  var inner_class: Class = nil
  if inner.kind == VkInstance:
    inner_class = inner.instance_class
  elif inner.kind == VkCustom and inner.ref.custom_class != nil:
    inner_class = inner.ref.custom_class
  elif inner.kind == VkClass:
    inner_class = inner.ref.class
  
  # If the class has an inline implementation, return the value directly
  if inner_class != nil and has_inline_implementation(inner_class.name, interface.name):
    vm.frame.push(inner)
    return
  
  # Look for external implementation
  var impl: Implementation = nil
  if inner_class != nil:
    impl = find_implementation(inner_class.name, interface)
  
  if impl.is_nil:
    # Check for built-in types
    let type_name = case inner.kind
      of VkArray: "Array"
      of VkMap: "Map"
      of VkString: "String"
      of VkInt: "Int"
      of VkFloat: "Float"
      of VkBool: "Bool"
      of VkGene: "Gene"
      else: ""
    
    if type_name.len > 0:
      impl = find_implementation(type_name, interface)
  
  if impl.is_nil:
    raise new_exception(types.Exception, 
      "No implementation found for interface " & interface.name & 
      " on type " & (if inner_class != nil: inner_class.name else: $inner.kind))
  
  # Create adapter
  let adapter = new_adapter(interface, inner, impl)
  
  # Create adapter value
  let r = new_ref(VkAdapter)
  r.adapter = adapter
  vm.frame.push(r.to_ref_value())

proc adapter_get_member(vm: ptr VirtualMachine, adapter: Adapter, key: Key): Value =
  ## Get a member from an adapter
  ## This handles the mapping from interface members to inner object members
  
  let interface = adapter.interface
  let impl = adapter.implementation
  
  # Check if it's a property
  if interface.props.has_key(key):
    let mapping = impl.prop_mappings.get_or_default(key, nil)
    if mapping.is_nil:
      # Default: direct access to inner object with same name
      return adapter.inner.get_member(key)
    
    case mapping.kind
    of AmkRename:
      return adapter.inner.get_member(mapping.inner_name)
    of AmkComputed:
      # Call the compute function with inner value as argument
      return vm.exec_callable(mapping.compute_fn, @[adapter.inner])
    of AmkHidden:
      raise new_exception(types.Exception, "Property " & $key & " is not accessible")
  
  # Check if it's a method
  if interface.methods.has_key(key):
    let mapping = impl.method_mappings.get_or_default(key, nil)
    if mapping.is_nil:
      # Default: direct access to inner object's method
      let method_val = adapter.inner.get_member(key)
      if not method_val.is_nil:
        return method_val
      # Try to find the method on the inner object's class
      if adapter.inner.kind == VkInstance:
        let inner_class = adapter.inner.instance_class
        let m = inner_class.get_method(key)
        if not m.is_nil:
          # Return a bound method
          var bm = BoundMethod(self: adapter.inner, method: m)
          let r = new_ref(VkBoundMethod)
          r.bound_method = bm
          return r.to_ref_value()
      raise new_exception(types.Exception, "Method " & $key & " not found on inner object")
    
    case mapping.kind
    of AmkRename:
      let method_val = adapter.inner.get_member(mapping.inner_name)
      if not method_val.is_nil:
        return method_val
      # Try to find the renamed method on the inner object's class
      if adapter.inner.kind == VkInstance:
        let inner_class = adapter.inner.instance_class
        let m = inner_class.get_method(mapping.inner_name)
        if not m.is_nil:
          var bm = BoundMethod(self: adapter.inner, method: m)
          let r = new_ref(VkBoundMethod)
          r.bound_method = bm
          return r.to_ref_value()
      raise new_exception(types.Exception, "Method " & $mapping.inner_name & " not found on inner object")
    of AmkComputed:
      # Return the computed function directly
      return mapping.compute_fn
    of AmkHidden:
      raise new_exception(types.Exception, "Method " & $key & " is not accessible")
  
  # Check adapter's own data
  if adapter.own_data.has_key(key):
    return adapter.own_data[key]
  
  # Not found
  return NIL

proc adapter_set_member(adapter: Adapter, key: Key, value: Value) =
  ## Set a member on an adapter
  ## Only adapter's own data can be set, not mapped properties
  
  let interface = adapter.interface
  
  # Check if it's a property
  if interface.props.has_key(key):
    let prop = interface.props[key]
    if prop.readonly:
      raise new_exception(types.Exception, "Property " & $key & " is readonly")
    # Store in adapter's own data
    adapter.own_data[key] = value
    return
  
  # Store in adapter's own data
  adapter.own_data[key] = value

proc is_adapter_value*(value: Value): bool {.inline.} =
  ## Check if a value is an adapter
  value.kind == VkAdapter

proc adapter_get_inner*(value: Value): Value {.inline.} =
  ## Get the inner value from an adapter
  if value.kind == VkAdapter:
    return value.ref.adapter.inner
  return value

proc adapter_get_interface*(value: Value): Interface {.inline.} =
  ## Get the interface from an adapter
  if value.kind == VkAdapter:
    return value.ref.adapter.interface
  return nil
