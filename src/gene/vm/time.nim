# Time module for Gene VM
import times
import ../types

proc init_time_ns*(): Namespace =
  result = new_namespace("time")
  
  # Add time/now function
  proc time_now(vm: VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value =
    # Return current time as a float (seconds since epoch)
    let now = epochTime()
    return now.to_value()

  let now_ref = new_ref(VkNativeFn)
  now_ref.native_fn = time_now
  result["now".to_key()] = now_ref.to_ref_value()
  
  # Add time/sleep function
  proc time_sleep(vm: VirtualMachine, args: ptr UncheckedArray[Value], arg_count: int, has_keyword_args: bool): Value =
    if arg_count < 1:
      raise new_exception(types.Exception, "sleep requires 1 argument")

    let duration = get_positional_arg(args, 0, has_keyword_args)
    case duration.kind:
      of VkInt:
        sleep(duration.int64.int * 1000)  # Convert seconds to milliseconds
      of VkFloat:
        sleep((duration.float64 * 1000).int)  # Convert seconds to milliseconds
      else:
        raise new_exception(types.Exception, "sleep requires a number")

    return NIL

  let sleep_ref = new_ref(VkNativeFn)
  sleep_ref.native_fn = time_sleep
  result["sleep".to_key()] = sleep_ref.to_ref_value()