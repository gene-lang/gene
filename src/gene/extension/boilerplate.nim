# Boilerplate for Gene VM extensions
# All extensions should include this file

import ../types

# Global VM pointer set by the main program
var VM*: ptr VirtualMachine

proc set_globals*(vm: ptr VirtualMachine) {.exportc, dynlib.} =
  ## Called by the main program to set global VM pointer
  VM = vm
  # Replace the local symbol table with the shared one
  if vm.symbols != nil:
    SYMBOLS = vm.symbols[]

# Helper to create native function value
proc wrap_native_fn*(fn: NativeFn): Value =
  let r = new_ref(VkNativeFn)
  r.native_fn = fn
  return r.to_ref_value()

# Wrappers for exception handling
template wrap_exception*(body: untyped): untyped =
  try:
    body
  except CatchableError as e:
    raise new_exception(types.Exception, e.msg)