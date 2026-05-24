when defined(gene_wasm):
  import ../types
  import ../wasm_host_abi

  proc load_extension*(vm: ptr VirtualMachine, path: string): Namespace =
    discard vm
    discard path
    raise_wasm_unsupported("dynamic_extension_loading")
else:
  include ./extension_native
