# Gene WASM Interface
# Provides JavaScript bindings for Gene VM

import gene/types
import gene/parser
import gene/compiler
import gene/vm

# Global VM instance
var global_vm: VirtualMachine = nil

# Initialize the VM
proc init_vm*() {.exportc.} =
  if global_vm.is_nil:
    global_vm = new_vm()

# Evaluate Gene code and return result as string
proc eval_gene*(code: cstring): cstring {.exportc.} =
  try:
    if global_vm.isNil:
      init_vm()

    # Parse the code
    let parsed = parse_string($code)

    # Compile to bytecode
    let instructions = parse_and_compile(parsed, global_vm)

    # Execute
    let result = global_vm.exec(instructions)

    # Convert result to string
    return cstring($result)
  except CatchableError as e:
    return cstring("Error: " & e.msg)

# Reset the VM state
proc reset_vm*() {.exportc.} =
  global_vm = new_vm()

# Get last error
var last_error: string = ""

proc get_last_error*(): cstring {.exportc.} =
  return cstring(last_error)

# Version info
proc get_version*(): cstring {.exportc.} =
  return cstring("Gene WASM v0.1.0")
