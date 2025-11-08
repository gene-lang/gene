import std/math, random
import ../types

# Math functions for the Gene standard library

# Absolute value
proc math_abs*(vm: VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value =
  if arg_count < 1:
    raise new_exception(types.Exception, "abs requires 1 argument")

  let value = get_positional_arg(args, 0, has_keyword_args)
  case value.kind:
    of VkInt:
      return abs(value.int64).to_value()
    of VkFloat:
      return abs(value.float64).to_value()
    else:
      raise new_exception(types.Exception, "abs requires a numeric argument")

# Square root
proc math_sqrt*(vm: VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value =
  if arg_count < 1:
    raise new_exception(types.Exception, "sqrt requires 1 argument")

  let value = get_positional_arg(args, 0, has_keyword_args)
  case value.kind:
    of VkInt:
      return sqrt(value.int64.float64).to_value()
    of VkFloat:
      return sqrt(value.float64).to_value()
    else:
      raise new_exception(types.Exception, "sqrt requires a numeric argument")

# Power
proc math_pow*(vm: VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value =
  if arg_count < 2:
    raise new_exception(types.Exception, "pow requires 2 arguments (base, exponent)")

  let base = get_positional_arg(args, 0, has_keyword_args)
  let exp = get_positional_arg(args, 1, has_keyword_args)

  var base_val: float64
  var exp_val: float64

  case base.kind:
    of VkInt:
      base_val = base.int64.float64
    of VkFloat:
      base_val = base.float64
    else:
      raise new_exception(types.Exception, "pow base must be numeric")

  case exp.kind:
    of VkInt:
      exp_val = exp.int64.float64
    of VkFloat:
      exp_val = exp.float64
    else:
      raise new_exception(types.Exception, "pow exponent must be numeric")

  return pow(base_val, exp_val).to_value()

# Trigonometric functions
proc math_sin*(vm: VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value =
  if arg_count < 1:
    raise new_exception(types.Exception, "sin requires 1 argument")

  let value = get_positional_arg(args, 0, has_keyword_args)
  case value.kind:
    of VkInt:
      return sin(value.int64.float64).to_value()
    of VkFloat:
      return sin(value.float64).to_value()
    else:
      raise new_exception(types.Exception, "sin requires a numeric argument")

proc math_cos*(vm: VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value =
  if arg_count < 1:
    raise new_exception(types.Exception, "cos requires 1 argument")

  let value = get_positional_arg(args, 0, has_keyword_args)
  case value.kind:
    of VkInt:
      return cos(value.int64.float64).to_value()
    of VkFloat:
      return cos(value.float64).to_value()
    else:
      raise new_exception(types.Exception, "cos requires a numeric argument")

proc math_tan*(vm: VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value =
  if arg_count < 1:
    raise new_exception(types.Exception, "tan requires 1 argument")

  let value = get_positional_arg(args, 0, has_keyword_args)
  case value.kind:
    of VkInt:
      return tan(value.int64.float64).to_value()
    of VkFloat:
      return tan(value.float64).to_value()
    else:
      raise new_exception(types.Exception, "tan requires a numeric argument")

# Logarithms
proc math_log*(vm: VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value =
  if arg_count < 1:
    raise new_exception(types.Exception, "log requires 1 argument")

  let value = get_positional_arg(args, 0, has_keyword_args)
  case value.kind:
    of VkInt:
      return ln(value.int64.float64).to_value()
    of VkFloat:
      return ln(value.float64).to_value()
    else:
      raise new_exception(types.Exception, "log requires a numeric argument")

proc math_log10*(vm: VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value =
  if arg_count < 1:
    raise new_exception(types.Exception, "log10 requires 1 argument")

  let value = get_positional_arg(args, 0, has_keyword_args)
  case value.kind:
    of VkInt:
      return log10(value.int64.float64).to_value()
    of VkFloat:
      return log10(value.float64).to_value()
    else:
      raise new_exception(types.Exception, "log10 requires a numeric argument")

# Rounding functions
proc math_floor*(vm: VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value =
  if arg_count < 1:
    raise new_exception(types.Exception, "floor requires 1 argument")

  let value = get_positional_arg(args, 0, has_keyword_args)
  case value.kind:
    of VkInt:
      return value
    of VkFloat:
      return floor(value.float64).to_value()
    else:
      raise new_exception(types.Exception, "floor requires a numeric argument")

proc math_ceil*(vm: VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value =
  if arg_count < 1:
    raise new_exception(types.Exception, "ceil requires 1 argument")

  let value = get_positional_arg(args, 0, has_keyword_args)
  case value.kind:
    of VkInt:
      return value
    of VkFloat:
      return ceil(value.float64).to_value()
    else:
      raise new_exception(types.Exception, "ceil requires a numeric argument")

proc math_round*(vm: VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value =
  if arg_count < 1:
    raise new_exception(types.Exception, "round requires 1 argument")

  let value = get_positional_arg(args, 0, has_keyword_args)
  case value.kind:
    of VkInt:
      return value
    of VkFloat:
      return round(value.float64).to_value()
    else:
      raise new_exception(types.Exception, "round requires a numeric argument")

# Min/Max
proc math_min*(vm: VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value =
  if arg_count < 2:
    raise new_exception(types.Exception, "min requires at least 2 arguments")

  var min_val = get_positional_arg(args, 0, has_keyword_args)
  for i in 1..<get_positional_count(arg_count, has_keyword_args):
    let val = get_positional_arg(args, i, has_keyword_args)
    if val.kind == VkInt and min_val.kind == VkInt:
      if val.int64 < min_val.int64:
        min_val = val
    elif (val.kind == VkFloat or val.kind == VkInt) and (min_val.kind == VkFloat or min_val.kind == VkInt):
      let val_f = if val.kind == VkFloat: val.float64 else: val.int64.float64
      let min_f = if min_val.kind == VkFloat: min_val.float64 else: min_val.int64.float64
      if val_f < min_f:
        min_val = val

  return min_val

proc math_max*(vm: VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value =
  if arg_count < 2:
    raise new_exception(types.Exception, "max requires at least 2 arguments")

  var max_val = get_positional_arg(args, 0, has_keyword_args)
  for i in 1..<get_positional_count(arg_count, has_keyword_args):
    let val = get_positional_arg(args, i, has_keyword_args)
    if val.kind == VkInt and max_val.kind == VkInt:
      if val.int64 > max_val.int64:
        max_val = val
    elif (val.kind == VkFloat or val.kind == VkInt) and (max_val.kind == VkFloat or max_val.kind == VkInt):
      let val_f = if val.kind == VkFloat: val.float64 else: val.int64.float64
      let max_f = if max_val.kind == VkFloat: max_val.float64 else: max_val.int64.float64
      if val_f > max_f:
        max_val = val

  return max_val

# Random numbers
var rng_initialized = false

proc ensure_rng() =
  if not rng_initialized:
    randomize()
    rng_initialized = true

proc math_random*(vm: VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value =
  ensure_rng()
  return rand(1.0).to_value()

proc math_random_int*(vm: VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value =
  ensure_rng()
  if arg_count < 1:
    raise new_exception(types.Exception, "random_int requires at least 1 argument (max)")

  let max_arg = get_positional_arg(args, 0, has_keyword_args)
  if max_arg.kind != VkInt:
    raise new_exception(types.Exception, "random_int max must be an integer")

  let max_val = max_arg.int64.int

  if arg_count >= 2:
    # Both min and max provided
    let min_arg = get_positional_arg(args, 1, has_keyword_args)
    if min_arg.kind != VkInt:
      raise new_exception(types.Exception, "random_int min must be an integer")
    let min_val = min_arg.int64.int
    return (rand(max_val - min_val) + min_val).int64.to_value()
  else:
    # Only max provided, min is 0
    return rand(max_val).int64.to_value()

# Constants
proc math_pi*(vm: VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value =
  return PI.to_value()

proc math_e*(vm: VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value =
  return E.to_value()

# Register all math functions in a namespace
proc init_math_namespace*(global_ns: Namespace) =
  let math_ns = new_namespace("math")

  # Basic operations
  math_ns["abs".to_key()] = math_abs.to_value()
  math_ns["sqrt".to_key()] = math_sqrt.to_value()
  math_ns["pow".to_key()] = math_pow.to_value()

  # Trigonometric
  math_ns["sin".to_key()] = math_sin.to_value()
  math_ns["cos".to_key()] = math_cos.to_value()
  math_ns["tan".to_key()] = math_tan.to_value()

  # Logarithms
  math_ns["log".to_key()] = math_log.to_value()
  math_ns["log10".to_key()] = math_log10.to_value()

  # Rounding
  math_ns["floor".to_key()] = math_floor.to_value()
  math_ns["ceil".to_key()] = math_ceil.to_value()
  math_ns["round".to_key()] = math_round.to_value()

  # Min/Max
  math_ns["min".to_key()] = math_min.to_value()
  math_ns["max".to_key()] = math_max.to_value()

  # Random
  math_ns["random".to_key()] = math_random.to_value()
  math_ns["random_int".to_key()] = math_random_int.to_value()

  # Constants
  math_ns["PI".to_key()] = PI.to_value()
  math_ns["E".to_key()] = E.to_value()

  global_ns["math".to_key()] = math_ns.to_value()

  # Also add directly to global namespace for convenience
  global_ns["abs".to_key()] = math_abs.to_value()
  global_ns["sqrt".to_key()] = math_sqrt.to_value()
  global_ns["pow".to_key()] = math_pow.to_value()
  global_ns["min".to_key()] = math_min.to_value()
  global_ns["max".to_key()] = math_max.to_value()
  global_ns["floor".to_key()] = math_floor.to_value()
  global_ns["ceil".to_key()] = math_ceil.to_value()
  global_ns["round".to_key()] = math_round.to_value()
  global_ns["random".to_key()] = math_random.to_value()
  global_ns["random_int".to_key()] = math_random_int.to_value()