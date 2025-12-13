import unittest

import gene/types except Exception
import ./helpers

type
  NativeHandle = ref object of CustomValue
    id: int
    label: string

var native_handle_class {.threadvar.}: Class

proc native_get_id(vm: ptr VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value {.gcsafe, nimcall.} =
  let self = get_positional_arg(args, 0, has_keyword_args)
  let data = cast[NativeHandle](self.get_custom_data("NativeHandle payload missing"))
  data.id.to_value()

suite "Custom Values":
  init_all()
  if native_handle_class.is_nil:
    native_handle_class = new_class("NativeHandle")
    native_handle_class.parent = App.app.object_class.ref.class
    native_handle_class.def_native_method("id", native_get_id)

    var class_ref = new_ref(VkClass)
    class_ref.class = native_handle_class
    App.app.global_ns.ns["NativeHandle".to_key()] = class_ref.to_ref_value()

    let handle_value = new_custom_value(native_handle_class, NativeHandle(id: 41, label: "demo"))
    App.app.global_ns.ns["native_handle".to_key()] = handle_value

  test "custom value exposes class metadata":
    let value = App.app.global_ns.ns["native_handle".to_key()]
    check value.has_object_class()
    check value.get_object_class() == native_handle_class

  test "class metadata accessible through Object.class":
    let handle_value = App.app.global_ns.ns["native_handle".to_key()]
    let class_method = App.app.object_class.ref.class.get_method("class")
    let result = call_native_fn(class_method.callable.ref.native_fn, VM, [handle_value])
    check result.kind == VkClass
    check result.ref.class == native_handle_class

  test "native method dispatch works":
    let handle_value = App.app.global_ns.ns["native_handle".to_key()]
    let id_method = native_handle_class.get_method("id")
    let result = call_native_fn(id_method.callable.ref.native_fn, VM, [handle_value])
    check result == 41.to_value()

  test "Object.is works with custom values":
    let handle_value = App.app.global_ns.ns["native_handle".to_key()]
    let class_value = App.app.global_ns.ns["NativeHandle".to_key()]
    let is_method = App.app.object_class.ref.class.get_method("is")
    let result = call_native_fn(is_method.callable.ref.native_fn, VM, [handle_value, class_value])
    check result == TRUE
