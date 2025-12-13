include ../src/gene/extension/boilerplate

type
  Extension2 = ref object of CustomValue
    name: string

proc new_extension2*(vm: ptr VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value {.gcsafe, nimcall.} =
  let r = new_ref(VkCustom)
  r.custom_data = Extension2(
    name: if arg_count > 0: get_positional_arg(args, 0, has_keyword_args).str else: ""
  )
  result = r.to_ref_value()

proc extension2_name*(vm: ptr VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value {.gcsafe, nimcall.} =
  if arg_count > 0 and get_positional_arg(args, 0, has_keyword_args).kind == VkCustom:
    let ext = cast[Extension2](get_positional_arg(args, 0, has_keyword_args).ref.custom_data)
    return ext.name.to_value()
  "".to_value()

{.push dynlib exportc.}

proc init*(vm: ptr VirtualMachine): Namespace =
  result = new_namespace("extension2")
  
  # Register functions
  var new_ext2_ref = new_ref(VkNativeFn)
  new_ext2_ref.native_fn = new_extension2
  result["new_extension2".to_key()] = new_ext2_ref.to_ref_value()
  
  var ext2_name_ref = new_ref(VkNativeFn)
  ext2_name_ref.native_fn = extension2_name
  result["extension2_name".to_key()] = ext2_name_ref.to_ref_value()

{.pop.}
