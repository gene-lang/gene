import dynlib, strutils
import ../types

type
  # Function type for extension initialization
  Init* = proc(vm: ptr VirtualMachine): Namespace {.gcsafe, nimcall.}
  
  # Function type for setting globals in extension
  SetGlobals* = proc(vm: ptr VirtualMachine) {.nimcall.}

proc load_extension*(vm: VirtualMachine, path: string): Namespace =
  ## Load a dynamic library extension and return its namespace
  var lib_path = path
  
  # Try adding .so extension if not present
  if not (path.endsWith(".so") or path.endsWith(".dll") or path.endsWith(".dylib")):
    when defined(windows):
      lib_path = path & ".dll"
    elif defined(macosx):
      lib_path = path & ".dylib"
    else:
      lib_path = path & ".so"
  
  let handle = loadLib(lib_path)
  if handle.isNil:
    raise new_exception(types.Exception, "Failed to load extension: " & lib_path)
  
  # Call set_globals to pass VM pointer to extension
  let set_globals = cast[SetGlobals](handle.symAddr("set_globals"))
  if set_globals == nil:
    raise new_exception(types.Exception, "set_globals not found in extension: " & path)
  
  set_globals(vm.addr)
  
  # Call init to get the extension's namespace
  let init = cast[Init](handle.symAddr("init"))
  if init == nil:
    raise new_exception(types.Exception, "init not found in extension: " & path)
  
  result = init(vm.addr)
  if result == nil:
    raise new_exception(types.Exception, "Extension init returned nil: " & path)
  
  

# No longer needed since we use deterministic hashing