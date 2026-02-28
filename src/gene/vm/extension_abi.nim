## Stable native extension ABI for gene-old.
##
## Extensions must export:
##   proc gene_init(host: ptr GeneHostAbi): int32 {.cdecl, exportc, dynlib.}

import ../types

const
  GENE_EXT_ABI_VERSION* = 3'u32

type
  GeneExtStatus* = enum
    GeneExtOk = 0
    GeneExtErr = 1
    GeneExtAbiMismatch = 2

  GeneHostLogFn* = proc(level: int32, logger_name: cstring, message: cstring) {.cdecl, gcsafe.}
  GeneHostSchedulerTickFn* = proc(vm_user_data: pointer, callback_user_data: pointer) {.cdecl, gcsafe.}
  GeneHostRegisterSchedulerCallbackFn* = proc(callback: GeneHostSchedulerTickFn, callback_user_data: pointer): int32 {.cdecl, gcsafe.}

  GeneHostAbi* {.bycopy.} = object
    abi_version*: uint32
    user_data*: pointer            ## host-owned context (ptr VirtualMachine)
    app_value*: Value
    symbols_data*: pointer         ## ptr ManagedSymbols
    log_message_fn*: GeneHostLogFn
    register_scheduler_callback_fn*: GeneHostRegisterSchedulerCallbackFn
    result_namespace*: ptr Namespace

  GeneExtensionInitFn* = proc(host: ptr GeneHostAbi): int32 {.cdecl.}

proc apply_extension_host_context*(host: ptr GeneHostAbi): ptr VirtualMachine =
  ## Synchronize extension-local globals with host runtime state.
  if host == nil:
    return nil
  let vm = cast[ptr VirtualMachine](host.user_data)
  if host.symbols_data != nil:
    SYMBOLS_SHARED = cast[ptr ManagedSymbols](host.symbols_data)
    SYMBOLS = SYMBOLS_SHARED[]
  if host.app_value != NIL:
    App = host.app_value
  vm

proc run_extension_vm_created_callbacks*() =
  ## Execute extension-local VM-created callbacks after host context is applied.
  for callback in VmCreatedCallbacks:
    callback()
