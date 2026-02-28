include ../src/gene/extension/boilerplate
import ../src/gene/vm/extension_abi

type
  Extension = ref object of CustomValue
    i: int
    s: string

# Create extension class
var ExtensionClass {.threadvar.}: Class

proc test*(vm: ptr VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value {.gcsafe, nimcall.} =
  if arg_count > 0:
    get_positional_arg(args, 0, has_keyword_args)
  else:
    1.to_value()

proc new_extension*(vm: ptr VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value {.gcsafe, nimcall.} =
  let r = new_ref(VkCustom)
  r.custom_data = Extension(
    i: if arg_count > 0: get_positional_arg(args, 0, has_keyword_args).to_int() else: 0,
    s: if arg_count > 1: get_positional_arg(args, 1, has_keyword_args).str else: ""
  )
  r.custom_class = ExtensionClass
  result = r.to_ref_value()

proc get_i*(vm: ptr VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value {.gcsafe, nimcall.} =
  if arg_count > 0 and get_positional_arg(args, 0, has_keyword_args).kind == VkCustom:
    let ext = cast[Extension](get_positional_arg(args, 0, has_keyword_args).ref.custom_data)
    return ext.i.to_value()
  0.to_value()

proc get_i_method*(vm: ptr VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value {.gcsafe, nimcall.} =
  # Self is now the first argument in args
  if arg_count > 0:
    let self = get_positional_arg(args, 0, has_keyword_args)
    if self.kind == VkCustom:
      let ext = cast[Extension](self.ref.custom_data)
      return ext.i.to_value()
  0.to_value()

{.push dynlib exportc.}

proc init*(vm: ptr VirtualMachine): Namespace =
  result = new_namespace("extension")
  
  # Register a simple test function first
  var test_ref = new_ref(VkNativeFn)
  test_ref.native_fn = test
  let test_key = "test".to_key()
  result[test_key] = test_ref.to_ref_value()
  
  # For now, skip class creation as it requires App.app which might not be accessible
  # Just register the functions
  
  # Register remaining functions
  var new_ext_ref = new_ref(VkNativeFn)
  new_ext_ref.native_fn = new_extension
  result["new_extension".to_key()] = new_ext_ref.to_ref_value()
  
  var get_i_ref = new_ref(VkNativeFn)
  get_i_ref.native_fn = get_i
  result["get_i".to_key()] = get_i_ref.to_ref_value()

proc gene_init*(host: ptr GeneHostAbi): int32 {.cdecl.} =
  if host == nil:
    return int32(GeneExtErr)
  if host.abi_version != GENE_EXT_ABI_VERSION:
    return int32(GeneExtAbiMismatch)
  let vm = apply_extension_host_context(host)
  run_extension_vm_created_callbacks()
  let ns = init(vm)
  if host.result_namespace != nil:
    host.result_namespace[] = ns
  if ns == nil:
    return int32(GeneExtErr)
  int32(GeneExtOk)

{.pop.}
