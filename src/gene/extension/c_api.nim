# C API implementation for Gene extensions
# This module exports C-compatible functions for use by C extensions

import ../types

# Export value conversion functions
proc gene_to_value_int*(i: int64): Value {.exportc, dynlib.} =
  ## Convert C int64 to Gene Value
  i.to_value()

proc gene_to_value_float*(f: float64): Value {.exportc, dynlib.} =
  ## Convert C double to Gene Value
  f.to_value()

proc gene_to_value_string*(s: cstring): Value {.exportc, dynlib.} =
  ## Convert C string to Gene Value
  if s == nil:
    return NIL
  ($s).to_value()

proc gene_to_value_bool*(b: bool): Value {.exportc, dynlib.} =
  ## Convert C bool to Gene Value
  b.to_value()

proc gene_nil*(): Value {.exportc, dynlib.} =
  ## Get NIL value
  NIL

proc gene_to_int*(v: Value): int64 {.exportc, dynlib.} =
  ## Convert Gene Value to C int64
  if v.kind == VkInt:
    v.to_int()
  else:
    0

proc gene_to_float*(v: Value): float64 {.exportc, dynlib.} =
  ## Convert Gene Value to C double
  case v.kind:
    of VkInt:
      v.to_int().float64
    of VkFloat:
      v.to_float()
    else:
      0.0

proc gene_to_string*(v: Value): cstring {.exportc, dynlib.} =
  ## Convert Gene Value to C string
  if v.kind == VkString:
    cstring(v.str)
  else:
    nil

proc gene_to_bool*(v: Value): bool {.exportc, dynlib.} =
  ## Convert Gene Value to C bool
  v.to_bool()

proc gene_is_nil*(v: Value): bool {.exportc, dynlib.} =
  ## Check if value is NIL
  v == NIL

# Namespace functions
proc gene_new_namespace*(name: cstring): Namespace {.exportc, dynlib.} =
  ## Create a new namespace
  if name == nil:
    new_namespace("extension")
  else:
    new_namespace($name)

proc gene_namespace_set*(ns: Namespace, key: cstring, value: Value) {.exportc, dynlib.} =
  ## Set a value in a namespace
  if ns != nil and key != nil:
    ns[($key).to_key()] = value

proc gene_namespace_get*(ns: Namespace, key: cstring): Value {.exportc, dynlib.} =
  ## Get a value from a namespace
  if ns != nil and key != nil:
    ns[($key).to_key()]
  else:
    NIL

# Function wrapping
proc gene_wrap_native_fn*(fn: NativeFn): Value {.exportc, dynlib.} =
  ## Wrap a C function pointer as a Gene Value
  let r = new_ref(VkNativeFn)
  r.native_fn = fn
  r.to_ref_value()

# Argument helpers
proc gene_get_arg*(args: ptr Value, arg_count: cint, has_keyword_args: bool, index: cint): Value {.exportc, dynlib.} =
  ## Get positional argument at index
  if args == nil or index < 0:
    return NIL

  # When has_keyword_args=true, args[0] is the keyword map
  # Positional arguments start at args[1]
  let args_array = cast[ptr UncheckedArray[Value]](args)
  let offset = if has_keyword_args: 1 else: 0
  let actual_index = offset + index

  if actual_index >= arg_count:
    return NIL

  return args_array[actual_index]

# Error handling
proc gene_raise_error*(message: cstring) {.exportc, dynlib, noreturn.} =
  ## Raise an exception
  if message == nil:
    raise new_exception(types.Exception, "Unknown error")
  else:
    raise new_exception(types.Exception, $message)

